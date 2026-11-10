extends Node

# Per-battle cumulative deltas, not absolute stats: equipment and host economy
# remain intact. Reliable reports are replay-safe and fenced by battle generation.
var totals = {}
var epoch = ""
var sealed = false
var finals = {}
var waiting_main = null
var released_scene = 0
var poll = 0.0
var last_economy_stamp = -1
var tracking_seen = {}
var local_started = {}
var acknowledged = {}
var last_report_msec = -1000
var reports_sent = 0
var last_seal_msec = -1000
var suspended = {}
var ready_tracking = {}
var waiting_since_msec = 0
var waiting_overlay = null
var paused_for_final = false
var was_paused_before_final = false

func session():
	return get_parent().get_node("BrotatoOnlineSessionManager")

func active() -> bool:
	return session().is_online_session_active()

func owns(index: int) -> bool:
	return session()._get_slot_manager().get_local_player_indices().has(index)

func current_epoch() -> String:
	var s = session()
	var start = s._host_current_battle_start_id if s._is_game_host() else s._client_active_battle_start_id
	return s._get_wire_session_id() + ":" + str(start) + ":" + str(RunData.current_wave) + ":" + str(RunData.retries)

func ensure_epoch() -> void:
	var next = current_epoch()
	if next == epoch:
		return
	_release_final_pause()
	epoch = next
	totals.clear()
	tracking_seen.clear()
	ready_tracking.clear()
	local_started.clear()
	acknowledged.clear()
	last_report_msec = -1000
	last_seal_msec = -1000
	finals.clear()
	sealed = false
	waiting_main = null
	released_scene = 0
	last_economy_stamp = -1

func suspend_owner_state() -> void:
	if not active() or session()._is_game_host():
		return
	var records = {}
	for index in session()._get_slot_manager().get_local_player_indices():
		observe_tracking(index)
		records[index] = get_total(index)
	suspended = {"epoch":epoch, "owner":session()._self_steam_id, "records":records}

func restore_rejoined_player(index: int, player_data, incoming: Dictionary, effects_merged: bool) -> void:
	if suspended.empty() or str(suspended.owner) != session()._self_steam_id or not suspended.records.has(index) or not owns(index):
		return
	# Only the exact same authoritative attempt may reuse a disconnected journal.
	# A retry, different room, or another owner must use its new RunData baseline.
	var marker = incoming.get("online_movement_rewards", {})
	if str(marker.get("epoch", "")) != str(suspended.epoch):
		return
	ensure_epoch()
	if epoch != str(suspended.epoch):
		return
	var saved = suspended.records[index]
	totals[index] = saved.duplicate(true)
	apply_tracking(index, saved.tracked)
	tracking_seen[index] = capture(index).tracked
	if not effects_merged:
		merge_pending_effects(index, player_data, incoming)
	ready_tracking[index] = saved.tracked.duplicate(true)
	suspended.records.erase(index)
	player_data.gold += int(saved.gold) - int(marker.get("gold", 0))
	local_started[index] = true

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	get_tree().connect("node_added", self, "_on_scene_added")

func _on_scene_added(node: Node) -> void:
	if str(node.filename) == "res://main.tscn":
		node.connect("ready", self, "_restore_tracking_after_scene_ready", [], CONNECT_ONESHOT)

func _restore_tracking_after_scene_ready() -> void:
	ensure_epoch()
	# Native scene initialization resets per-wave counters. A reconnect is not a
	# new wave: restore once after that initialization, before any gameplay ticks.
	for index in ready_tracking:
		if owns(index):
			apply_tracking(index, ready_tracking[index])
			tracking_seen[index] = capture(index).tracked
	ready_tracking.clear()

func _show_waiting_notice(main: Node) -> void:
	if is_instance_valid(waiting_overlay) or OS.get_ticks_msec() - waiting_since_msec < 1000:
		return
	waiting_overlay = CanvasLayer.new()
	waiting_overlay.layer = 90
	main.add_child(waiting_overlay)
	var label = Label.new()
	label.name = "MovementRewardsWaiting"
	label.anchor_right = 1.0
	label.margin_left = 24
	label.margin_right = -24
	label.margin_top = 170
	label.margin_bottom = 270
	label.align = Label.ALIGN_CENTER
	label.autowrap = true
	label.text = get_parent().get_node("BrotatoOnlineI18n").get_text("BROTATO_ONLINE_REWARDS_WAITING")
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_font_override("font", load("res://resources/fonts/actual/base/font_22.tres"))
	label.add_color_override("font_color_shadow", Color.black)
	label.add_constant_override("shadow_as_outline", 1)
	waiting_overlay.add_child(label)


func _process(delta):
	if not active():
		_release_final_pause()
		# A transport interruption must not erase unacknowledged owner records.
		# A new battle/checkpoint is reset by ensure_epoch, never by connection state.
		return
	poll += delta
	if poll < 0.2:
		return
	poll = 0.0
	var main_scene = get_tree().current_scene
	if paused_for_final and (not is_instance_valid(waiting_main) or waiting_main != main_scene):
		_release_final_pause()
		waiting_main = null
	if main_scene != null and (str(main_scene.filename) == "res://main.tscn" or sealed):
		ensure_epoch()
		for index in session()._get_slot_manager().get_local_player_indices():
			local_started[index] = true
			observe_tracking(index)
	if is_instance_valid(waiting_main):
		var ready = true
		for peer in session()._get_remote_ids_for_host_sync():
			if not finals.has(str(peer)):
				ready = false
		if ready:
			if is_instance_valid(waiting_overlay):
				waiting_overlay.queue_free()
			var main = waiting_main
			waiting_main = null
			released_scene = main.get_instance_id()
			_release_final_pause()
			main.call_deferred("_on_WaveTimer_timeout")
		else:
			_show_waiting_notice(waiting_main)
		if not ready and OS.get_ticks_msec() - last_seal_msec >= 1000:
			last_seal_msec = OS.get_ticks_msec()
			session().broadcast_message({"msg_type":"movement_rewards_seal", "epoch":epoch}, "", true)

	elif not session()._is_game_host() and epoch == current_epoch() and not totals.empty():
		if OS.get_ticks_msec() - last_report_msec >= 1000 and _has_pending_report():
			_send_local(sealed)

func capture(index: int) -> Dictionary:
	ensure_epoch()
	var effects = {}
	for key in RunData.get_player_effects(index):
		var value = RunData.get_player_effects(index)[key]
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_REAL:
			effects[str(key)] = value
	var tracked = {}
	for key in RunData.tracked_item_effects[index]:
		var value = RunData.tracked_item_effects[index][key]
		if _numeric_array(value):
			tracked[str(key)] = value.duplicate()
		elif _number(value):
			tracked[str(key)] = value
	return {"effects":effects, "tracked":tracked, "gold":RunData.get_player_gold(index)}

func empty_total() -> Dictionary:
	return {"epoch":epoch, "revision":0, "effects":{}, "tracked":{}, "gold":0}

func get_total(index: int) -> Dictionary:
	ensure_epoch()
	return totals.get(index, empty_total()).duplicate(true)

func record(index: int, before: Dictionary) -> void:
	var after = capture(index)
	var total = get_total(index)
	var changed = false
	for field in ["effects"]:
		for key in after[field]:
			var difference = after[field][key] - before[field].get(key, 0)
			if difference != 0:
				total[field][key] = total[field].get(key, 0) + difference
				changed = true
	var gold = int(after.gold) - int(before.gold)
	if gold != 0:
		total.gold += gold
		changed = true
	if not changed:
		return
	total.revision += 1
	totals[index] = total
	observe_tracking(index)

func _has_pending_report() -> bool:
	for index in session()._get_slot_manager().get_local_player_indices():
		var total = get_wire_total(index)
		var ack = acknowledged.get(index, {})
		if sealed:
			if int(total.revision) > int(ack.get("revision", -1)):
				return true
		else:
			if total.gold != ack.get("gold", 0):
				return true
			for key in total.effects:
				if total.effects[key] != ack.get("effects", {}).get(key, 0):
					return true
	return false

func get_wire_total(index: int) -> Dictionary:
	var total = get_total(index)
	if not sealed:
		total.tracked = {}
	return total

func _send_local(final: bool) -> void:
	var records = {}
	for index in session()._get_slot_manager().get_local_player_indices():
		observe_tracking(index)
		records[str(index)] = get_wire_total(index)
	last_report_msec = OS.get_ticks_msec()
	reports_sent += 1
	session().send_battle_message_to_host({"msg_type":"movement_rewards", "epoch":epoch, "records":records, "final":final}, true)

func _freeze_local() -> void:
	# An authenticated seal for this exact attempt supersedes the temporary
	# shop-to-battle guard, including a late-wave reconnect with no level-up UI.
	if not session()._is_game_host():
		session()._client_ignore_stale_menu_until_msec = 0
	var menu = get_parent().get_node_or_null("BrotatoOnlineMenuSyncManager")
	if menu != null:
		menu._end_game_start_guard("movement_rewards_wave_end")
	if not sealed:
		for index in session()._get_slot_manager().get_local_player_indices():
			var total = get_total(index)
			total.revision += 1
			totals[index] = total
	sealed = true
	var main = get_tree().current_scene
	if main != null and main.get("_players") != null:
		for player in main._players:
			if is_instance_valid(player) and owns(int(player.player_index)):
				player.set_physics_process(false)

func before_wave_end(main: Node) -> bool:
	if not active():
		return true
	ensure_epoch()
	if not session()._is_game_host():
		_freeze_local()
		_send_local(true)
		return true
	if released_scene == main.get_instance_id():
		return true
	if waiting_main == main:
		return false
	_freeze_local()
	waiting_main = main
	waiting_since_msec = OS.get_ticks_msec()
	# Native cleanup has not started yet. Freeze gameplay while networking and
	# this PROCESS-mode manager keep accepting the disconnected owner's final.
	was_paused_before_final = get_tree().paused
	paused_for_final = true
	get_tree().paused = true
	session().broadcast_message({"msg_type":"movement_rewards_seal", "epoch":epoch}, "", true)
	return false

func _release_final_pause() -> void:
	if not paused_for_final:
		return
	get_tree().paused = was_paused_before_final
	paused_for_final = false

func receive(peer: String, message: Dictionary) -> void:
	var s = session()
	if s._should_drop_p2p_message_for_session(peer, message):
		return
	ensure_epoch()
	if str(message.get("epoch", "")) != epoch:
		return
	if str(message.msg_type) == "movement_rewards_ack":
		if s._is_game_host() or peer != s._get_game_host_steam_id():
			return
		var ack_records = message.get("records", {})
		if typeof(ack_records) != TYPE_DICTIONARY:
			return
		for key in ack_records:
			if not _valid_key(str(key), false):
				continue
			var index = int(key)
			var record = ack_records[key]
			if owns(index) and _valid(record) and int(record.revision) >= int(acknowledged.get(index, {}).get("revision", -1)):
				acknowledged[index] = record.duplicate(true)
		return
	if str(message.msg_type) == "movement_rewards_seal":
		if s._is_game_host() or peer != s._get_game_host_steam_id():
			return
		_freeze_local()
		if OS.get_ticks_msec() - last_report_msec >= 1000:
			_send_local(true)
		return
	if not s._is_game_host() or s._should_drop_stale_client_battle_packet(peer, message):
		return
	var records = message.get("records", {})
	if typeof(records) != TYPE_DICTIONARY:
		return
	# Validate the entire batch before mutating any player's state.
	var slots = s._get_slot_manager()
	for key in records:
		var index = int(key)
		if str(index) != str(key) or index < 0 or index >= RunData.get_player_count() or slots.resolve_owned_player_index(peer, index) != index or not _valid(records[key]):
			return
	if bool(message.get("final", false)):
		for index in range(RunData.get_player_count()):
			if slots.resolve_owned_player_index(peer, index) == index and (not records.has(str(index)) or int(records[str(index)].revision) < int(get_total(index).revision)):
				return
	for key in records:
		apply_total(int(key), records[key], true)
	if bool(message.get("final", false)):
		for index in range(RunData.get_player_count()):
			if slots.resolve_owned_player_index(peer, index) == index and (not records.has(str(index)) or int(records[str(index)].revision) < int(get_total(index).revision)):
				return
		finals[peer] = true
	var accepted = {}
	for key in records:
		accepted[key] = get_total(int(key))
	s._send_p2p_json(peer, {"msg_type":"movement_rewards_ack", "epoch":epoch, "records":accepted}, true)

func _valid(data) -> bool:
	if typeof(data) != TYPE_DICTIONARY or str(data.get("epoch", "")) != epoch or not _number(data.get("revision")) or int(data.revision) < 0 or float(data.revision) != float(int(data.revision)):
		return false
	for field in ["effects", "tracked"]:
		if typeof(data.get(field)) != TYPE_DICTIONARY:
			return false
		for key in data[field]:
			if not (_number(data[field][key]) or (field == "tracked" and _numeric_array(data[field][key]))) or not _valid_key(str(key), false):
				return false
	return _number(data.get("gold")) and float(data.gold) == float(int(data.gold))

func apply_total(index: int, incoming: Dictionary, apply_gold: bool) -> void:
	ensure_epoch()
	if not _valid(incoming) or index < 0 or index >= RunData.get_player_count():
		return
	var old = get_total(index)
	if int(incoming.revision) < int(old.revision):
		return
	if int(incoming.revision) == int(old.revision):
		apply_tracking(index, old.tracked)
		return
	var effects = RunData.get_player_effects(index)
	for key in incoming.effects:
		var hash_key = int(key)
		if effects.has(hash_key):
			effects[hash_key] += incoming.effects[key] - old.effects.get(key, 0)
	apply_tracking(index, incoming.tracked)
	if apply_gold:
		RunData.add_gold(int(incoming.gold) - int(old.gold), index)
	totals[index] = incoming.duplicate(true)
	RunData._are_player_stats_dirty[index] = true
	Utils.reset_stat_cache(index)

func economy_gold(index: int, state: Dictionary, gold: int) -> int:
	ensure_epoch()
	var incoming = state.get("movement_rewards", {})
	if not _valid(incoming):
		return gold
	if owns(index):
		# The host's gold contains its acknowledged cumulative rewards. Keep only
		# rewards not yet included in THIS economy sample, even if a newer ACK arrived.
		return gold + int(get_total(index).gold) - int(incoming.gold)
	apply_total(index, incoming, false)
	return gold

func accept_economy(stamp: int) -> bool:
	ensure_epoch()
	if stamp <= last_economy_stamp:
		return false
	last_economy_stamp = stamp
	return true

func economy_max_hp(index: int, state: Dictionary, max_hp: int) -> int:
	# Player-state and economy packets are sampled independently. The host can
	# still hold the owner's pre-reward HP cap after acknowledging its effects.
	# Once this owner has changed attributes, use its native derived cap, including
	# local pending rewards and stat multipliers, instead of feeding that old cap
	# back into the owner and then back to the host indefinitely.
	if owns(index) and _valid(state.get("movement_rewards", {})) and not get_total(index).effects.empty():
		return RunData.get_player_max_health(index)
	return max_hp

func observe_tracking(index: int) -> bool:
	var current = capture(index).tracked
	var previous = tracking_seen.get(index, {})
	var total = get_total(index)
	var changed = current.size() != previous.size()
	for key in current:
		if not previous.has(key) or not _same_tracking_value(current[key], previous[key]):
			changed = true
	tracking_seen[index] = current
	if changed:
		# Preserve array shape and key removal, including [] and scalar/array changes.
		total.tracked = current.duplicate(true)
		total.revision += 1
		totals[index] = total
	return changed

func apply_tracking(index: int, incoming: Dictionary) -> void:
	# Empty means a gameplay-only report; a final numeric snapshot includes the
	# native initialized counters even when all their values are zero.
	if incoming.empty():
		return
	var tracked = RunData.tracked_item_effects[index]
	for key in tracked.keys():
		if (_number(tracked[key]) or _numeric_array(tracked[key])) and not incoming.has(str(key)):
			tracked.erase(key)
	for key in incoming:
		tracked[int(key)] = incoming[key].duplicate() if typeof(incoming[key]) == TYPE_ARRAY else incoming[key]

func _same_tracking_value(a, b) -> bool:
	if typeof(a) == TYPE_ARRAY or typeof(b) == TYPE_ARRAY:
		if typeof(a) != TYPE_ARRAY or typeof(b) != TYPE_ARRAY or a.size() != b.size():
			return false
		for i in range(a.size()):
			if a[i] != b[i]:
				return false
		return true
	return a == b

func _numeric_array(value) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for entry in value:
		if not _number(entry):
			return false
	return true

func preserve_local(index: int) -> bool:
	return active() and not session()._is_game_host() and owns(index) and local_started.has(index)

func accept_applied_snapshot(index: int, player_data, incoming: Dictionary) -> void:
	if not active() or session()._is_game_host() or (owns(index) and local_started.has(index)):
		return
	ensure_epoch()
	var marker = incoming.get("online_movement_rewards", {})
	if not _valid(marker):
		return
	var known = get_total(index)
	if int(marker.revision) >= int(known.revision):
		# The absolute RunData just applied already includes these cumulative gains.
		# Adopt its watermark; a later economy/report replay must not add them again.
		totals[index] = marker.duplicate(true)
	else:
		# Economy can overtake a full snapshot. Preserve only newer movement deltas
		# while accepting the snapshot's independent inventory/stat changes.
		merge_pending_effects(index, player_data, incoming)
		player_data.gold += int(known.gold) - int(marker.gold)
		apply_tracking(index, known.tracked)
	RunData._are_player_stats_dirty[index] = true
	Utils.reset_stat_cache(index)

func merge_pending_effects(index: int, player_data, incoming: Dictionary) -> void:
	var total = get_total(index)
	var applied = incoming.get("online_movement_rewards", {})
	if not applied.empty() and str(applied.get("epoch", "")) != epoch:
		return
	for key in total.effects:
		var hash_key = int(key)
		if player_data.effects.has(hash_key):
			player_data.effects[hash_key] += total.effects[key] - applied.get("effects", {}).get(key, 0)

func _number(value) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_REAL) and not is_nan(float(value)) and not is_inf(float(value))

func _valid_key(key: String, _array_key: bool) -> bool:
	return key.is_valid_integer() and str(int(key)) == key
