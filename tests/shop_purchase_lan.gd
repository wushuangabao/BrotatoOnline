extends Node

var role = OS.get_environment("BROTATO_TEST_ROLE")
var folder = OS.get_environment("BROTATO_TEST_DIR")
var session
var manager

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	DebugService.disable_saving = true
	get_tree().create_timer(45).connect("timeout", self, "_timeout")
	call_deferred("_run")

func _timeout():
	printerr("SHOP_PURCHASE_LAN_FAIL: watchdog " + role)
	get_tree().quit(2)

func _write(name: String, value):
	var file = File.new()
	if file.open(folder.plus_file(name + ".tmp"), File.WRITE) == OK:
		file.store_string(JSON.print(value, "  "))
		file.close()
		Directory.new().rename(folder.plus_file(name + ".tmp"), folder.plus_file(name))

func _exists(name: String) -> bool:
	return File.new().file_exists(folder.plus_file(name))

func _snapshot() -> Dictionary:
	var weapons = []
	for weapon in RunData.get_player_weapons(1):
		weapons.append(weapon.my_id)
	return {"weapons": weapons, "gold": RunData.get_player_gold(1)}

func _matches_purchase() -> bool:
	var snapshot = _snapshot()
	return snapshot.weapons == ["weapon_pistol_2", "weapon_smg_1"] and snapshot.gold == 9920

func _run():
	ProgressData.apply_settings()
	ProgressData.settings.pause_on_focus_lost = false
	ProgressData.settings.keep_lock = true
	session = get_tree().root.find_node("BrotatoOnlineSessionManager", true, false)
	manager = get_tree().root.find_node("BrotatoOnlineMenuSyncManager", true, false)
	get_tree().current_scene = null
	get_tree().change_scene(MenuData.character_selection_scene if role == "host" else "res://ui/menus/title_screen/title_screen.tscn")
	yield(get_tree().create_timer(1), "timeout")
	if role == "host":
		session.create_session(false)
		_write("listening.json", {"port": 27462})
	else:
		while not _exists("listening.json"):
			yield(get_tree().create_timer(0.1), "timeout")
		session.join_lan("127.0.0.1", 27462)
	while session.get_session_member_count() < 2:
		yield(get_tree().create_timer(0.1), "timeout")
	if role == "host":
		yield(get_tree().create_timer(1), "timeout")
		var connected = CoopService.connected_players.duplicate(true)
		RunData.reset()
		RunData.set_player_count(2, true)
		RunData.set_coop_run(true)
		CoopService.connected_players = connected
		for i in 2:
			RunData.add_character(load("res://items/characters/well_rounded/well_rounded_data.tres"), i)
			RunData.add_weapon(load("res://weapons/ranged/pistol/1/pistol_data.tres"), i, true)
			RunData.players_data[i].gold = 10000
		RunData.add_weapon(load("res://weapons/ranged/pistol/1/pistol_data.tres"), 1, true)
		RunData.current_wave = 21
		RunData.is_endless_run = true
		RunData.locked_shop_items[1] = [[load("res://weapons/ranged/smg/1/smg_data.tres"), 20]]
		ZoneService.set_current_zone(ZoneService.get_zone_data(RunData.current_zone).duplicate())
		ItemService.init_unlocked_pool()
		get_tree().change_scene("res://ui/menus/shop/coop_shop.tscn")
		while not _exists("client-result.json"):
			yield(get_tree().create_timer(0.1), "timeout")
	else:
		while true:
			var scene = get_tree().current_scene
			if scene != null and scene.has_method("_get_shop_items_container") and manager._client_shop_intercept_key != "" and RunData.get_player_count() == 2 and RunData.get_player_weapons(1).size() == 2 and RunData.get_player_gold(1) == 10000:
				var card = scene._get_shop_items_container(1)._shop_items[0]
				if card.item_data != null and card.item_data.my_id == "weapon_smg_1" and card.locked:
					break
			yield(get_tree().create_timer(0.1), "timeout")
		var shop = get_tree().current_scene
		# Invoke the production UI callbacks in one turn: both optimistic actions are
		# queued before the first host reply. All delivery/ACK/repair uses real LAN.
		manager._on_client_shop_combine_weapon_pressed(RunData.get_player_weapons(1)[0], 1)
		manager._on_client_shop_item_bought(shop._get_shop_items_container(1)._shop_items[0], 1)
		_write("client-prediction.json", _snapshot())
		# Let the complete response chain settle, including chunked corrections.
		yield(get_tree().create_timer(3), "timeout")
		var deadline = OS.get_ticks_msec() + 5000
		while not _matches_purchase() and OS.get_ticks_msec() < deadline:
			yield(get_tree().create_timer(0.1), "timeout")
		_write("client-result.json", _snapshot())
	var result = _snapshot()
	_write(role + "-result.json", result)
	var ok = _matches_purchase()
	print("SHOP_PURCHASE_LAN_RESULT: ", role, " ", "PASS" if ok else "FAIL", " ", JSON.print(result))
	yield(get_tree(), "idle_frame")
	var frame = get_viewport().get_texture().get_data()
	frame.flip_y()
	frame.save_png(folder.plus_file(role + ".png"))
	# Keep the host alive until the client has finished recording its result.
	if role == "host":
		yield(get_tree().create_timer(0.5), "timeout")
	get_tree().quit(0 if ok else 1)
