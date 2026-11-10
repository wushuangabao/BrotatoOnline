extends "res://mods-unpacked/Local-NoobsProbe/base_probe.gd"

var role = OS.get_environment("BROTATO_TEST_ROLE")
var folder = OS.get_environment("BROTATO_TEST_DIR")
var session
var manager
var dog
var elapsed = 0.0
var busy = false
var command_id = 0
var result = {}
var hold_settlement = false
var held_timer = null
var step_baseline = {}
var prior_report = {}
var combat_ticks = 0
var prior_peer = ""

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
	ProgressData.settings.retry_wave = true
	ProgressData.apply_settings()
	TranslationServer.set_locale("zh")
	session = get_tree().root.find_node("BrotatoOnlineSessionManager", true, false)
	manager = get_tree().root.find_node("BrotatoOnlineMenuSyncManager", true, false)
	session._lan_transport.connect("packet_received", self, "_observe_packet")
	for entry in ItemService.characters:
		if entry.my_id == (OS.get_environment("BROTATO_TEST_CHARACTER") if OS.get_environment("BROTATO_TEST_CHARACTER") != "" else Catalog.PREFIX + "an_mao"):
			dog = entry
	get_tree().change_scene(MenuData.character_selection_scene if role == "host" else MenuData.title_screen_scene)

func _observe_packet(_transport, _peer, bytes, _channel):
	var parsed = JSON.parse(bytes.get_string_from_utf8())
	if parsed.error == OK and parsed.result is Dictionary and parsed.result.get("msg_type", "") == "run_page_action_sync":
		var data = parsed.result
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
		"export_full":
			result["state"] = manager._serialize_player_run_data_for_shop_sync(index, "full")
		"snapshot_order":
			var ledger = get_tree().root.find_node("BrotatoOnlineMovementRewards", true, false)
			ledger.totals.erase(index)
			manager._apply_one_serialized_player_run_data(index, command.state, false)
			var before = JSON.print(ledger.capture(index).effects)
			ledger.apply_total(index, command.state.online_movement_rewards, false)
			result["before"] = before
			result["after"] = JSON.print(ledger.capture(index).effects)
			result["record"] = command.state.online_movement_rewards
			result["valid"] = ledger._valid(command.state.online_movement_rewards) and not command.state.online_movement_rewards.effects.empty()
			result["stable"] = before == JSON.print(ledger.capture(index).effects)
			var newer = command.state.online_movement_rewards.duplicate(true)
			newer.revision += 1
			newer.gold += 6
			for key in newer.effects:
				newer.effects[key] += 1
			ledger.apply_total(index, newer, false)
			var newer_effects = JSON.print(ledger.capture(index).effects)
			manager._apply_one_serialized_player_run_data(index, command.state, false)
			result["older_snapshot"] = newer_effects == JSON.print(ledger.capture(index).effects)
			ledger.totals.erase(index)
			manager._apply_one_serialized_player_run_data(index, command.state, false)

		"capture_report":
			var ledger = get_tree().root.find_node("BrotatoOnlineMovementRewards", true, false)
			prior_peer = str(session._get_remote_ids_for_host_sync()[0])
			prior_report = {"msg_type":"movement_rewards", "epoch":ledger.epoch, "records":{"1":ledger.get_total(1)}, "session_lobby_id":session._get_wire_session_id(), "battle_start_id":session._host_current_battle_start_id}
		"replay_prior":
			var ledger = get_tree().root.find_node("BrotatoOnlineMovementRewards", true, false)
			var before = JSON.print(ledger.capture(1))
			ledger.receive(prior_peer, prior_report)
			ledger.receive(prior_peer, prior_report)
			result["unchanged"] = before == JSON.print(ledger.capture(1))
		"loss":
			session.drop_reports = int(command.get("reports", 0))
			session.drop_acks = int(command.get("acks", 0))
		"die":
			RunData.invulnerable = false
			var args = TakeDamageArgs.new(-1)
			args.dodgeable = false
			args.armor_applied = false
			args.bypass_invincibility = true
			for player in scene._players:
				if session._get_slot_manager().get_local_player_indices().has(player.player_index):
					player.take_damage(999999, args)
		"retry_confirm":
			session._get_retry_wave_confirm_button(session._get_retry_wave_node()).emit_signal("pressed")
		"combat_timer":
			var timer = Timer.new()
			timer.wait_time = 0.05
			scene.add_child(timer)
			timer.connect("timeout", self, "_combat_tick")
			timer.start()
		"disconnect":
			session._handle_client_host_disconnect("movement_rewards_wait_test")
		"hard_rejoin":
			session._handle_client_host_disconnect("movement_rewards_rejoin_test")
			while get_tree().current_scene.filename != MenuData.title_screen_scene:
				yield(get_tree().create_timer(0.1), "timeout")
			session.join_lan("127.0.0.1", int(OS.get_environment("BROTATO_TEST_PORT")))
		"reconnect":
			session._lan_transport._begin_client_reconnect("movement_rewards_test")
			yield(get_tree().create_timer(0.2), "timeout")
			while session._lan_transport._reconnect_active:
				yield(get_tree().create_timer(0.1), "timeout")
			result["online"] = session.is_online_session_active()
		"join":
			session.join_lan("127.0.0.1", int(OS.get_environment("BROTATO_TEST_PORT")))
		"add_seat":
			if role == "host":
				CoopService._add_player(6, CoopService.PlayerType.GAMEPAD_XBOX)
			else:
				while not CoopService.listening_for_inputs:
					yield(get_tree().create_timer(0.1), "timeout")
				var event = InputEventJoypadButton.new()
				event.device = 0 # Native input maps pad 0 to CoopService device 6.
				event.button_index = JOY_BUTTON_0
				event.pressed = true
				Input.parse_input_event(event)
				while session._get_slot_manager().get_local_player_indices().size() < 2:
					yield(get_tree().create_timer(0.1), "timeout")
				event.pressed = false
				Input.parse_input_event(event)
		"fixture":
			var layout = CoopService.connected_players.duplicate(true)
			RunData.reset()
			RunData.set_player_count(layout.size(), true)
			RunData.set_coop_run(true)
			CoopService.connected_players = layout
			for i in layout.size():
				RunData.add_character(dog, i)
			RunData.current_wave = 1
			RunData.invulnerable = true
			ZoneService.set_current_zone(ZoneService.get_zone_data(RunData.current_zone).duplicate())
			ItemService.init_unlocked_pool()
			for data in RunData.players_data:
				data.gold = 1000
			get_tree().change_scene("res://ui/menus/shop/coop_shop.tscn")
		"go":
			Utils.focus_player_control(scene._get_go_button(index), index)
			yield(settle(4), "completed")
			scene._get_go_button(index).emit_signal("pressed")
			result["paused"] = get_tree().paused
			result["pressed"] = scene._player_pressed_go_button.duplicate()
			result["queued"] = manager._queued_local_run_page_action_messages.duplicate(true)
		"walk":
			var player = scene._players[index]
			var start = player.global_position
			player._move_locked = true
			player._current_movement = Vector2.RIGHT if float(command.get("direction", 1)) > 0 else Vector2.LEFT
			yield(get_tree().create_timer(1.8), "timeout")
			player._current_movement = Vector2.ZERO
			result["distance"] = start.distance_to(player.global_position)
		"cat_restore":
			var original = JSON.parse(JSON.print(manager._serialize_player_run_data_for_shop_sync(index, "full"))).result
			original["tracked_item_effects"] = manager._build_shop_tracked_item_effects_snapshot(index)
			var gained = int(RunData.tracked_item_effects[index].get(dog.my_id_hash, 0))
			var stale = step_baseline[index].duplicate(true)
			stale.effects[str(Keys.bonus_crit_damage_hash)] += 50
			manager._apply_one_serialized_player_run_data(index, stale, true)
			manager._apply_one_serialized_player_run_data(index, stale, true)
			result["preserved"] = RunData.get_player_effect(Keys.bonus_crit_damage_hash, index) == gained + 50 and RunData.tracked_item_effects[index][dog.my_id_hash] == gained
			manager._apply_one_serialized_player_run_data(index, stale, false)
			result["retry"] = RunData.get_player_effect(Keys.bonus_crit_damage_hash, index) == int(stale.effects[str(Keys.bonus_crit_damage_hash)]) and RunData.tracked_item_effects[index][dog.my_id_hash] == int(stale.tracked_item_effects[str(dog.my_id_hash)])
			manager._apply_one_serialized_player_run_data(index, original, false)
		"cat_steps":
			if not step_baseline.has(index) or int(step_baseline[index].get("test_wave", -1)) != RunData.current_wave:
				step_baseline[index] = JSON.parse(JSON.print(manager._serialize_player_run_data_for_shop_sync(index, "full"))).result
				step_baseline[index]["tracked_item_effects"] = manager._build_shop_tracked_item_effects_snapshot(index)
				step_baseline[index]["test_wave"] = RunData.current_wave
			var actor = scene._players[index]
			var behavior = find_steps(actor)
			var steps = float(command.get("steps", 80))
			behavior.on_moved(Vector2(steps * actor.get_move_speed() * behavior._move_animation_duration_secs / actor._animation_player.playback_speed / 2.0, 0))
			result["steps"] = behavior._steps_taken
		"hit_trap":
			# Use a real trail-created trap and actual Enemy overlap / native explosion.
			var traps = scene._players[index].get_node("NoobsPoopTrail").traps
			var trap = null
			for candidate in traps:
				if is_instance_valid(candidate):
					trap = candidate
					break
			if trap == null:
				result["error"] = "no walking trap"
			else:
				for candidate in get_tree().get_nodes_in_group("nwtl_poop_traps"):
					if candidate != trap:
						candidate.queue_free()
				yield(settle(3), "completed")
				var at = trap.global_position
				var enemy = _enemy(at)
				var neighbour = _enemy(at + Vector2(50, 0))
				var before = RunData.tracked_item_effects[index][dog.my_id_hash]
				yield(get_tree().create_timer(0.5), "timeout")
				result["damage"] = 1000 - enemy.current_stats.health
				result["area_damage"] = 1000 - neighbour.current_stats.health
				result["tracked_delta"] = RunData.tracked_item_effects[index][dog.my_id_hash] - before
				result["consumed"] = not is_instance_valid(trap)
				enemy.queue_free()
				neighbour.queue_free()
		"native_tracking":
			result["keys"] = {}
			for key in ["character_bull", "character_lucky", "character_lich", "character_glutton", "character_ogre", "item_rip_and_tear"]:
				var hash_key = Keys.generate_hash(key)
				var before = RunData.tracked_item_effects[index].get(hash_key, 0)
				var at = scene._players[index].global_position + Vector2(0, -200)
				var enemy = _enemy(at)
				var effect = load("res://items/characters/bull/bull_effect_4.tres").duplicate()
				var args = WeaponServiceExplodeArgs.new()
				args.pos = at + Vector2(0,-12)
				args.damage = 13
				args.accuracy = 1.0
				args.crit_chance = 0.0
				args.crit_damage = 1.0
				args.burning_data = BurningData.new()
				args.from_player_index = index
				args.damage_tracking_key_hash = hash_key
				args.from = scene._players[index]
				WeaponService.explode(effect, args)
				yield(get_tree().create_timer(0.4), "timeout")
				result["keys"][key] = {"damage":1000-enemy.current_stats.health,"gain":RunData.tracked_item_effects[index].get(hash_key,0)-before}
				enemy.queue_free()
		"custom_tracking":
			RunData.tracked_item_effects[index][Keys.generate_hash("online_test_array")] = command.get("array", [0,0] if bool(command.get("zero",false)) else [11,22])
			RunData.tracked_item_effects[index][Keys.generate_hash("online_test_scalar")] = command.get("scalar", 0 if bool(command.get("zero",false)) else 33)
		"gold_bonus":
			RunData.add_gold(int(command.amount), index)
		"ledger_guards":
			var ledger = get_tree().root.find_node("BrotatoOnlineMovementRewards", true, false)
			var remote = session._get_remote_ids_for_host_sync()[0]
			var total = ledger.get_total(1)
			var packet = {"msg_type":"movement_rewards", "epoch":ledger.epoch, "records":{"1":total}, "session_lobby_id":session._get_wire_session_id(), "battle_start_id":session._host_current_battle_start_id}
			var before = ledger.capture(1)
			ledger.receive(remote, packet)
			ledger.receive(remote, packet)
			result["duplicate"] = JSON.print(ledger.capture(1)) == JSON.print(before)
			var stale = packet.duplicate(true)
			stale.records["1"].revision = max(0, int(total.revision)-1)
			stale.records["1"].gold += 999
			ledger.receive(remote, stale)
			result["stale"] = JSON.print(ledger.capture(1)) == JSON.print(before)
			var other_before = ledger.capture(0)
			var spoof = packet.duplicate(true)
			spoof.records = {"0":total}
			ledger.receive(remote, spoof)
			result["wrong_owner"] = JSON.print(ledger.capture(0)) == JSON.print(other_before)
			var previous = packet.duplicate(true)
			previous.battle_start_id -= 1
			previous.epoch += ":old-retry"
			previous.records["1"].revision += 1
			previous.records["1"].gold += 999
			ledger.receive(remote, previous)
			result["wrong_generation"] = JSON.print(ledger.capture(1)) == JSON.print(before)
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
		"add_luck_item":
			# A persistent native item survives inventory reconstruction at handoff.
			RunData.add_item(load("res://items/all/00_base_game/clover/clover_data.tres"), index)
		"compact_check":
			var owned = {dog.my_id_hash:true}
			var state = manager._build_shop_tracked_item_effects_snapshot(index, owned)
			result["included"] = []
			for key in ["nwtl_dog_damage_current_wave", "nwtl_dog_damage_last_wave", "nwtl_dog_statistics_started"]:
				result.included.append(state.has(str(Keys.generate_hash(key))))
		"restore_check":
			var before = RunData.tracked_item_effects[index].duplicate(true)
			var luck_before = Utils.get_stat(Keys.stat_luck_hash, index)
			# Native deserialization expects string dictionary keys from the wire.
			var data = JSON.parse(JSON.print(RunData.players_data[index].serialize())).result
			data["tracked_item_effects"] = {}
			for key in [dog.my_id, "nwtl_dog_damage_current_wave", "nwtl_dog_damage_last_wave", "nwtl_dog_statistics_started"]:
				data.tracked_item_effects[str(Keys.generate_hash(key))] = 0
			manager._apply_one_serialized_player_run_data(index, data, true)
			result["preserved"] = true
			result["before"] = []
			result["after"] = []
			for key in [dog.my_id, "nwtl_dog_damage_current_wave", "nwtl_dog_damage_last_wave", "nwtl_dog_statistics_started"]:
				var hash_key = Keys.generate_hash(key)
				result.before.append(before.get(hash_key, 0))
				result.after.append(RunData.tracked_item_effects[index].get(hash_key, 0))
				if result.before.back() != result.after.back():
					result.preserved = false
			manager._apply_one_serialized_player_run_data(index, data, false)
			result["retry_restored"] = RunData.tracked_item_effects[index][dog.my_id_hash] == 0
			RunData.tracked_item_effects[index] = before
			Utils.reset_stat_cache(index)
			result["luck_unchanged"] = Utils.get_stat(Keys.stat_luck_hash, index) == luck_before
		"capture_screen":
			var screen = get_viewport().get_texture().get_data()
			screen.flip_y()
			screen.save_png(folder.plus_file(role + "-" + str(command.get("label", "screen")) + ".png"))
		"screenshot":
			var element = scene._get_gear_container(index).items_container._elements.get_child(0)
			scene._get_item_popup(index).display_element(element)
			yield(settle(10), "completed")
			scene._get_item_popup(index)._panel.get_description_scroll().scroll_vertical = 10000
			yield(settle(10), "completed")
			shot(role + "-" + command.label)
		"quit":
			get_tree().quit()
	yield(settle(3), "completed")
	command_id = int(command.id)
	busy = false
	_snapshot()

func _combat_tick():
	combat_ticks += 1

func _enemy(position):
	var args = EntitySpawner.SpawnEntityArgs.new(position, EntityType.ENEMY)
	var enemy = scene._entity_spawner.spawn_entity(load("res://entities/units/enemies/crash_zone/basic/baby_alien/baby_alien.tscn"), args)
	enemy._can_move = false
	enemy._prevent_contact_damage = true
	enemy.current_stats.health = 1000
	return enemy

func _snapshot():
	var current_scene = get_tree().current_scene
	var state = {"command":command_id, "result":result, "scene":current_scene.filename if current_scene else "", "online":session.is_online_session_active(), "members":session.get_session_member_count(), "role":session.get_online_role(), "players":[], "wave":RunData.current_wave, "progression_ready":[]}
	var ledger = get_tree().root.find_node("BrotatoOnlineMovementRewards", true, false)
	var replica = get_tree().root.find_node("BrotatoOnlineBattleReplicaManager", true, false)
	state["retries"] = RunData.retries
	state["retry_visible"] = session._is_retry_wave_visible(session._get_retry_wave_node())
	state["dropped_reports"] = session.dropped_reports
	state["dropped_acks"] = session.dropped_acks
	state["start_guard"] = manager._is_game_start_guard_active()
	state["ec_debug"] = replica._latest_snapshot.get("economy_state", {})
	state["ledger"] = {"epoch":ledger.epoch,"totals":ledger.totals,"stamp":ledger.last_economy_stamp,"reports":ledger.reports_sent,"ack":ledger.acknowledged,"waiting":is_instance_valid(ledger.waiting_main)}
	state["shop_epoch"] = manager._get_trusted_shop_sync().epoch
	state["paused"] = get_tree().paused
	state["combat_ticks"] = combat_ticks
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
		var tracked = RunData.tracked_item_effects[i]
		var data = {"total":tracked.get(dog.my_id_hash, 0), "current":tracked.get(Keys.generate_hash("nwtl_dog_damage_current_wave"),0), "last":tracked.get(Keys.generate_hash("nwtl_dog_damage_last_wave"),0), "local":manager._is_local_client_player_index(i), "traps":0, "spawned":0, "character":RunData.players_data[i].current_character.my_id if RunData.players_data[i].current_character else ""}
		data["gold"] = RunData.get_player_gold(i)
		data["max_hp"] = Utils.get_stat(Keys.stat_max_hp_hash, i)
		data["custom_array"] = tracked.get(Keys.generate_hash("online_test_array"), [])
		data["custom_scalar"] = tracked.get(Keys.generate_hash("online_test_scalar"), 0)
		data["stock"] = {}
		for key in ["character_bull", "character_lucky", "character_lich", "character_glutton", "character_ogre", "item_rip_and_tear"]:
			data.stock[key] = tracked.get(Keys.generate_hash(key),0)
		data["all_tracking"] = tracked.duplicate(true)
		data["crit_bonus"] = RunData.get_player_effect(Keys.bonus_crit_damage_hash, i)
		data["steps"] = RunData.steps_taken_this_wave[i]
		data["luck"] = Utils.get_stat(Keys.stat_luck_hash, i)
		if current_scene is Main and i < current_scene._players.size():
			var player = current_scene._players[i]
			var trail = player.get_node_or_null("NoobsPoopTrail")
			data["position"] = [player.global_position.x, player.global_position.y]
			data["actor_max_hp"] = player.max_stats.health
			if trail:
				data.spawned = trail.total_spawned
				for trap in trail.traps:
					if is_instance_valid(trap):
						data.traps += 1
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

func find_steps(node):
	if node is ForEveryStepEffectBehavior:
		return node
	for child in node.get_children():
		var found = find_steps(child)
		if found != null:
			return found
	return null
