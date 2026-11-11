extends "res://mods-unpacked/Local-NoobsProbe/base_probe.gd"

var role = OS.get_environment("BROTATO_TEST_ROLE")
var folder = OS.get_environment("BROTATO_TEST_DIR")
var session
var manager
var character
var elapsed = 0.0
var busy = false
var command_id = 0
var result = {}
var hold_settlement = false
var held_timer = null

func _init():
	ModLoaderMod.install_script_extension("res://mods-unpacked/Local-NoobsProbe/online_session_fixture.gd")

func _run():
	# The shared probe's deferred entry is not the online command driver.
	pass

func _timeout():
	if OS.get_ticks_msec() > 350000:
		printerr("NWTL_FAIL: online probe timeout")
		get_tree().quit(1)

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	DebugService.disable_saving = true
	DebugService.no_enemies = true
	get_tree().create_timer(360).connect("timeout", self, "_timeout")
	call_deferred("_boot")

func _boot():
	ProgressData.settings.pause_on_focus_lost = false
	ProgressData.apply_settings()
	TranslationServer.set_locale("zh")
	session = get_tree().root.find_node("BrotatoOnlineSessionManager", true, false)
	manager = get_tree().root.find_node("BrotatoOnlineMenuSyncManager", true, false)
	session._lan_transport.connect("packet_received", self, "_observe_packet")
	for entry in ItemService.characters:
		if entry.my_id == ("character_streamer" if OS.get_environment("BROTATO_TEST_CHARACTER") == "streamer" else Catalog.PREFIX + "xiao_tian_cai"):
			character = entry
	get_tree().change_scene(MenuData.character_selection_scene if role == "host" else MenuData.title_screen_scene)

func _observe_packet(_transport, _peer, bytes, _channel):
	var parsed = JSON.parse(bytes.get_string_from_utf8())
	if parsed.error == OK and parsed.result is Dictionary and parsed.result.get("msg_type", "") == "run_page_action_sync":
		var data = parsed.result
		if data.get("action_type", "") == "shop_owner_state":
			var packet_file = File.new()
			packet_file.open(folder.plus_file(role + "-owner-packet-" + str(OS.get_ticks_msec()) + ".json"), File.WRITE)
			packet_file.store_string(JSON.print(data))
			packet_file.close()
		print("NWTL_PACKET ", role, " ", data.get("action_type"), " wire=", data.get("session_lobby_id"), " expected=", session._get_wire_session_id(), " owner=", session._get_slot_manager().resolve_owned_player_index(str(data.get("origin_steam_id", "")), int(data.get("player_index", -1))))

func _process(delta):
	var main = get_tree().current_scene
	if hold_settlement and held_timer == null and main is Main and main._cleaning_up:
		held_timer = main._end_wave_timer
		held_timer.paused = true
	elapsed += delta
	if elapsed < 0.1 or session == null:
		return
	elapsed = 0
	_snapshot()
	if busy:
		return
	var file = File.new()
	if file.open(folder.plus_file(role + "-command.json"), File.READ) != OK:
		return
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or int(parsed.result.get("id", 0)) <= command_id:
		return
	busy = true
	call_deferred("_execute", parsed.result)

func _execute(command):
	scene = get_tree().current_scene
	var index = int(command.get("player", 0 if role == "host" else 1))
	result = {"action":command.action}
	match command.action:
		"host":
			session._get_mod_settings_manager().set_lan_host_port(int(OS.get_environment("BROTATO_TEST_PORT")))
			session.create_session(false)
		"join":
			session.join_lan("127.0.0.1", int(OS.get_environment("BROTATO_TEST_PORT")))
		"nested_effect_roundtrip":
			# Materialized description args and modified nested burning data must not
			# fall back to the receiving peer's untouched asset template.
			var weapon = load("res://weapons/melee/wrench/2/wrench_2_data.tres").duplicate()
			weapon.effects = [weapon.effects[0].duplicate()]
			var effect = weapon.effects[0]
			effect.effects = [effect.effects[0].duplicate()]
			effect.effects[0].burning_data = effect.effects[0].burning_data.duplicate()
			effect.custom_args = [load("res://items/global/custom_arg.gd").new()]
			effect.custom_args[0].arg_value = 7
			effect.effects[0].burning_data.damage = 17
			var sync = manager._get_upgrade_runtime_sync()
			var encoded = sync.serialize_item_effect_state(weapon)
			result["serialized_nested_effect"] = encoded[0].has("serialized_effect")
			var restored = load("res://weapons/melee/wrench/2/wrench_2_data.tres").duplicate()
			sync.apply_item_effect_state(restored, JSON.parse(JSON.print(encoded)).result)
			result["same_native_state"] = JSON.print(effect.serialize(), "", true) == JSON.print(restored.effects[0].serialize(), "", true)
			result["burning_damage"] = restored.effects[0].effects[0].burning_data.damage
			result["custom_args"] = restored.effects[0].custom_args.size()
		"lifecycle_checks":
			result["checks"] = load("res://mods-unpacked/Local-NoobsProbe/effect_lifecycle_checks.gd").new().run(manager)
		"lifecycle_fixture":
			load("res://mods-unpacked/Local-NoobsProbe/effect_lifecycle_checks.gd").new().fixture(self)
		"render_effects":
			for item in RunData.players_data[index].weapons + RunData.players_data[index].items:
				for effect in item.effects:
					effect.get_text(index)
		"fixture":
			var layout = CoopService.connected_players.duplicate(true)
			RunData.reset()
			RunData.set_player_count(2, true)
			RunData.set_coop_run(true)
			CoopService.connected_players = layout
			for i in 2:
				RunData.add_character(character, i)
				RunData.add_weapon(load("res://weapons/melee/wrench/1/wrench_data.tres"), i)
			RunData.add_item(load("res://items/all/00_base_game/landmines/landmines_data.tres"), 1)
			RunData.current_wave = int(OS.get_environment("BROTATO_TEST_WAVE"))
			RunData.is_endless_run = RunData.current_wave >= 20
			ProgressData.settings.endless_mode_toggled = RunData.is_endless_run
			RunData.invulnerable = true
			ZoneService.set_current_zone(ZoneService.get_zone_data(RunData.current_zone).duplicate())
			ItemService.init_unlocked_pool()
			for data in RunData.players_data:
				data.gold = 5000
			get_tree().change_scene("res://ui/menus/shop/coop_shop.tscn")
		"go":
			Utils.focus_player_control(scene._get_go_button(index), index)
			yield(settle(4), "completed")
			scene._get_go_button(index).emit_signal("pressed")
			result["paused"] = get_tree().paused
			result["pressed"] = scene._player_pressed_go_button.duplicate()
			result["queued"] = manager._queued_local_run_page_action_messages.duplicate(true)
		"sell_wrench":
			var weapon = RunData.get_player_weapons_ref(index)[0]
			scene._get_item_popup(index).emit_signal("item_discard_button_pressed", weapon)
		"set_offer":
			var path = "res://weapons/melee/wrench/1/wrench_data.tres" if command.get("item", "wrench") == "wrench" else "res://items/all/00_base_game/landmines/landmines_data.tres"
			var card = scene._get_shop_items_container(index)._shop_items[0]
			card.set_shop_item(load(path).duplicate(), RunData.current_wave)
			result["price"] = card.value
		"buy":
			var card = scene._get_shop_items_container(index)._shop_items[0]
			result["price"] = card.value
			card.emit_signal("buy_button_pressed", card)
		"combine":
			scene._get_item_popup(index).emit_signal("item_combine_button_pressed", RunData.get_player_weapons_ref(index)[0])
		"repeat_snapshot":
			# Exercise the real full-state receiver with the same wire-shaped state.
			# This is controlled duplicate application, not a claim of packet replay.
			var data = manager._serialize_player_run_data_for_shop_sync(index, manager.SHOP_HELD_ITEMS_SYNC_COMPACT)
			data = JSON.parse(JSON.print(data)).result
			result["applied"] = 0
			for _n in 3:
				if manager._apply_one_serialized_player_run_data(index, data, true):
					result.applied += 1
		"finish_wave":
			scene._wave_timer.start(0.2)
		"hold_settlement":
			hold_settlement = true
			held_timer = null
		"release_settlement":
			hold_settlement = false
			if is_instance_valid(held_timer):
				held_timer.paused = false
			held_timer = null
		"progression_confirm":
			var ui = scene.get("_coop_upgrades_ui")
			if ui != null and ui.visible:
				var button = ui._get_player_container(index).get_focus_control()
				if button.is_visible_in_tree() and not button.disabled:
					button.emit_signal("pressed")
		"reroll":
			scene._get_reroll_button(index).emit_signal("pressed")
		"screenshot":
			shot(role + "-" + command.label)
		"quit":
			get_tree().quit()
	yield(settle(3), "completed")
	command_id = int(command.id)
	busy = false
	_snapshot()

func _snapshot():
	var current_scene = get_tree().current_scene
	var state = {"command":command_id, "result":result, "scene":current_scene.filename if current_scene else "", "online":session.is_online_session_active(), "members":session.get_session_member_count(), "role":session.get_online_role(), "players":[], "wave":RunData.current_wave, "progression_ready":[]}
	state["endless_sync"] = manager._should_use_endless_incremental_items_only_shop_sync()
	state["shop_epoch"] = manager._get_trusted_shop_sync().epoch
	state["paused"] = get_tree().paused
	state["settlement_held"] = is_instance_valid(held_timer) and held_timer.paused
	state["wave_settled"] = current_scene.get_meta("bo_wave_run_data_settled", false) if current_scene is Main else false
	state["origin"] = session._self_steam_id
	state["session"] = session.get_session_id()
	state["lan_host"] = session._lan_transport.is_hosting()
	state["roster"] = CoopService.connected_players
	state["sent_seq"] = session._local_run_page_action_seq
	state["received_seq"] = manager._last_run_page_action_seq_by_origin
	var slots = get_tree().root.find_node("BrotatoOnlineOnlinePlayerSlotManager", true, false)
	state["owners"] = slots._remote_steam_id_by_device
	state["pressed"] = current_scene._player_pressed_go_button if current_scene != null and current_scene.has_method("_get_go_button") else []
	state["shop_ready"] = []
	state["go_hooked"] = false
	if current_scene != null and current_scene.has_method("_get_go_button"):
		for i in RunData.get_player_count():
			state.shop_ready.append(not current_scene._get_go_button(i).disabled)
		var owner_index = 0 if role == "host" else 1
		if owner_index < RunData.get_player_count():
			state.go_hooked = current_scene._get_go_button(owner_index).is_connected("pressed", manager, "_on_host_shop_go_pressed" if role == "host" else "_on_client_shop_go_pressed")
	for i in RunData.get_player_count():
		var data = {"local":manager._is_local_client_player_index(i), "character":RunData.players_data[i].current_character.my_id if RunData.players_data[i].current_character else ""}
		data["luck"] = Utils.get_stat(Keys.stat_luck_hash, i)
		data["structures"] = RunData.get_nb_structures(i)
		data["armor"] = Utils.get_stat(Keys.stat_armor_hash, i)
		data["engineering"] = Utils.get_stat(Keys.stat_engineering_hash, i)
		data["damage_gain"] = RunData.get_stat_gain(Keys.stat_melee_damage_hash, i)
		data["weapon_count"] = RunData.get_player_weapons_ref(i).size()
		data["weapons"] = []
		for weapon in RunData.get_player_weapons_ref(i):
			data.weapons.append([weapon.my_id, weapon.tier])
		data["gold"] = RunData.get_player_gold(i)
		data["max_hp"] = RunData.get_player_max_health(i)
		data["landmines"] = RunData.get_nb_item(Keys.generate_hash("item_landmines"), i)
		data["duplicate_count"] = RunData.get_duplicate_items_count(i)
		data["different_items"] = RunData.get_nb_different_items_of_tier(-1, i)
		data["tool_set_bonus"] = RunData.get_player_effect(Keys.weapon_set_bonus_hash, i)
		data["tool_engineering"] = []
		for bonus in ItemService.get_set(Keys.generate_hash("set_tool")).set_bonuses:
			data.tool_engineering.append(bonus[0].value)
		data["structure_refs"] = []
		for effect in RunData.get_player_effect(Keys.structures_hash, i):
			var owners = []
			for item in RunData.players_data[i].items + RunData.players_data[i].weapons:
				if item.effects.has(effect):
					owners.append(item.my_id)
			data.structure_refs.append({"instance":effect.get_instance_id(), "owners":owners, "serialized":effect.serialize()})
		data["inventory_effects"] = []
		for item in RunData.players_data[i].items + RunData.players_data[i].weapons:
			for effect in item.effects:
				if effect is StructureEffect:
					data.inventory_effects.append({"item":item.my_id, "instance":effect.get_instance_id(), "serialized":effect.serialize()})

		if current_scene is Main and i < current_scene._players.size():
			var player = current_scene._players[i]
			data["live_armor"] = player.current_stats.armor
		if OS.get_environment("BROTATO_TEST_SUITE") == "lifecycle":
			data["lifecycle"] = load("res://mods-unpacked/Local-NoobsProbe/effect_lifecycle_checks.gd").new().snapshot(i)
		state.players.append(data)
		var ui = current_scene.get("_coop_upgrades_ui") if current_scene is Main else null
		var ready = false
		if ui != null and ui.visible:
			var button = ui._get_player_container(i).get_focus_control()
			ready = button.is_visible_in_tree() and not button.disabled
		state.progression_ready.append(ready)
	var file = File.new()
	file.open(folder.plus_file(role + "-state.json"), File.WRITE)
	file.store_string(JSON.print(state))
	file.close()
