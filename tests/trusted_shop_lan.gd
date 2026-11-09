extends "res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/tests/meca_upgrade_lan.gd"

func _check(ok: bool, label: String):
	print("TRUSTED_SHOP_LAN_", "PASS" if ok else "FAIL", ": ", role, " ", label)
	if not ok:
		failures += 1

func _read(name: String):
	var file = File.new()
	file.open(folder.plus_file(name), File.READ)
	var result = JSON.parse(file.get_as_text()).result
	file.close()
	return result

func _snapshot() -> Dictionary:
	var weapons = []
	for weapon in RunData.get_player_weapons(1):
		weapons.append(menu._build_shop_item_stable_identity(weapon))
	var player = RunData.players_data[1]
	return {"weapons": weapons, "gold": RunData.get_player_gold(1), "items": RunData.get_player_items(1).size(), "level": player.current_level, "xp": player.current_xp, "parts": player.meca_parts, "armor": RunData.get_player_effect(Keys.stat_armor_hash, 1)}

func _run():
	ProgressData.apply_settings()
	ProgressData.settings.pause_on_focus_lost = false
	ProgressData.settings.keep_lock = true
	session = get_tree().root.find_node("BrotatoOnlineSessionManager", true, false)
	menu = get_tree().root.find_node("BrotatoOnlineMenuSyncManager", true, false)
	get_tree().current_scene = null
	get_tree().change_scene(MenuData.character_selection_scene if role == "host" else "res://ui/menus/title_screen/title_screen.tscn")
	yield(get_tree().create_timer(1), "timeout")
	if role == "host":
		session.create_session(false)
		_write("listening.json", {})
	else:
		yield(_wait_file("listening.json"), "completed")
		session.join_lan("127.0.0.1", 27462)
	while session.get_session_member_count() < 2:
		yield(get_tree().create_timer(0.1), "timeout")
	if role == "host":
		yield(get_tree().create_timer(1), "timeout")
		var layout = CoopService.connected_players.duplicate(true)
		RunData.reset()
		RunData.set_player_count(2, true)
		RunData.set_coop_run(true)
		CoopService.connected_players = layout
		for index in 2:
			RunData.add_character(load("res://items/characters/well_rounded/well_rounded_data.tres"), index)
			RunData.add_weapon(load("res://weapons/ranged/pistol/1/pistol_data.tres"), index, true)
			RunData.players_data[index].gold = 10000
		RunData.add_weapon(load("res://weapons/ranged/pistol/1/pistol_data.tres"), 1, true)
		RunData.current_wave = 21
		RunData.is_endless_run = true
		RunData.locked_shop_items[1] = [[load("res://weapons/ranged/smg/1/smg_data.tres"), 20]]
		ZoneService.set_current_zone(ZoneService.get_zone_data(RunData.current_zone).duplicate())
		ItemService.init_unlocked_pool()
		get_tree().change_scene("res://ui/menus/shop/coop_shop.tscn")
		yield(_wait_file("first-local.json"), "completed")
		var initial = _read("first-local.json")
		var sync = menu._get_trusted_shop_sync()
		while int(sync.revisions.get(1, 0)) < int(initial.shop_owner_revision):
			yield(get_tree().create_timer(0.1), "timeout")
		_check(RunData.get_player_gold(1) == initial.gold and RunData.get_player_weapons(1).size() == 2, "host mirrors combined weapon and purchase without replay")
		_check(get_tree().current_scene._reroll_count[1] == int(initial.reroll_count), "host mirrors local reroll counters")
		var before = JSON.print(_snapshot())
		_check(sync.accept(1, initial) and JSON.print(_snapshot()) == before, "duplicate result does not charge or apply twice")
		var old = initial.duplicate(true)
		old.shop_owner_revision = int(initial.shop_owner_revision) - 1
		old.gold = 1
		_check(sync.accept(1, old) and JSON.print(_snapshot()) == before, "older revision cannot roll back the mirrored result")
		old.shop_owner_epoch = "previous-shop"
		_check(not sync.accept(1, old), "previous shop epoch is ignored")
		var peer = str(session._get_remote_ids_for_host_sync()[0])
		session._handle_run_page_action_sync(peer, {"action_type": "shop_owner_state", "player_index": 0, "owner_state": initial})
		_check(RunData.get_player_gold(0) == 10000, "a client's result stays within its assigned seats")
		_write("first-mirrored.json", {})
		yield(_wait_file("start-now.json"), "completed")
		var expected = _read("start-now.json")
		_check(JSON.print(_snapshot()) != JSON.print(expected), "final operation is still withheld when host presses Go")
		session.request_synced_shop_game_start(get_tree().current_scene, 0)
		session._pending_host_game_start.ack_deadline_msec = OS.get_ticks_msec() - 1
		session._poll_host_game_start_sync()
		_check(str(session._pending_host_game_start.get("stage", "")) == "waiting_ack", "clock timeout retries the owner barrier instead of committing old inventory")
	else:
		while not menu._get_trusted_shop_sync().owns(1) or RunData.get_player_gold(1) != 10000 or menu._client_shop_intercept_key == "":
			yield(get_tree().create_timer(0.1), "timeout")
		var shop = get_tree().current_scene
		var sync = menu._get_trusted_shop_sync()
		var stale_state = sync.snapshot(1)
		var stale_config = JSON.parse(JSON.print(menu._build_run_config_for_scene_sync(true, menu.SHOP_HELD_ITEMS_SYNC_COMPACT, true))).result
		var card = shop._get_shop_items_container(1)._shop_items[0]
		_check(card.locked and card.item_data.my_id == "weapon_smg_1", "retained locked offer is initialized")
		menu._on_client_shop_item_lock_toggled(false, card, 1)
		_check(not card.locked and RunData.get_player_locked_shop_items(1).empty(), "unlock updates visuals and native lock list immediately")
		menu._on_client_shop_item_lock_toggled(true, card, 1)
		_check(card.locked and RunData.get_player_locked_shop_items(1).size() == 1, "lock updates native state immediately")
		var gold = RunData.get_player_gold(1)
		var price = int(shop._reroll_price[1])
		var count = int(shop._reroll_count[1])
		menu._on_client_shop_reroll_pressed(1)
		_check(shop._reroll_count[1] == count + 1 and RunData.get_player_gold(1) == gold - price, "reroll result and charge apply in the input frame")
		card = shop._get_shop_items_container(1)._shop_items[0]
		_check(card.locked and card.item_data.my_id == "weapon_smg_1", "reroll retains the locked weapon")
		menu._on_client_shop_combine_weapon_pressed(RunData.get_player_weapons(1)[0], 1)
		menu._on_client_shop_item_bought(card, 1)
		_check(RunData.get_player_weapons(1).size() == 2 and RunData.get_player_weapons(1)[0].my_id == "weapon_pistol_2" and RunData.get_player_weapons(1)[1].my_id == "weapon_smg_1", "combine then buy completes before any host response")
		var before = JSON.print(_snapshot())
		menu._apply_shop_player_state_to_ui(shop, stale_state)
		var previous_visit = stale_state.duplicate(true)
		previous_visit.shop_owner_epoch = "previous-shop"
		menu._apply_shop_player_state_to_ui(shop, previous_visit)
		menu._apply_run_config_before_client_scene_change(stale_config, "shop")
		_check(JSON.print(_snapshot()) == before, "old shop epoch, snapshot and scene RunData cannot undo local results")
		_write("first-local.json", sync.snapshot(1))
		sync.flush()
		yield(_wait_file("first-mirrored.json"), "completed")
		# Delay only the normal owner-state publisher. The start ACK must carry
		# this final edit through real ENet even though no result packet was sent.
		menu._on_client_shop_discard_weapon_pressed(RunData.get_player_weapons(1)[0], 1)
		_check(RunData.get_player_weapons(1).size() == 1, "recycle applies immediately")
		# Controlled personal-state fixture: the handoff must carry more than gear/gold.
		RunData.players_data[1].current_health = 7
		RunData.players_data[1].current_level = 4
		RunData.players_data[1].current_xp = 17
		RunData.players_data[1].meca_parts = 13
		RunData.add_stat(Keys.stat_armor_hash, 9, 1)
		sync.flush_at = OS.get_ticks_msec() + 60000
		sync.resend_at = OS.get_ticks_msec() + 60000
		_write("start-now.json", _snapshot())
	while get_tree().current_scene == null or str(get_tree().current_scene.filename) != "res://main.tscn":
		yield(get_tree().create_timer(0.1), "timeout")
	var expected = _read("start-now.json")
	_check(JSON.print(_snapshot()) == JSON.print(expected), "battle starts with the final client-owned weapon and currency")
	_check(RunData.players_data[1].current_level == 4 and RunData.players_data[1].current_xp == 17 and RunData.players_data[1].meca_parts == 13 and RunData.get_player_effect(Keys.stat_armor_hash, 1) == int(expected.armor), "level, XP, chips and character effects survive the handoff")
	if role == "client":
		var received = menu._last_menu_scene_state_from_host.get("run_config", {}).get("players", [])
		_check(received.size() == 2 and int(received[1].run_data.current_health) == 7, "host start payload includes the final client health")
	_write(role + "-result.json", _snapshot())
	if role == "host":
		yield(_wait_file("client-result.json"), "completed")
	print("TRUSTED_SHOP_LAN_RESULT: ", role, " ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
