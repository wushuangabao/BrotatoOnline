extends Reference

var manager = null
var previews = {}
var client_previews = {}
var client_preview_sources = {}
var pending_preview_sources = {}

func reset() -> void:
	previews.clear()
	client_previews.clear()
	client_preview_sources.clear()
	pending_preview_sources.clear()

func is_action(action: String) -> bool:
	return action in ["shop_dismantle", "shop_meca_preview", "shop_meca_upgrade"]

func wire_popup(shop: Node, player_index: int, intercept: bool) -> void:
	var popup = shop._get_item_popup(player_index)
	if popup == null:
		return
	# The coop scene also binds the button's own visual callbacks to the popup.
	for button in [popup._effect_button_0, popup._effect_button_1]:
		if not is_instance_valid(button):
			continue
		for event in ["focus_entered", "focus_exited", "mouse_entered", "mouse_exited", "pressed"]:
			var method = "_on_ButtonWithIcon_" + event
			if not popup.has_method(method) and button.is_connected(event, popup, method):
				button.disconnect(event, popup, method)
	if intercept:
		if popup.is_connected("item_meca_upgrade_selected", shop, "_on_item_meca_upgrade_selected"):
			popup.disconnect("item_meca_upgrade_selected", shop, "_on_item_meca_upgrade_selected")
		var specs = [["_upgrade_button", "_on_UpgradeButton_pressed", "_on_client_meca_preview_pressed", []], ["_effect_button_0", "_on_EffectButton0_pressed", "_on_client_meca_effect_pressed", [0]], ["_effect_button_1", "_on_EffectButton1_pressed", "_on_client_meca_effect_pressed", [1]]]
		for spec in specs:
			var button = manager._safe_get(popup, spec[0], null)
			if button == null:
				continue
			if button.is_connected("pressed", popup, spec[1]):
				button.disconnect("pressed", popup, spec[1])
			if not button.is_connected("pressed", manager, spec[2]):
				var args = [player_index]
				args.append_array(spec[3])
				button.connect("pressed", manager, spec[2], args)
	else:
		if not popup.is_connected("item_meca_upgrade_selected", manager, "_on_host_meca_upgrade_observed"):
			popup.connect("item_meca_upgrade_selected", manager, "_on_host_meca_upgrade_observed", [player_index])

func request(player_index: int, action: String, choice: int = -1) -> void:
	var shop = manager._find_shop_node()
	if not manager._is_valid_shop_node(shop) or manager._applying_remote_run_page_action:
		return
	var popup = shop._get_item_popup(player_index)
	if popup == null:
		return
	if manager._get_trusted_shop_sync().owns(player_index):
		_request_local_upgrade(shop, popup, player_index, action, choice)
		return
	var weapon = manager._safe_get(popup, "_item_data", null)
	if not (weapon is WeaponData):
		return
	var slot = weapon_slot(player_index, weapon)
	if slot < 0:
		return
	var message = {"msg_type": "run_page_action_sync", "action_type": action, "screen": "shop", "player_index": player_index, "weapon_slot_index": slot, "item_identity": manager._build_shop_item_stable_identity(weapon)}
	if action == "shop_meca_preview":
		pending_preview_sources[player_index] = weapon
	if action == "shop_meca_upgrade":
		var preview = client_previews.get(player_index, {})
		if preview.empty() or client_preview_sources.get(player_index, null) != weapon or not manager._shop_item_matches_stable_identity(weapon, preview.get("source", {})):
			return
		message["preview_id"] = str(preview.get("preview_id", ""))
		message["effect_choice"] = choice
		message["chosen_effect"] = manager._meca_choice_descriptor(popup._pending_upgrade, choice)
		if message.chosen_effect.empty():
			return
	manager._submit_local_shop_action(message, player_index, action)

func _request_local_upgrade(shop, popup, index: int, action: String, choice: int) -> void:
	if manager._is_game_start_guard_active() or not popup._focused or not popup.is_visible_in_tree():
		return
	if action == "shop_meca_preview":
		# Use the native cached random options immediately; the host does not reroll them.
		popup._on_UpgradeButton_pressed()
		return
	if action != "shop_meca_upgrade" or manager._meca_choice_descriptor(popup._pending_upgrade, choice).empty():
		return
	var weapon = popup._item_data
	if not RunData.get_player_weapons(index).has(weapon) or RunData.get_player_meca_parts(index) < weapon.meca_rank + 1:
		return
	var upgraded = DLC2Data.change_effect_option_to_modular_effect(popup._pending_upgrade, choice)
	manager._applying_remote_run_page_action = true
	shop._on_item_meca_upgrade_selected(weapon, upgraded, index)
	manager._applying_remote_run_page_action = false
	if RunData.get_player_weapons(index).has(weapon):
		return
	manager._install_client_shop_intercepts(shop, index)
	var elements = manager._get_shop_inventory_elements(shop, index, true)
	var focus_index = -1
	var identity = manager._build_shop_item_stable_identity(upgraded)
	for i in elements.size():
		if manager._shop_item_matches_stable_identity(elements[i].item, identity):
			focus_index = i
			break
	manager._close_shop_popup_for_player(shop, index, focus_index)
	call_deferred("_focus_local_upgrade", shop, index, upgraded)
	manager._get_trusted_shop_sync().changed(index)

func _focus_local_upgrade(shop, index: int, upgraded) -> void:
	if not manager._is_valid_shop_node(shop) or shop._get_item_popup(index)._focused:
		return
	# Native remove_element queues focus on a neighbouring weapon. Run after that
	# callback, locating the new resource instead of a pre-removal display index.
	var identity = manager._build_shop_item_stable_identity(upgraded)
	for element in manager._get_shop_inventory_elements(shop, index, true):
		if not element.is_queued_for_deletion() and manager._shop_item_matches_stable_identity(element.item, identity):
			Utils.focus_player_control(element, index, Utils.get_focus_emulator(index))
			return

func apply_dismantle(shop: Node, player_index: int, message: Dictionary) -> bool:
	var node = manager._get_shop_item_for_action(shop, player_index, message)
	if not manager._is_live_ref(node) or not (node.item_data is WeaponData) or not node.item_data.is_meca or not bool(node.active):
		return false
	var price = int(node.get_dismantle_price())
	if price < 0 or RunData.get_player_currency(player_index) < price:
		return false
	shop.on_shop_item_dismantled(node, player_index)
	node.deactivate()
	return true

func weapon_slot(player_index: int, weapon) -> int:
	# A full shop repair replaces Resource objects while an open popup can still
	# reference the old one. Weapon family/id alone conflates different upgrades.
	var weapons = RunData.get_player_weapons(player_index)
	var exact = weapons.find(weapon)
	if exact >= 0:
		return exact
	var identity = manager._build_shop_item_stable_identity(weapon)
	var match_index = -1
	for index in weapons.size():
		if manager._shop_item_matches_stable_identity(weapons[index], identity):
			if match_index >= 0:
				# Do not choose arbitrarily between indistinguishable stale copies.
				return -1
			match_index = index
	return match_index

func capture_client_popup(shop: Node, state: Dictionary) -> Dictionary:
	var index = int(state.get("player_index", -1))
	if manager._is_game_host() or not manager._is_local_client_player_index(index) or not manager._is_valid_shop_node(shop):
		return {}
	var popup = shop._get_item_popup(index)
	if popup == null:
		return {}
	var popup_open = popup._focused and popup.is_visible_in_tree()
	var control = manager._safe_get(Utils.get_focus_emulator(index), "focused_control", null)
	var weapon = popup._item_data if popup_open else manager._safe_get(control, "item", null)
	if not (weapon is WeaponData):
		return {}
	return {"index": index, "weapon": weapon, "slot": weapon_slot(index, weapon), "identity": manager._build_shop_item_stable_identity(weapon), "popup_open": popup_open, "control": control}

func rebind_client_popup(shop: Node, context: Dictionary) -> void:
	if context.empty():
		return
	var index = int(context.index)
	var popup = shop._get_item_popup(index)
	var weapons = RunData.get_player_weapons(index)
	var slot = int(context.slot)
	if popup == null or slot < 0 or slot >= weapons.size():
		return
	if context.popup_open and (not popup._focused or popup._item_data != context.weapon):
		return
	if not context.popup_open and popup._focused:
		return
	var weapon = weapons[slot]
	if not manager._shop_item_matches_stable_identity(weapon, context.identity):
		return
	# Rebind unchanged data without display_element/focus: those vanilla methods
	# cancel the pending attribute choice. Keep the exact slot for identical copies.
	var elements = manager._get_shop_inventory_elements(shop, index, true)
	for i in elements.size():
		var element = elements[i]
		if element.item != weapon:
			continue
		if not context.popup_open:
			# A rejection arriving after success may rebuild the inventory again.
			# Restore only destroyed focus, without overriding a newer user selection.
			if element != context.control:
				manager._restore_shop_focus_after_popup_close(shop, index, i)
			return
		popup._item_data = weapon
		popup._attachment = element
		if client_preview_sources.get(index, null) == context.weapon:
			client_preview_sources[index] = weapon
		if pending_preview_sources.get(index, null) == context.weapon:
			pending_preview_sources[index] = weapon
		var popup_manager = shop._popup_manager
		popup_manager._elements_pressed[index] = element
		popup_manager._elements_focused[index] = element
		popup_manager._elements_hovered[index] = element
		return

func finish_client_upgrade(shop: Node, index: int, message: Dictionary) -> void:
	var state = message.get("host_shop_state_after", message.get("host_state_after", message.get("state_after", {})))
	if typeof(state) != TYPE_DICTIONARY or not bool(state.get("host_applied", false)) or not manager._is_valid_shop_node(shop):
		return
	var preview = client_previews.get(index, {})
	if preview.empty() or str(preview.get("preview_id", "")) != str(message.get("preview_id", "")):
		return
	client_previews.erase(index)
	var source_weapon = client_preview_sources.get(index, null)
	client_preview_sources.erase(index)
	var popup = shop._get_item_popup(index)
	# An old confirmation must not close a newly opened, unrelated weapon popup.
	if popup == null or not popup._focused or popup._item_data != source_weapon or not manager._shop_item_matches_stable_identity(popup._item_data, preview.get("source", {})):
		return
	var focus_index = -1
	var elements = manager._get_shop_inventory_elements(shop, index, true)
	for i in elements.size():
		if manager._shop_item_matches_stable_identity(elements[i].item, message.get("meca_upgraded_identity", {})):
			focus_index = i
			break
	manager._close_shop_popup_for_player(shop, index, focus_index)

func _weapon(player_index: int, message: Dictionary):
	var weapons = RunData.get_player_weapons(player_index)
	var index = int(message.get("weapon_slot_index", -1))
	var identity = message.get("item_identity", {})
	if index < 0 or index >= weapons.size() or not manager._shop_item_matches_stable_identity(weapons[index], identity):
		return null
	return weapons[index]

func apply(player_index: int, action: String, message: Dictionary) -> bool:
	if not manager._is_game_host() or player_index < 0 or player_index >= RunData.get_player_count():
		return false
	var shop = manager._find_shop_node()
	if not manager._is_valid_shop_node(shop) or not RunData.enabled_dlcs.has("primal_dread") or not ProgressData.active_update_data.has("primal_dread"):
		return false
	var dlc = ItemService.get_dlc_data_by_id("primal_dread")
	if dlc == null:
		return false
	if action == "shop_dismantle":
		if not apply_dismantle(shop, player_index, message):
			return false
		manager._mark_host_shop_run_data_dirty(player_index)
		return true
	var weapon = _weapon(player_index, message)
	if weapon == null or not ItemService.can_weapon_be_mechanized(weapon):
		return false
	var cost = int(dlc.get_meca_upgrade_cost(weapon))
	if cost <= 0 or RunData.get_player_meca_parts(player_index) < cost:
		return false
	var identity = manager._build_shop_item_stable_identity(weapon)
	if action == "shop_meca_preview":
		var cached = previews.get(player_index, {})
		if cached.empty() or int(cached.get("scene_id", 0)) != shop.get_instance_id() or cached.get("weapon", null) != weapon or not manager._shop_item_matches_stable_identity(weapon, cached.get("source", {})):
			var preview = dlc.meca_item(weapon, player_index)
			var option_count = 0
			for effect in preview.effects:
				if effect is EffectOption:
					option_count += 1
			if option_count != 2:
				return false
			cached = {"scene_id": shop.get_instance_id(), "weapon": weapon, "source": identity, "preview": preview, "preview_id": str(shop.get_instance_id()) + ":" + str(OS.get_ticks_usec())}
			previews[player_index] = cached
		message["meca_upgrade_preview"] = {"source": cached.source, "preview_id": cached.preview_id, "weapon": manager._serialize_item_parent_data(cached.preview)}
		return true
	if action != "shop_meca_upgrade":
		return false
	var cached = previews.get(player_index, {})
	var choice = int(message.get("effect_choice", -1))
	if cached.empty() or choice < 0 or choice > 1 or str(message.get("preview_id", "")) != str(cached.preview_id) or int(cached.scene_id) != shop.get_instance_id() or cached.weapon != weapon or not manager._shop_item_matches_stable_identity(weapon, cached.source):
		return false
	if not manager._matches_meca_choice(cached.preview, choice, message):
		return false
	var upgraded = DLC2Data.change_effect_option_to_modular_effect(cached.preview, choice)
	# Consume before the native mutation so duplicate confirmations cannot spend twice.
	previews.erase(player_index)
	shop._on_item_meca_upgrade_selected(weapon, upgraded, player_index)
	message["meca_upgraded_identity"] = manager._build_shop_item_stable_identity(upgraded)
	manager._mark_host_shop_run_data_dirty(player_index)
	return not RunData.get_player_weapons(player_index).has(weapon)

func apply_client_state(shop: Node, state: Dictionary) -> void:
	var index = int(state.get("player_index", -1))
	if index < 0 or index >= RunData.get_player_count():
		return
	if state.has("meca_parts"):
		var parts = int(state.meca_parts)
		RunData.players_data[index].meca_parts = parts
		RunData.emit_signal("meca_parts_changed", parts, index)
	if state.has("dismantle_savings"):
		RunData.set_tracked_value(index, Keys.item_titanium_excess_hash, state.dismantle_savings)
	if manager._is_game_host() or not manager._is_local_client_player_index(index) or not state.has("meca_upgrade_preview"):
		return
	var preview = state.meca_upgrade_preview
	var popup = shop._get_item_popup(index)
	if typeof(preview) != TYPE_DICTIONARY or popup == null or not popup._focused or not popup.is_visible_in_tree() or pending_preview_sources.get(index, null) != popup._item_data or not manager._shop_item_matches_stable_identity(manager._safe_get(popup, "_item_data", null), preview.get("source", {})):
		return
	var weapon = manager._resolve_item_parent_data(preview.get("weapon", {}), false)
	if not (weapon is WeaponData) or not popup.has_meca_upgrade_ui() or popup._get_effect_options(weapon).size() != 2:
		return
	client_previews[index] = preview.duplicate(true)
	client_preview_sources[index] = popup._item_data
	popup._upgrade_preview_cache[popup._item_data.get_instance_id()] = weapon
	popup._on_UpgradeButton_pressed()
