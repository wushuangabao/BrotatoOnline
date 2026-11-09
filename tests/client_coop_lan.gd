extends Node

var role = OS.get_environment("BROTATO_TEST_ROLE")
var folder = OS.get_environment("BROTATO_TEST_DIR")
var client_count = max(2, int(OS.get_environment("BROTATO_TEST_CLIENT_PLAYERS")))
var host_count = max(1, int(OS.get_environment("BROTATO_TEST_HOST_PLAYERS")))
var session
var menu
var slots
var failures = 0

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	DebugService.disable_saving = true
	get_tree().create_timer(120).connect("timeout", self, "_timeout")
	call_deferred("_run")

func _timeout():
	printerr("CLIENT_COOP_LAN_FAIL: watchdog " + role)
	get_tree().quit(2)

func _check(ok: bool, label: String):
	print("CLIENT_COOP_LAN_", "PASS" if ok else "FAIL", ": ", role, " ", label)
	if not ok:
		failures += 1

func _write(name: String, value):
	var file = File.new()
	if file.open(folder.plus_file(name + ".tmp"), File.WRITE) == OK:
		file.store_string(JSON.print(value, "  "))
		file.close()
		Directory.new().rename(folder.plus_file(name + ".tmp"), folder.plus_file(name))

func _read(name: String):
	var file = File.new()
	if file.open(folder.plus_file(name), File.READ) != OK:
		return {}
	var result = parse_json(file.get_as_text())
	file.close()
	return result

func _exists(name: String) -> bool:
	return File.new().file_exists(folder.plus_file(name))

func _wait_file(name: String):
	yield(get_tree(), "idle_frame")
	while not _exists(name):
		yield(get_tree().create_timer(0.1), "timeout")
	return true

func _shop_matches() -> bool:
	if RunData.get_player_count() != host_count + client_count:
		return false
	for index in range(host_count, host_count + client_count):
		if RunData.get_player_gold(index) != 9920 or RunData.get_player_weapons(index).size() != 2:
			return false
	return true

func _run():
	ProgressData.apply_settings()
	ProgressData.settings.pause_on_focus_lost = false
	ProgressData.settings.keep_lock = true
	get_tree().root.set_meta("brotato_online_local_input_device_mode", "keyboard")
	session = get_tree().root.find_node("BrotatoOnlineSessionManager", true, false)
	menu = get_tree().root.find_node("BrotatoOnlineMenuSyncManager", true, false)
	slots = get_tree().root.find_node("BrotatoOnlineOnlinePlayerSlotManager", true, false)
	get_tree().current_scene = null
	get_tree().change_scene(MenuData.character_selection_scene if role == "host" else "res://ui/menus/title_screen/title_screen.tscn")
	yield(get_tree().create_timer(1), "timeout")
	if role == "host":
		session.create_session(false)
		for index in range(1, host_count):
			CoopService._add_player(7 - index, CoopService.PlayerType.GAMEPAD_XBOX)
		_write("listening.json", {"port": 27462})
	else:
		yield(_wait_file("listening.json"), "completed")
		session.join_lan("127.0.0.1", 27462)
		while slots.get_local_mirrored_player_index() < 0 or not str(get_tree().current_scene.filename).ends_with("/character_selection.tscn"):
			yield(get_tree().create_timer(0.1), "timeout")
		for seat in range(1, client_count):
			# Inject a held device accept button through vanilla's join timer.
			# No physical controller is required by this automated LAN fixture.
			var device = 6 if seat == 1 else 5
			while not CoopService.listening_for_inputs:
				yield(get_tree().create_timer(0.1), "timeout")
			var event = InputEventJoypadButton.new()
			event.device = 0 if device == CoopService.GAMEPAD_REMAPPED_DEVICE_ID else device
			event.button_index = JOY_BUTTON_0
			event.pressed = true
			Input.parse_input_event(event)
			while slots.get_local_player_indices().size() < seat + 1:
				yield(get_tree().create_timer(0.1), "timeout")
			event.pressed = false
			Input.parse_input_event(event)
		_check(slots.get_local_player_indices().size() == client_count, "one connection owns multiple local device slots")
		_write("joined.json", {"indices": slots.get_local_player_indices(), "devices": CoopService.connected_players})
		var selection = get_tree().current_scene
		for index in slots.get_local_player_indices():
			var selectable = []
			while selectable.empty():
				for element in menu._get_selectable_elements_for_player(selection, int(index), false):
					if menu._is_host_catalog_item_selectable("character_selection", int(index), menu._element_to_state(element)):
						selectable.append(element)
				if selectable.empty():
					yield(get_tree().create_timer(0.1), "timeout")
			var choice = selectable[int(index) % selectable.size()]
			FocusEmulatorSignal.set_expected_control(choice, int(index))
			menu._on_client_inventory_element_pressed(choice, selection, "character_selection", int(index))
		yield(get_tree().create_timer(1), "timeout")
		for index in slots.get_local_player_indices():
			_check(bool(selection._has_player_selected[index]), "independent character confirmation for slot " + str(index))
		_write("selected.json", {})
	if role == "host":
		yield(_wait_file("joined.json"), "completed")
		yield(_wait_file("selected.json"), "completed")
		var peer = str(session._get_remote_ids_for_host_sync()[0])
		_check(slots.get_player_indices_for_steam_id(peer).size() == client_count, "host allocates all client seats")
		_check(session.get_session_member_count() == host_count + client_count, "capacity counts players instead of connections")
		_check(slots.resolve_owned_player_index(peer, 0) == -1, "client cannot address host slot")
		var owners = session._get_identity_manager()._capture_current_owners()
		_check(int(owners[host_count + 1].local_slot) == 1 and owners[host_count].owner_id == owners[host_count + 1].owner_id, "save identities distinguish seats of one peer")
		for index in slots.get_player_indices_for_steam_id(peer):
			_check(bool(get_tree().current_scene._has_player_selected[index]), "host receives character selection for slot " + str(index))
		var before_count = CoopService.connected_players.size()
		session._handle_client_local_join(peer, {"local_slot": 1})
		_check(CoopService.connected_players.size() == before_count, "duplicate join does not allocate another character")
		if before_count == 4:
			session._handle_client_local_join(peer, {"local_slot": client_count})
			_check(CoopService.connected_players.size() == 4, "full room rejects a fifth player")
		var saved_layout = []
		for index in range(before_count):
			saved_layout.append({"peer_key": slots.get_remote_steam_id(index), "local_slot": slots.get_peer_local_slot(index)})
		_check(slots.apply_resume_identity_layout(saved_layout) and slots.get_player_indices_for_steam_id(peer).size() == client_count, "saved layout restores multiple seats for one peer")
		var layout = CoopService.connected_players.duplicate(true)
		RunData.reset()
		RunData.set_player_count(host_count + client_count, true)
		RunData.set_coop_run(true)
		CoopService.connected_players = layout
		for index in range(host_count + client_count):
			RunData.add_character(load("res://items/characters/well_rounded/well_rounded_data.tres"), index)
			RunData.add_weapon(load("res://weapons/ranged/pistol/1/pistol_data.tres"), index, true)
			RunData.players_data[index].gold = 10000
			if index >= host_count:
				RunData.locked_shop_items[index] = [[load("res://weapons/ranged/smg/1/smg_data.tres"), 20]]
		RunData.current_wave = 21
		RunData.is_endless_run = true
		ZoneService.set_current_zone(ZoneService.get_zone_data(RunData.current_zone).duplicate())
		ItemService.init_unlocked_pool()
		get_tree().change_scene("res://ui/menus/shop/coop_shop.tscn")
		yield(_wait_file("bought.json"), "completed")
		_check(_shop_matches(), "host preserves each client purchase and currency separately")
		_write("start.json", {})
		session.request_synced_shop_game_start(get_tree().current_scene, 0)
	else:
		while get_tree().current_scene == null or not get_tree().current_scene.has_method("_get_shop_items_container") or menu._client_shop_intercept_keys.size() < client_count:
			yield(get_tree().create_timer(0.1), "timeout")
		for index in slots.get_local_player_indices():
			var card = get_tree().current_scene._get_shop_items_container(index)._shop_items[0]
			while card.item_data == null or card.item_data.my_id != "weapon_smg_1" or not card.locked:
				yield(get_tree().create_timer(0.1), "timeout")
			menu._on_client_shop_item_bought(card, int(index))
		yield(get_tree().create_timer(2), "timeout")
		while not _shop_matches():
			yield(get_tree().create_timer(0.1), "timeout")
		_check(_shop_matches(), "each local player buys their own locked offer")
		_write("bought.json", {})
	while get_tree().current_scene == null or str(get_tree().current_scene.filename) != "res://main.tscn":
		yield(get_tree().create_timer(0.1), "timeout")
	yield(get_tree().create_timer(1), "timeout")
	var main = get_tree().current_scene
	_check(main._players.size() == host_count + client_count, "all players enter battle after host starts")
	if role == "client":
		yield(_wait_file("host-battle-ready.json"), "completed")
		var before = []
		for index in slots.get_local_player_indices():
			var player = main._players[index]
			player.max_stats.health = 1000
			player.current_stats.health = 1000
			before.append(player.global_position)
			var device = CoopService.get_remapped_player_device(index)
			Input.action_press("button_move_" + ("left_" if index == host_count else "right_") + str(device))
		yield(get_tree().create_timer(0.6), "timeout")
		var offset = 0
		for index in slots.get_local_player_indices():
			var device = CoopService.get_remapped_player_device(index)
			Input.action_release("button_move_left_" + str(device))
			Input.action_release("button_move_right_" + str(device))
			var player = main._players[index]
			_check(player.global_position.distance_to(before[offset]) > 5, "independent movement for slot " + str(index))
			offset += 1
			var args = TakeDamageArgs.new(-1)
			args.dodgeable = false
			args.armor_applied = false
			args.bypass_invincibility = true
			var hp = player.current_stats.health
			player.take_damage(7 + index, args)
			_check(player.current_stats.health < hp, "local damage applies to slot " + str(index))
			if index == host_count + 1:
				player.take_damage(999999, args)
		yield(get_tree().create_timer(1), "timeout")
		_check(not main._players[host_count].dead and main._players[host_count + 1].dead, "one local death does not kill the other local player")
		_write("battle.json", {"dead_index": host_count + 1})
		yield(_wait_file("host-battle.json"), "completed")
		# Exercise ENet reconnection without replacing the slot manager or bypassing
		# the production identity handshake. Device/character ownership must persist.
		session._lan_transport._begin_client_reconnect("controlled_test_disconnect")
		yield(get_tree().create_timer(0.2), "timeout")
		while session._lan_transport._reconnect_active:
			yield(get_tree().create_timer(0.1), "timeout")
		yield(get_tree().create_timer(2), "timeout")
		_check(slots.get_local_player_indices().size() == client_count and session.is_online_session_active(), "reconnect retains every local player")
		_write("reconnected.json", {})
		yield(_wait_file("host-reconnected.json"), "completed")
	else:
		var peer = str(session._get_remote_ids_for_host_sync()[0])
		var host_hp = main._players[0].current_stats.health
		session._get_state_snapshot_manager().apply_player_state(peer, {"player_index": 0, "hp": 0, "dead": true, "terminal": true})
		_check(main._players[0].current_stats.health == host_hp and not main._players[0].dead, "forged client death packet cannot kill host")
		_check(session._get_online_input_manager().receive_battle_input(peer, {"player_index": 0, "move": {"x": 1, "y": 0}}).empty(), "client input cannot control host slot")
		session._handle_client_local_join(peer, {"local_slot": 1})
		session._handle_client_local_join(peer, {"local_slot": client_count})
		_check(CoopService.connected_players.size() == host_count + client_count, "battle keeps roster fixed after duplicate or new join requests")
		var pickup_kind = "mutation_consumable_fruit"
		main._bo_known["test-secondary-pickup"] = main.BO_SPECIALS[pickup_kind]
		main._bo_known["test-forged-pickup"] = main.BO_SPECIALS[pickup_kind]
		main.bo_receive_pickups({"action": "items", "items": [["test-secondary-pickup", pickup_kind, host_count + 1, false, false], ["test-forged-pickup", pickup_kind, 0, false, false]]}, host_count, peer)
		_check(main._bo_received.has(str(host_count + 1) + ":test-secondary-pickup") and not main._bo_received.has("0:test-forged-pickup"), "DLC pickup batch accepts secondary seat and rejects host spoof")
		_write("host-battle-ready.json", {})
		yield(_wait_file("battle.json"), "completed")
		_check(not main._players[host_count].dead and main._players[host_count + 1].dead, "host receives death for the correct secondary client player")
		_check(main._players[host_count].current_stats.health > 0, "primary client health remains alive on host")
		_write("host-battle.json", {})
		yield(_wait_file("reconnected.json"), "completed")
		peer = str(session._get_remote_ids_for_host_sync()[0])
		_check(slots.get_player_indices_for_steam_id(peer).size() == client_count and session._connection_by_peer_key.has(peer), "host rebinds one connection to all saved client seats")
		_write("host-reconnected.json", {})
	_write(role + "-result.json", {"failures": failures, "players": CoopService.connected_players, "local_indices": slots.get_local_player_indices()})
	yield(get_tree(), "idle_frame")
	var frame = get_viewport().get_texture().get_data()
	frame.flip_y()
	frame.save_png(folder.plus_file(role + ".png"))
	print("CLIENT_COOP_LAN_RESULT: ", role, " ", "PASS" if failures == 0 else "FAIL")
	if role == "host":
		yield(get_tree().create_timer(0.5), "timeout")
	get_tree().quit(0 if failures == 0 else 1)
