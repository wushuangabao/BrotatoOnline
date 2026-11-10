extends Node

var role = OS.get_environment("FRIENDS_PROBE_ROLE")
var input_config = OS.get_environment("SAVE_TEST_HOST_INPUT" if role == "host" else "SAVE_TEST_CLIENT_INPUT")
var folder = OS.get_environment("FRIENDS_PROBE_DIR")
var session
var slots
var menu
var failures = []
var checks = 0
var phase = OS.get_environment("SAVE_TEST_PHASE")
var root_folder = OS.get_environment("SAVE_TEST_ROOT")
var identity

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	DebugService.disable_saving = false
	get_tree().create_timer(110).connect("timeout", self, "_timeout")
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

func _check(ok, label):
	checks += 1
	print("SAVE_COMPAT_CHECK: ", role, " ", label, " ", ok)
	if not ok: failures.append(label)

func _read(path):
	var f = File.new()
	if f.open(path, File.READ) != OK: return {}
	var data = parse_json(f.get_as_text())
	f.close()
	return data

func _equal(a,b):
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _equal(a[key],b[key]): return false
		return true
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not _equal(a[i],b[i]): return false
		return true
	return a == b

func _snapshot():
	var players = []
	for i in range(RunData.get_player_count()):
		var p = RunData.players_data[i]
		var weapons = []
		for weapon in p.weapons: weapons.append(weapon.my_id)
		var items = []
		for item in p.items: items.append(item.my_id)
		players.append({"character":p.current_character.my_id,"weapons":weapons,"items":items,"gold":p.gold,"level":p.current_level,"xp":p.current_xp})
	return {"input_config":input_config,"players":players,"wave":RunData.current_wave,"difficulty":RunData.current_difficulty,"zone":RunData.current_zone,"locals":slots.get_local_player_indices(),"devices":CoopService.connected_players.duplicate(true),"identity":identity.registry.metadata()}

func _run():
	_check(OS.get_user_data_dir().replace("\\", "/").begins_with(root_folder.replace("\\", "/")), "save directory isolated")
	if not failures.empty():
		get_tree().quit(1)
		return
	ProgressData.apply_settings()
	ProgressData.settings.pause_on_focus_lost = false
	ProgressData.settings.on_lost_focus = 0
	session = get_tree().root.find_node("BrotatoOnlineSessionManager", true, false)
	slots = get_tree().root.find_node("BrotatoOnlineOnlinePlayerSlotManager", true, false)
	menu = get_tree().root.find_node("BrotatoOnlineMenuSyncManager", true, false)
	identity = session._get_identity_manager()
	Input.joy_connection_changed(0, true, "SavePad A", "save-a")
	if input_config == "pads":
		Input.joy_connection_changed(1, true, "SavePad B", "save-b")
	get_tree().root.find_node("BrotatoOnlineModSettingsManager", true, false).set_lan_host_port(59128)
	get_tree().current_scene = null
	get_tree().change_scene(MenuData.character_selection_scene if phase == "create" and role == "host" else MenuData.title_screen_scene)
	yield(get_tree().create_timer(0.6), "timeout")
	if phase == "create":
		if role == "host":
			get_tree().current_scene._play_mode_init(RunData.PlayMode.COOP, false)
			yield(_button(6,0.85), "completed")
			yield(_button(7 if input_config == "mixed" else 1,0.85), "completed")
			session.create_session(false)
			_write("listening", {})
		else:
			yield(_wait_file("listening"), "completed")
			session.join_lan("127.0.0.1",59128)
			while slots.get_local_mirrored_player_index() < 0:
				yield(get_tree(), "idle_frame")
			yield(get_tree().create_timer(0.5), "timeout")
			yield(_button(7 if input_config == "mixed" else 1,0.85), "completed")
		while CoopService.connected_players.size() != 4:
			yield(get_tree(), "idle_frame")
		if role == "host":
			var layout = CoopService.connected_players.duplicate(true)
			RunData.reset()
			RunData.play_mode = RunData.PlayMode.COOP
			RunData.set_coop_run(true)
			RunData.set_player_count(4,true)
			CoopService.connected_players = layout
			var ids = ["xia_xia_mi","fan_jue_yun","mu_rong_xue","di_qing_lian"]
			for i in range(4):
				for character in ItemService.characters:
					if character.my_id == "character_wushuangabao_nwtl_" + ids[i]:
						RunData.add_character(character,i)
						RunData.add_weapon(character.starting_weapons[0],i,true)
				RunData.add_weapon(load("res://weapons/ranged/pistol/"+str(i+1)+"/"+("pistol_data.tres" if i == 0 else "pistol_"+str(i+1)+"_data.tres")),i,true)
				for n in range(i+1): RunData.add_item(load("res://items/all/00_base_game/lens/lens_data.tres"),i)
				RunData.players_data[i].gold = 1200 + i*111
				RunData.players_data[i].current_level = 3+i
				RunData.players_data[i].current_xp = 1+i
			RunData.current_wave = 7
			RunData.current_difficulty = 1
			ZoneService.set_current_zone(ZoneService.get_zone_data(RunData.current_zone).duplicate())
			ItemService.init_unlocked_pool()
			get_tree().change_scene("res://ui/menus/shop/coop_shop.tscn")
	else:
		if role == "host":
			_check(bool(ProgressData.saved_run_state.get("has_run_state",false)), "disk save loaded at fresh startup")
			var button = get_tree().current_scene._main_menu.continue_button
			_check(button.is_visible_in_tree(), "native Continue button available")
			button.emit_signal("pressed")
			while not session.is_online_session_active():
				yield(get_tree(), "idle_frame")
			_write("listening", {})
			yield(_button(7 if input_config == "mixed" else 1,0.85), "completed")
		else:
			yield(_wait_file("listening"), "completed")
			session.join_lan("127.0.0.1",59128)
	while get_tree().current_scene == null or not get_tree().current_scene.has_method("_get_shop_items_container") or RunData.get_player_count() != 4:
		yield(get_tree(), "idle_frame")
	yield(get_tree().create_timer(1), "timeout")
	var snapshot = _snapshot()
	_write(role + "-shop",snapshot)
	if phase == "create":
		if role == "host":
			_check(bool(ProgressData.saved_run_state.has_run_state), "native shop checkpoint exists")
			_check(identity.load_saved_identity().get("slots",[]).size() == 4, "four identities persisted against saved bytes")
			snapshot["run_file"] = ProjectSettings.globalize_path(str(ProgressData.SAVE_PATH).replace("save_v3_","run_v3_"))
			_write("checkpoint", snapshot)
		for peer in ["host","client1"]:
			yield(_wait_file(peer+"-shop"),"completed")
	else:
		var expected = _read(root_folder.plus_file("create/checkpoint.json"))
		for key in ["players","wave","difficulty","zone"]:
			_check(_equal(snapshot[key],expected[key]), "restored " + key)
		_check(snapshot.locals == ([0,1] if role == "host" else [2,3]), "restored local seats")
		var expected_devices = [6, 7 if input_config == "mixed" else 1]
		for rank in range(snapshot.locals.size()):
			var i = snapshot.locals[rank]
			_check(int(snapshot.devices[i][0]) == expected_devices[rank], "current session device assigned to P"+str(i+1))
		if role == "host":
			_check(_equal(snapshot.identity,expected.identity), "stable run id, slot ids and owner identities")
			_check(not identity._legacy_save and not identity._manual, "automatic saved-owner restoration without reassignment")
		for peer in ["host","client1"]:
			yield(_wait_file(peer+"-shop"),"completed")
		if role == "host": session.request_synced_shop_game_start(get_tree().current_scene,0)
		while str(get_tree().current_scene.filename) != "res://main.tscn":
			yield(get_tree(),"idle_frame")
		var main = get_tree().current_scene
		if main._wave_manager.is_connected("group_spawn_timing_reached",main._entity_spawner,"on_group_spawn_timing_reached"):
			main._wave_manager.disconnect("group_spawn_timing_reached",main._entity_spawner,"on_group_spawn_timing_reached")
		main._wave_manager.set_process(false)
		main._entity_spawner.set_process(false)
		yield(get_tree().create_timer(3),"timeout")
		_check(main._players.size() == 4,"four saved players entered next wave")
		_check(RunData.current_wave == int(expected.wave)+1,"continued to next saved wave")
		_check(slots.get_local_player_indices() == ([0,1] if role == "host" else [2,3]),"battle control ownership preserved")
		for i in range(4):
			var before = []
			for player in main._players: before.append(player.global_position)
			_write(role+"-move-ready-"+str(i),{})
			for peer in ["host","client1"]:
				yield(_wait_file(peer+"-move-ready-"+str(i)),"completed")
			if slots.get_local_player_indices().has(i):
				var expected_device = expected_devices[snapshot.locals.find(i)]
				var event
				if expected_device == 7:
					event = InputEventKey.new()
					event.scancode = KEY_D
					event.physical_scancode = KEY_D
					event.pressed = true
				else:
					event = InputEventJoypadMotion.new()
					event.device = 0 if expected_device == 6 else expected_device
					event.axis = JOY_AXIS_0
					event.axis_value = 1.0
				Input.parse_input_event(event)
				yield(get_tree().create_timer(0.6),"timeout")
				_write(role+"-input-"+str(i),{"expected_device":expected_device,"current_device":CoopService.get_remapped_player_device(i),"dead":main._players[i].dead,"move":str(session._get_online_input_manager()._read_move_vector_for_device(CoopService.get_remapped_player_device(i)))})
				if expected_device == 7: event.pressed = false
				else: event.axis_value = 0.0
				Input.parse_input_event(event)
				_write("move-done-"+str(i),{})
			yield(_wait_file("move-done-"+str(i)),"completed")
			yield(get_tree().create_timer(0.35),"timeout")
			var distances = []
			for j in range(4):
				var distance = main._players[j].global_position.distance_to(before[j])
				distances.append(distance)
				_check(distance>5 if i==j else distance<3,"input P"+str(i+1)+" moves only its player, observed P"+str(j+1))
			_write(role+"-movement-"+str(i),distances)
			for peer in ["host","client1"]:
				yield(_wait_file(peer+"-movement-"+str(i)),"completed")
		_dump("battle")
	_write(role+"-result",{"checks":checks,"failures":failures})
	for peer in ["host","client1"]:
		yield(_wait_file(peer+"-result"),"completed")
	print("SAVE_COMPAT_RESULT: ",role," ","PASS" if failures.empty() else "FAIL")
	get_tree().quit(0 if failures.empty() else 1)
