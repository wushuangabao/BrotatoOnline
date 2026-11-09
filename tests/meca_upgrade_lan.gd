extends Node

var role = OS.get_environment("BROTATO_TEST_ROLE")
var folder = OS.get_environment("BROTATO_TEST_DIR")
var session
var menu
var failures = 0

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	DebugService.disable_saving = true
	get_tree().create_timer(90).connect("timeout", self, "_timeout")
	call_deferred("_run")

func _timeout():
	printerr("MECA_UPGRADE_LAN_FAIL: watchdog " + role)
	get_tree().quit(2)

func _check(ok: bool, label: String):
	print("MECA_UPGRADE_LAN_", "PASS" if ok else "FAIL", ": ", role, " ", label)
	if not ok:
		failures += 1

func _write(name: String, value):
	var file = File.new()
	if file.open(folder.plus_file(name + ".tmp"), File.WRITE) == OK:
		file.store_string(JSON.print(value, "  "))
		file.close()
		Directory.new().rename(folder.plus_file(name + ".tmp"), folder.plus_file(name))

func _exists(name: String) -> bool:
	return File.new().file_exists(folder.plus_file(name))

func _wait_file(name: String):
	yield(get_tree(), "idle_frame")
	while not _exists(name):
		yield(get_tree().create_timer(0.1), "timeout")

func _snapshot() -> Dictionary:
	var weapon = RunData.get_player_weapons(1)[2]
	return {"rank": weapon.meca_rank, "power": weapon.meca_power, "parts": RunData.get_player_meca_parts(1), "identity": menu._build_shop_item_stable_identity(weapon)}

func _repair(name: String):
	_write(name + ".json", {})
	yield(_wait_file(name + "-sent.json"), "completed")
	yield(get_tree().create_timer(1), "timeout")

func _run():
	ProgressData.apply_settings()
	ProgressData.settings.pause_on_focus_lost = false
	get_tree().root.set_meta("brotato_online_local_input_device_mode", "keyboard")
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
		if not RunData.enabled_dlcs.has("primal_dread"):
			RunData.enabled_dlcs.append("primal_dread")
		if not ProgressData.active_update_data.has("primal_dread"):
			ProgressData.active_update_data.append("primal_dread")
		RunData.active_update_data_ids = ProgressData.active_update_data.duplicate()
		for index in 2:
			RunData.add_character(load("res://items/characters/well_rounded/well_rounded_data.tres"), index)
			var dlc = ItemService.get_dlc_data_by_id("primal_dread")
			RunData.add_weapon(load("res://weapons/ranged/pistol/1/pistol_data.tres"), index, true)
			RunData.add_weapon(load("res://weapons/ranged/smg/1/smg_data.tres"), index, true)
			var weapon = dlc.meca_item(load("res://weapons/ranged/pistol/1/pistol_data.tres"), index)
			RunData.add_weapon(DLC2Data.change_effect_option_to_modular_effect(weapon, 0), index, true)
			RunData.players_data[index].meca_parts = 1000
			RunData.players_data[index].gold = 10000
			for _item in 80:
				RunData.add_item(load("res://items/all/00_base_game/lens/lens_data.tres"), index)
		RunData.current_wave = 21
		RunData.is_endless_run = true
		ZoneService.set_current_zone(ZoneService.get_zone_data(RunData.current_zone).duplicate())
		ItemService.init_unlocked_pool()
		get_tree().change_scene("res://ui/menus/shop/coop_shop.tscn")
		while not _exists("client-result.json"):
			for name in ["repair-choice", "repair-preview"]:
				if _exists(name + ".json") and not _exists(name + "-sent.json"):
					var repair = menu._build_shop_player_state(1, get_tree().current_scene, false, false)
					menu._append_forced_shop_run_data_repair_to_delta_state(repair, 1, "test_meca_open_popup")
					menu._queue_local_run_page_action({"msg_type": "run_page_action_sync", "action_type": "shop_state", "player_index": 1, "screen": "shop", "host_state_after": repair})
					_write(name + "-sent.json", {})
			yield(get_tree().create_timer(0.1), "timeout")
		_check(RunData.get_player_weapons(1)[2].meca_rank == 7, "six confirmed upgrades reach rank seven")
	else:
		while get_tree().current_scene == null or not get_tree().current_scene.has_method("_get_item_popup") or menu._client_shop_intercept_key == "" or RunData.get_player_weapons(1).size() != 3 or RunData.get_player_meca_parts(1) != 1000:
			yield(get_tree().create_timer(0.1), "timeout")
		yield(get_tree().create_timer(1), "timeout")
		for attempt in 6:
			var shop = get_tree().current_scene
			var popup = shop._get_item_popup(1)
			var weapon = RunData.get_player_weapons(1)[2]
			var before = _snapshot()
			var element = null
			for candidate in menu._get_shop_inventory_elements(shop, 1, true):
				if candidate.item == weapon:
					element = candidate
			_check(element != null, "selected inventory element owns target weapon")
			Utils.focus_player_control(element, 1, Utils.get_focus_emulator(1))
			yield(get_tree(), "idle_frame")
			FocusEmulatorSignal.set_expected_control(element, 1)
			shop._popup_manager._on_element_pressed(element)
			yield(get_tree().create_timer(0.3), "timeout")
			if attempt == 2:
				yield(_repair("repair-preview"), "completed")
				_check(popup._item_data == RunData.get_player_weapons(1)[2], "repair before preview rebinds exact third weapon")
			popup._upgrade_button.emit_signal("pressed")
			_check(popup._pending_upgrade != null and popup._effect_choice_container.is_visible_in_tree(), "preview is visible in the input frame without a host reply")
			var deadline = OS.get_ticks_msec() + 4000
			while (popup._pending_upgrade == null or not popup._effect_choice_container.is_visible_in_tree()) and OS.get_ticks_msec() < deadline:
				yield(get_tree().create_timer(0.05), "timeout")
			_check(popup._pending_upgrade != null and popup._effect_choice_container.is_visible_in_tree(), "preview appears for attempt " + str(attempt))
			if attempt == 1:
				yield(_repair("repair-choice"), "completed")
				_check(popup._focused and popup._pending_upgrade != null and popup._effect_choice_container.is_visible_in_tree(), "same-weapon correction preserves open upgrade choices")
				_check(menu._shop_item_matches_stable_identity(popup._item_data, before.identity), "same-weapon correction keeps selected weapon")
				_check(popup._item_data == RunData.get_player_weapons(1)[2], "repair rebinds popup Resource and keeps exact slot")
				menu._submit_local_shop_action({"msg_type": "run_page_action_sync", "action_type": "shop_meca_upgrade", "screen": "shop", "player_index": 1, "weapon_slot_index": 2, "item_identity": before.identity, "preview_id": "invalid-test-token", "effect_choice": 0, "chosen_effect": []}, 1, "shop_meca_upgrade")
				yield(get_tree().create_timer(1), "timeout")
				_check(popup._focused and popup._pending_upgrade != null and popup._effect_choice_container.is_visible_in_tree() and _snapshot().parts == before.parts, "rejected confirmation keeps choices and charges nothing")
			var choice = attempt % 2
			var shown = menu._meca_choice_descriptor(popup._pending_upgrade, choice)
			var button = popup._effect_button_0 if choice == 0 else popup._effect_button_1
			button.emit_signal("pressed")
			_check(RunData.get_player_weapons(1)[2].meca_rank == before.rank + 1, "upgrade applies in the input frame without a host reply")
			if attempt == 4:
				button.emit_signal("pressed")
			# Exercise focus traffic alongside the authoritative inventory response.
			menu._queue_local_run_page_action({"msg_type": "run_page_action_sync", "action_type": "shop_focus", "screen": "shop", "player_index": 1, "target": "weapon_2"})
			_write("request-" + str(attempt) + ".json", {"before": before, "shown": shown, "preview": menu._get_dlc_shop_actions().client_previews.get(1, {}), "queued": menu._queued_local_run_page_action_messages})
			yield(get_tree().create_timer(1), "timeout")
			deadline = OS.get_ticks_msec() + 3000
			while RunData.get_player_weapons(1)[2].meca_rank == before.rank and OS.get_ticks_msec() < deadline:
				yield(get_tree().create_timer(0.1), "timeout")
			var after = _snapshot()
			_check(after.rank == before.rank + 1 and after.parts == before.parts - before.rank - 1, "one choice upgrades once and charges once: " + str(attempt))
			var focused = Utils.get_focus_emulator(1).focused_control
			_check(is_instance_valid(focused) and menu._safe_get(focused, "item", null) == RunData.get_player_weapons(1)[2], "successful upgrade keeps focus on upgraded weapon: " + str(attempt))
			_write("after-" + str(attempt) + ".json", after)
		# Controlled late-success delivery at the production popup completion boundary.
		# The player has already opened another weapon before the old reply arrives.
		var shop = get_tree().current_scene
		var popup = shop._get_item_popup(1)
		var dlc_actions = menu._get_dlc_shop_actions()
		var weapons = RunData.get_player_weapons_ref(1)
		var other = null
		for element in menu._get_shop_inventory_elements(shop, 1, true):
			if element.item == weapons[0]:
				other = element
		Utils.focus_player_control(other, 1, Utils.get_focus_emulator(1))
		yield(get_tree(), "idle_frame")
		FocusEmulatorSignal.set_expected_control(other, 1)
		shop._popup_manager._on_element_pressed(other)
		dlc_actions.client_previews[1] = {"preview_id": "late-test-success", "source": menu._build_shop_item_stable_identity(weapons[2])}
		dlc_actions.client_preview_sources[1] = weapons[2]
		dlc_actions.finish_client_upgrade(shop, 1, {"preview_id": "late-test-success", "host_state_after": {"host_applied": true}})
		_check(popup._focused and popup._item_data == weapons[0], "late success cannot close another weapon popup")
		var restored_copy = menu._resolve_item_parent_data(menu._serialize_item_parent_data(weapons[2]), false)
		_check(dlc_actions.weapon_slot(1, restored_copy) == 2, "serialized mechanical copy resolves by complete identity, not weapon family")
		var stale_copy = menu._resolve_item_parent_data(menu._serialize_item_parent_data(weapons[0]), false)
		var identical_copy = menu._resolve_item_parent_data(menu._serialize_item_parent_data(weapons[0]), false)
		_check(stale_copy != weapons[0] and identical_copy != stale_copy and identical_copy != weapons[0], "identity fixture uses distinct deserialized resources")
		weapons.append(identical_copy)
		_check(dlc_actions.weapon_slot(1, stale_copy) == -1, "ambiguous stale copies cannot select an arbitrary slot")
		_check(dlc_actions.weapon_slot(1, weapons[0]) == 0, "live identical copies retain exact resource slot")
		dlc_actions.client_previews[1] = {"preview_id": "identical-test-success", "source": menu._build_shop_item_stable_identity(identical_copy)}
		dlc_actions.client_preview_sources[1] = identical_copy
		dlc_actions.finish_client_upgrade(shop, 1, {"preview_id": "identical-test-success", "host_state_after": {"host_applied": true}})
		_check(popup._focused and popup._item_data == weapons[0], "late success for identical copy cannot close current weapon popup")
		weapons.remove(weapons.size() - 1)
		_write("client-result.json", _snapshot())
	_write(role + "-result.json", _snapshot())
	print("MECA_UPGRADE_LAN_RESULT: ", role, " ", "PASS" if failures == 0 else "FAIL")
	if role == "host":
		yield(get_tree().create_timer(0.5), "timeout")
	get_tree().quit(0 if failures == 0 else 1)
