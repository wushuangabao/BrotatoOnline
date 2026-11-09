extends Reference

# The seat's owner executes shop gameplay. The host mirrors results, not clicks.
# Epoch + revision protect against old visits, duplicate packets and delayed echoes.
var manager = null
var scene_id = 0
var epoch = ""
var revisions = {}
var dirty = {}
var flush_at = 0
var acknowledged = {}
var resend_at = 0

func reset() -> void:
	scene_id = 0
	epoch = ""
	revisions.clear()
	dirty.clear()
	acknowledged.clear()
	flush_at = 0
	resend_at = 0

func _shop():
	var shop = manager._find_shop_node()
	if not manager._is_valid_shop_node(shop):
		return null
	if scene_id != shop.get_instance_id():
		scene_id = shop.get_instance_id()
		epoch = str(scene_id) + ":" + str(OS.get_ticks_usec()) if manager._is_game_host() else ""
		revisions.clear()
		dirty.clear()
		acknowledged.clear()
	return shop

func owns(index: int) -> bool:
	return _shop() != null and not manager._is_game_host() and epoch != "" and manager._is_local_client_player_index(index)

func has_edits(index: int) -> bool:
	return _shop() != null and int(revisions.get(index, 0)) > 0

func is_owned_action(action: String) -> bool:
	return action in ["shop_buy", "shop_lock", "shop_reroll", "shop_combine_weapon", "shop_discard_weapon", "shop_dismantle", "shop_meca_preview", "shop_meca_upgrade"]

func stamp(state: Dictionary) -> void:
	if _shop() != null and manager._is_game_host():
		state["shop_owner_epoch"] = epoch
		state["shop_owner_revision"] = int(revisions.get(int(state.get("player_index", -1)), 0))

func observe(state: Dictionary) -> void:
	if _shop() == null or manager._is_game_host() or not manager._is_local_client_player_index(int(state.get("player_index", -1))):
		return
	var incoming = str(state.get("shop_owner_epoch", ""))
	if incoming != "" and epoch == "":
		epoch = incoming
	if incoming == epoch:
		var index = int(state.player_index)
		revisions[index] = max(int(revisions.get(index, 0)), int(state.get("shop_owner_revision", 0)))
		acknowledged[index] = int(revisions[index])

func acknowledge(message: Dictionary) -> void:
	var index = int(message.get("player_index", -1))
	if owns(index) and str(message.get("shop_owner_epoch", "")) == epoch:
		acknowledged[index] = max(int(acknowledged.get(index, 0)), min(int(revisions.get(index, 0)), int(message.get("shop_owner_revision", 0))))

func keeps_local(state: Dictionary) -> bool:
	var index = int(state.get("player_index", -1))
	if not manager._is_game_host() and _shop() != null and epoch != "":
		var incoming = str(state.get("shop_owner_epoch", ""))
		if incoming != "" and incoming != epoch:
			return true
	# Bootstrap/rejoin receives the host copy once. After the first local edit,
	# snapshots and acknowledgements must never replay or roll back our own work.
	return owns(index) and int(revisions.get(index, 0)) > 0 and str(state.get("shop_owner_epoch", "")) == epoch

func changed(index: int) -> void:
	revisions[index] = int(revisions.get(index, 0)) + 1
	dirty[index] = true
	if flush_at == 0:
		flush_at = OS.get_ticks_msec() + 50

func submit(message: Dictionary, index: int) -> bool:
	if not owns(index):
		return false
	var action = str(message.get("action_type", ""))
	if not action in ["shop_buy", "shop_lock", "shop_reroll", "shop_combine_weapon", "shop_discard_weapon", "shop_dismantle"]:
		return false
	if manager._applying_remote_run_page_action or manager._is_game_start_guard_active():
		return true
	manager._applying_remote_run_page_action = true
	var applied = false
	match action:
		"shop_buy": applied = manager._apply_shop_buy_action(index, message)
		"shop_lock": applied = manager._apply_shop_lock_action(index, message)
		"shop_reroll": applied = manager._apply_shop_reroll_action(index, message)
		"shop_combine_weapon": applied = manager._apply_shop_combine_weapon_action(index, message)
		"shop_discard_weapon": applied = manager._apply_shop_discard_weapon_action(index, message)
		"shop_dismantle": applied = manager._get_dlc_shop_actions().apply_dismantle(_shop(), index, message)
	manager._applying_remote_run_page_action = false
	if applied:
		_sync_local_locks(index)
		manager._install_client_shop_intercepts(_shop(), index)
		manager._intercept_client_shop_item_buttons(_shop()._get_shop_items_container(index), index)
		if action in ["shop_combine_weapon", "shop_discard_weapon"]:
			manager._close_shop_popup_for_player(_shop(), index, message)
		changed(index)
	return true

func _sync_local_locks(index: int) -> void:
	# Lock signals update visuals before the intercepted action. Rebuild from the
	# live cards, using their exact Resources; deserialized copies cannot be unlocked
	# by vanilla's reference-based removal and must not accumulate across waves.
	var locks = []
	for card in _shop()._get_shop_items_container(index)._shop_items:
		if card.active and card.locked and card.item_data != null:
			locks.append([card.item_data, card.wave_value])
	RunData.locked_shop_items[index] = locks

func snapshot(index: int) -> Dictionary:
	var shop = _shop()
	if shop == null or epoch == "":
		return {}
	var state = manager._build_shop_player_state(index, shop, false, false)
	# Full compact owned inventory also carries DLC effects, reroll side effects,
	# bans and currencies. It can supersede any number of earlier local operations.
	var raw = manager._serialize_player_run_data_for_shop_sync(index, manager.SHOP_HELD_ITEMS_SYNC_COMPACT)
	state["run_data"] = manager._compact_player_run_data_for_shop_sync(index, raw, manager.SHOP_HELD_ITEMS_SYNC_COMPACT, true)
	state["run_data_key"] = ""
	state["run_data_full"] = true
	state["force_run_data_repair"] = true
	state["shop_owner_epoch"] = epoch
	state["shop_owner_revision"] = int(revisions.get(index, 0))
	state.erase("shop_state_revision")
	return state

func tick() -> void:
	if not manager._is_game_host() and OS.get_ticks_msec() >= resend_at:
		for index in revisions.keys():
			if owns(index) and int(revisions[index]) > int(acknowledged.get(index, 0)):
				dirty[index] = true
		resend_at = OS.get_ticks_msec() + 1000
	if dirty.empty() or OS.get_ticks_msec() < flush_at or manager._is_game_start_guard_active():
		return
	flush()

func flush() -> void:
	for index in dirty.keys():
		var state = snapshot(index)
		if not state.empty():
			var queue = manager._queued_local_run_page_action_messages
			for i in range(queue.size() - 1, -1, -1):
				if str(queue[i].get("action_type", "")) == "shop_owner_state" and int(queue[i].get("player_index", -1)) == index:
					queue.remove(i)
			manager._queue_local_run_page_action({"msg_type": "run_page_action_sync", "action_type": "shop_owner_state", "screen": "shop", "player_index": index, "owner_state": state})
	dirty.clear()
	flush_at = 0
	resend_at = OS.get_ticks_msec() + 1000

func transition_states() -> Array:
	var result = []
	for index in RunData.get_player_count():
		if owns(index):
			result.append(snapshot(index))
	return result

func accept(index: int, state: Dictionary) -> bool:
	var shop = _shop()
	if not manager._is_game_host() or shop == null or index < 0 or index >= RunData.get_player_count():
		return false
	if str(state.get("shop_owner_epoch", "")) != epoch or int(state.get("current_wave", -1)) != RunData.current_wave:
		return false
	var revision = int(state.get("shop_owner_revision", -1))
	if revision < 0:
		return false
	if revision <= int(revisions.get(index, 0)):
		return true
	if typeof(state.get("run_data", null)) != TYPE_DICTIONARY or state.run_data.empty() or typeof(state.get("shop_items", null)) != TYPE_ARRAY:
		return false
	var copy = state.duplicate(true)
	copy["player_index"] = index
	copy["pressed_go"] = manager._get_node_array_value(shop, "_player_pressed_go_button", index, false)
	copy["force_run_data_repair"] = true
	copy["run_data_key"] = ""
	copy.erase("shop_state_revision")
	var was_applying = manager._applying_remote_run_page_action
	manager._applying_remote_run_page_action = true
	var applied = manager._apply_shop_player_state_to_ui(shop, copy)
	manager._applying_remote_run_page_action = was_applying
	if not applied:
		return false
	# The native slot lock list is needed when the host constructs the next shop.
	manager._replace_client_locked_shop_items_from_host_entries(index, copy.shop_items, true)
	revisions[index] = revision
	manager._mark_host_shop_run_data_dirty(index)
	return true
