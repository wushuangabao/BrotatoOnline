extends Node

var role = OS.get_environment("FRIENDS_PROBE_ROLE")
var probe_case = OS.get_environment("FRIENDS_PROBE_CASE")
var folder = OS.get_environment("FRIENDS_PROBE_DIR")
var session
var slots
var menu
var failures = []
var checks = 0

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	DebugService.disable_saving = true
	get_tree().create_timer(55).connect("timeout", self, "_timeout")
	call_deferred("_run")

func _timeout():
	_dump("timeout")
	get_tree().quit(2)

func _write(name, data):
	var f = File.new()
	f.open(folder.plus_file(name + ".json"), File.WRITE)
	f.store_string(JSON.print(data))
	f.close()

func _wait_file(name):
	yield(get_tree(), "idle_frame")
	while not File.new().file_exists(folder.plus_file(name + ".json")):
		yield(get_tree().create_timer(0.1), "timeout")

func _dump(label):
	var scene = get_tree().current_scene
	var state = {"role": role, "label": label, "players": CoopService.connected_players.duplicate(true), "count": RunData.get_player_count(), "locals": slots.get_local_player_indices(), "screen": str(scene.filename) if scene else "", "focus": [], "visible_panels": [], "inventories": []}
	if scene != null:
		if scene.get("_has_player_selected") != null:
			state["selected"] = scene._has_player_selected.duplicate()
		for i in range(4):
			var fe = Utils.get_focus_emulator(i)
			if fe != null:
				state.focus.append({"index": i, "device": fe._device, "processing": fe.is_processing_input(), "control": str(fe.focused_control.get_path()) if is_instance_valid(fe.focused_control) else "null"})
		if scene.has_method("_get_panels"):
			for panel in scene._get_panels():
				if panel.is_visible_in_tree(): state.visible_panels.append(str(panel.name))
		if scene.has_method("_get_coop_join_panels"):
			for panel in scene._get_coop_join_panels():
				if panel.is_visible_in_tree(): state.visible_panels.append(str(panel.name))
		if scene.has_method("_get_inventories"):
			for inventory in scene._get_inventories():
				state.inventories.append({"visible": inventory.is_visible_in_tree(), "children": inventory.get_child_count()})
	print("LAN_INPUT_PROBE ", JSON.print(state))
	_write(role + "-" + label, state)
	if label in ["joined", "four-characters", "focused-characters", "battle"]:
		var picture = get_viewport().get_texture().get_data()
		picture.flip_y()
		picture.save_png(folder.plus_file(role + "-" + label + ".png"))

func _button(device, held = 0.08):
	var e
	if device == 7:
		e = InputEventKey.new()
		e.scancode = KEY_ENTER
	else:
		e = InputEventJoypadButton.new()
		e.device = 0 if device == 6 else device
		e.button_index = JOY_XBOX_A
	e.pressed = true
	Input.parse_input_event(e)
	yield(get_tree().create_timer(held), "timeout")
	e.pressed = false
	Input.parse_input_event(e)
	yield(get_tree().create_timer(0.1), "timeout")

func _run():
	ProgressData.apply_settings()
	ProgressData.settings.pause_on_focus_lost = false
	ProgressData.settings.on_lost_focus = 0
	session = get_tree().root.find_node("BrotatoOnlineSessionManager", true, false)
	slots = get_tree().root.find_node("BrotatoOnlineOnlinePlayerSlotManager", true, false)
	# Engine-level virtual attachments exercise the production enumeration/remap.
	Input.joy_connection_changed(0, true, "ProbePad A", "030000005e0400008e02000014010000")
	if role != "host" or not ["keyboard", "late_keyboard"].has(probe_case):
		Input.joy_connection_changed(1, true, "ProbePad B", "030000005e0400008e02000014010000")
	menu = get_tree().root.find_node("BrotatoOnlineMenuSyncManager", true, false)
	var settings = get_tree().root.find_node("BrotatoOnlineModSettingsManager", true, false)
	settings.set_lan_host_port(59128)
	get_tree().current_scene = null
	get_tree().change_scene(MenuData.character_selection_scene if role == "host" else MenuData.title_screen_scene)
	yield(get_tree().create_timer(0.8), "timeout")
	if role == "host":
		get_tree().current_scene._play_mode_init(RunData.PlayMode.COOP, false)
		yield(_button(6, 0.85), "completed")
		if probe_case != "late_keyboard":
			yield(_button(7 if probe_case == "keyboard" else 1, 0.85), "completed")
		_dump("before-session")
		session.create_session(false)
		_write("listening", {})
		if probe_case == "late_keyboard":
			yield(_wait_file("client-extra"), "completed")
			yield(_button(7, 0.85), "completed")
	else:
		yield(_wait_file("listening" if role == "client1" else "client1-joined"), "completed")
		session.join_lan("127.0.0.1", 59128)
		while slots.get_local_mirrored_player_index() < 0 or get_tree().current_scene == null or not str(get_tree().current_scene.filename).ends_with("/character_selection.tscn"):
			yield(get_tree().create_timer(0.1), "timeout")
		yield(get_tree().create_timer(0.8), "timeout")
		_check_character_ui("joined")
		_dump("joined")
		if probe_case != "three":
			yield(_button(1, 0.85), "completed")
			if probe_case == "late_keyboard":
				while RunData.get_player_count() != 3:
					yield(get_tree(), "idle_frame")
				_write("client-extra", {})
	while RunData.get_player_count() != 4:
		yield(get_tree().create_timer(0.1), "timeout")
	yield(get_tree().create_timer(1), "timeout")
	_check_character_ui("four-characters")
	_dump("four-characters")
	var peers = ["host", "client1", "client2"] if probe_case == "three" else ["host", "client1"]
	var expected = [0,1] if role == "host" else [2,3]
	if probe_case == "late_keyboard":
		expected = [0,3] if role == "host" else [1,2]
	elif probe_case == "three" and role != "host":
		expected = [2] if role == "client1" else [3]
	_check(slots.get_local_player_indices() == expected, "joining order preserves local seats")
	for index in slots.get_local_player_indices():
		var element = menu._find_element_by_item_id(get_tree().current_scene, index, "character_wushuangabao_nwtl_xia_xia_mi", true)
		Utils.focus_player_control(element, index)
	_write(role + "-character-focused", {})
	for peer in peers:
		yield(_wait_file(peer + "-character-focused"), "completed")
	yield(get_tree().create_timer(0.4), "timeout")
	var visible = 0
	for panel in get_tree().current_scene._get_panels():
		if panel.is_visible_in_tree(): visible += 1
	_check(visible == 4, "four occupied character panels after focus synchronization")
	_dump("focused-characters")
	for index in slots.get_local_player_indices():
		yield(_button(CoopService.get_remapped_player_device(index)), "completed")
		_dump("character-accept-" + str(index))
	while not str(get_tree().current_scene.filename).ends_with("/weapon_selection.tscn"):
		yield(get_tree().create_timer(0.1), "timeout")
	yield(get_tree().create_timer(0.8), "timeout")
	_dump("weapon-ready")
	for index in slots.get_local_player_indices():
		var target = null
		for element in get_tree().current_scene._get_inventories()[index].get_children():
			if element.item != null and not element.item.is_locked and not element.is_special: target = element
		_check(target != null, "Noobs selectable weapon " + str(index))
		if target != null: Utils.focus_player_control(target, index)
	_write(role + "-weapon-focused", {})
	for peer in peers:
		yield(_wait_file(peer + "-weapon-focused"), "completed")
	yield(get_tree().create_timer(0.4), "timeout")
	for index in slots.get_local_player_indices():
		yield(_button(CoopService.get_remapped_player_device(index)), "completed")
		_dump("weapon-accept-" + str(index))
	_write(role + "-weapons-sent", {})
	for peer in peers:
		yield(_wait_file(peer + "-weapons-sent"), "completed")
	# Scene commits/ACKs are asynchronous. Wait for the actual transition instead
	# of treating a fixed two-second delay as a network-completion guarantee.
	while get_tree().current_scene == null or not str(get_tree().current_scene.filename).ends_with("/difficulty_selection.tscn"):
		yield(get_tree(), "idle_frame")
	_dump("end")
	_check(str(get_tree().current_scene.filename).ends_with("/difficulty_selection.tscn"), "four weapon confirmations reached difficulty")
	if not str(get_tree().current_scene.filename).ends_with("/difficulty_selection.tscn"):
		_finish()
		return
	var final_roster = CoopService.connected_players.duplicate(true)
	_write(role + "-difficulty-ready", {})
	for peer in peers:
		yield(_wait_file(peer + "-difficulty-ready"), "completed")
	if role == "host":
		var difficulty = get_tree().current_scene._get_inventories()[0].get_child(0)
		Utils.focus_player_control(difficulty, 0)
		yield(get_tree(), "idle_frame")
		yield(_button(6), "completed")
	while get_tree().current_scene == null or str(get_tree().current_scene.filename) != "res://main.tscn":
		yield(get_tree(), "idle_frame")
	yield(get_tree().create_timer(0.5), "timeout")
	_check(get_tree().current_scene._players.size() == 4, "four actual player nodes entered battle")
	_check(CoopService.connected_players == final_roster, "battle preserves device roster")
	_check(slots.get_local_player_indices() == expected, "battle preserves local seats")
	_dump("battle")
	for peer in peers:
		yield(_wait_file(peer + "-battle"), "completed")
	_finish()

func _check(ok, label):
	checks += 1
	if not ok:
		failures.append(label)
		printerr("SELECTION_INPUT_FAIL: " + role + " " + label)

func _check_character_ui(label):
	var scene = get_tree().current_scene
	var count = RunData.get_player_count()
	_check(scene._get_inventories()[0].is_visible_in_tree(), label + " character grid visible")
	var joined = 0
	for panel in scene._get_coop_join_panels():
		if panel.is_visible_in_tree(): joined += 1
	_check(joined == 4-count, label + " no ghost join panels")
	_check(CoopService.connected_players.size() == count, label + " roster count")
	for index in range(count):
		var fe = Utils.get_focus_emulator(index)
		_check(fe._device == CoopService.get_remapped_player_device(index), label + " focus binding " + str(index))
		_check(fe.is_processing_input() == slots.get_local_player_indices().has(index), label + " input owner " + str(index))
	for index in slots.get_local_player_indices():
		_check(is_instance_valid(Utils.get_focus_emulator(index).focused_control), label + " local focus " + str(index))

func _finish():
	_write(role + "-result", {"checks":checks,"failures":failures})
	print("SELECTION_INPUT_RESULT: " + role + (" PASS" if failures.empty() else " FAIL") + " checks=" + str(checks))
	get_tree().quit(0 if failures.empty() else 1)
