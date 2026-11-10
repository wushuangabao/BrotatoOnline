extends Node

# Real native weapon controls and Input events; session/roster setup is controlled.
var slots
var session
var menu
var failures = []
var checks = 0
var folder = OS.get_environment("FRIENDS_PROBE_DIR")

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	DebugService.disable_saving = true
	get_tree().create_timer(50).connect("timeout", get_tree(), "quit", [2])
	call_deferred("_run")

func _check(ok, label):
	checks += 1
	print("SELECTION_INPUT_CHECK: ", label, " ", "PASS" if ok else "FAIL")
	if not ok: failures.append(label)

func _run():
	ProgressData.apply_settings()
	ProgressData.settings.pause_on_focus_lost = false
	ProgressData.settings.on_lost_focus = 0
	slots = get_tree().root.find_node("BrotatoOnlineOnlinePlayerSlotManager", true, false)
	session = get_tree().root.find_node("BrotatoOnlineSessionManager", true, false)
	menu = get_tree().root.find_node("BrotatoOnlineMenuSyncManager", true, false)
	session.set_process(false)
	slots.set_process(false)
	session._session_active = true
	session._online_role = "host"
	get_tree().root.set_meta("brotato_online_session_active", true)
	Input.joy_connection_changed(0, true, "Pad A", "probe-a")
	Input.joy_connection_changed(1, true, "Pad B", "probe-b")
	get_tree().current_scene = null
	var ordinary = load("res://items/characters/well_rounded/well_rounded_data.tres")
	for keyboard in [false, true]:
		for alias in [false, true]:
			yield(_weapon_case(ordinary, keyboard, alias), "completed")
	var noobs_count = 0
	for character in ItemService.characters:
		if character.my_id.begins_with("character_wushuangabao_nwtl_") and not character.starting_weapons.empty():
			noobs_count += 1
			yield(_weapon_case(character, false, false), "completed")
	_check(noobs_count == 10, "all ten Noobs weapon-bearing characters loaded")
	# Offline native co-op must retain input for all local players.
	get_tree().root.set_meta("brotato_online_session_active", false)
	session._session_active = false
	for index in range(4): Utils.get_focus_emulator(index).set_process_input(true)
	yield(_weapon_case(ordinary, false, false, true), "completed")
	get_tree().root.set_meta("brotato_online_session_active", true)
	session._session_active = true
	_check_allocation()
	var result = {"checks":checks,"failures":failures}
	var f = File.new()
	f.open(folder.plus_file("single-result.json"), File.WRITE)
	f.store_string(JSON.print(result))
	f.close()
	print("SELECTION_INPUT_RESULT: single ", "PASS" if failures.empty() else "FAIL", " checks=", checks)
	get_tree().quit(0 if failures.empty() else 1)

func _weapon_case(character, keyboard, alias, offline = false):
	menu.set_process(true)
	RunData.reset()
	RunData.play_mode = RunData.PlayMode.COOP
	RunData.set_coop_run(true)
	CoopService.listening_for_inputs = false
	# Legacy device 0 is intentional: the input-entry guard must protect older
	# layouts independently of the fixed allocator and periodic owner setup.
	CoopService.connected_players = [[6,1],[7,0] if keyboard else [1,1],[2,1],[0 if alias else 3,1]]
	if alias and not keyboard:
		CoopService.connected_players[0] = [1,1]
		CoopService.connected_players[1] = [6,1]
	slots._remote_devices = [2,0 if alias else 3]
	slots._remote_steam_id_by_device = {2:"client"}
	slots._remote_steam_id_by_device[0 if alias else 3] = "client"
	slots._remote_local_slot_by_device = {2:0}
	slots._remote_local_slot_by_device[0 if alias else 3] = 1
	RunData.set_player_count(4)
	for index in range(4): RunData.add_character(character, index)
	get_tree().change_scene(MenuData.weapon_selection_scene)
	yield(get_tree().create_timer(0.3), "timeout")
	var scene = get_tree().current_scene
	var label = character.my_id + " keyboard=" + str(keyboard) + " alias=" + str(alias) + " offline=" + str(offline)
	for index in range(4):
		var fe = Utils.get_focus_emulator(index)
		_check(fe.is_processing_input() == (offline or index < 2), label + " owner " + str(index))
		var target = null
		for element in scene._get_inventories()[index].get_children():
			if element.item != null and not element.item.is_locked and not element.is_special: target = element
		_check(target != null, label + " selectable weapon " + str(index))
		if target != null: Utils.focus_player_control(target, index)
	yield(get_tree(), "idle_frame")
	# Recreate the pre-poll window: all emulators active, no manual owner helper.
	if alias:
		menu.set_process(false)
		for index in range(4): Utils.get_focus_emulator(index).set_process_input(true)
		var old_focus = []
		for index in range(4): old_focus.append(Utils.get_focus_emulator(index).focused_control)
		var navigation
		if keyboard:
			navigation = InputEventKey.new()
			navigation.scancode = KEY_LEFT
			navigation.physical_scancode = KEY_LEFT
		else:
			navigation = InputEventJoypadButton.new()
			navigation.device = 0
			navigation.button_index = JOY_DPAD_LEFT
		navigation.pressed = true
		Input.parse_input_event(navigation)
		yield(get_tree().create_timer(0.05), "timeout")
		navigation.pressed = false
		Input.parse_input_event(navigation)
		for index in range(4):
			_check((Utils.get_focus_emulator(index).focused_control != old_focus[index]) == (index == 1), label + " navigation owner " + str(index))
		Utils.focus_player_control(old_focus[1], 1)
		yield(get_tree(), "idle_frame")
	var event
	if keyboard:
		event = InputEventKey.new()
		event.scancode = KEY_ENTER
	else:
		event = InputEventJoypadButton.new()
		event.device = 0 if alias else 1
		event.button_index = JOY_XBOX_A
	event.pressed = true
	Input.parse_input_event(event)
	yield(get_tree(), "idle_frame")
	event.pressed = false
	Input.parse_input_event(event)
	_check(scene._has_player_selected == [false,true,false,false], label + " only P2 confirms")
	_check(scene._player_weapons[1].size() == 1, label + " one native weapon pick")
	# The polling path must also configure the recreated scene without a fixture call.
	menu.set_process(true)
	yield(get_tree().create_timer(0.15), "timeout")
	if not offline:
		_check(not Utils.get_focus_emulator(3).is_processing_input(), label + " remote input disabled")

func _check_allocation():
	# Reserve every physical pad id. Device 0 must never be a spare slot.
	for device in range(6): Input.joy_connection_changed(device, true, "Pad " + str(device), "probe-" + str(device))
	CoopService.connected_players = [[6,1],[7,0]]
	slots._remote_devices.clear()
	slots._remote_steam_id_by_device.clear()
	slots._remote_local_slot_by_device.clear()
	slots._device_by_remote_steam_id.clear()
	var before = CoopService.connected_players.duplicate(true)
	_check(slots._add_remote_steam_id("no-room", 0) == -1, "exhausted host allocation rejected")
	_check(CoopService.connected_players == before, "failed allocation preserves roster")
	_check(slots._remote_devices.empty(), "failed allocation preserves ownership")
	_check(slots._get_next_remote_placeholder_device_from_lists([], [], [1,2,3,4,5]) == -1, "client allocator never uses zero")
	# A client layout that runs out halfway must not compact later player indices.
	Input.joy_connection_changed(5, false, "", "")
	slots._client_entries_by_local_slot = {0:[6,1]}
	slots._local_mirrored_player_index = 0
	slots._mirrored_connected_players = before.duplicate(true)
	var players = [{"player_index":0,"steam_id":"host"},{"player_index":1,"steam_id":"other"},{"player_index":2,"steam_id":"self"}]
	get_tree().current_scene = null
	slots.apply_host_selection_layout({"players":players}, "self", "host", true)
	_check(CoopService.connected_players == before, "exhausted client layout is atomic")
	_check(slots._local_mirrored_player_index == 0, "failed layout preserves local index")
