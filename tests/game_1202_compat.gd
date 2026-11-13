extends Node

var checks = 0
var failures = 0
var host
var client
var main
var rows = []

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	DebugService.disable_saving = true
	get_tree().create_timer(90).connect("timeout", self, "_timeout")
	call_deferred("_run")

func _timeout():
	printerr("GAME_1202_FAIL: watchdog")
	get_tree().quit(2)

func check(ok, label):
	checks += 1
	if not ok:
		failures += 1
	rows.append({"passed": bool(ok), "label": label})
	print("GAME_1202_", "PASS: " if ok else "FAIL: ", label)

func _state(index):
	var p = RunData.players_data[index]
	var items = []
	for item in p.items:
		items.append({"id": item.my_id, "mutant": item.is_mutant, "effects": item.get_effects_text(index)})
	var weapons = []
	for weapon in p.weapons:
		weapons.append(weapon.serialize())
	return JSON.print({"items": items, "weapons": weapons, "effects": p.serialize().effects, "gold": p.gold, "pending": p.pending_mutations}, "", true)

func _pickup_case(label, effects, caps, full, expected):
	var player = main._players[0]
	var data = ItemService.get_dlc_data_by_id("primal_dread").meca_fruit
	var results = []
	for native in [true, false]:
		RunData.get_player_effects(0)[Keys.consumable_stats_while_max_hash] = effects.duplicate(true)
		RunData.max_consumable_stats_gained_this_wave[0] = caps.duplicate(true)
		var hp = RunData.get_player_effect(Keys.stat_max_hp_hash, 0)
		var damage = RunData.get_player_effect(Keys.stat_percent_damage_hash, 0)
		var tracked = RunData.tracked_item_effects[0].get(Keys.item_extra_stomach_hash, 0)
		if native:
			player.current_stats.health = player.max_stats.health if full else player.max_stats.health - 1
			player.on_consumable_picked_up(data)
		else:
			main._bo_apply_remote_reward("meca_consumable_fruit", 0, full)
		results.append([RunData.get_player_effect(Keys.stat_max_hp_hash, 0) - hp, RunData.get_player_effect(Keys.stat_percent_damage_hash, 0) - damage, RunData.tracked_item_effects[0].get(Keys.item_extra_stomach_hash, 0) - tracked, RunData.max_consumable_stats_gained_this_wave[0].duplicate(true)])
	check(results[0].slice(0, 2) == expected, label + ": native expected gain/tracking")
	check(results[0] == results[1], label + ": remote equals native including wave counters")

func _crate(data, label, host_seed, client_seed):
	var reward = UpgradesUI.ConsumableToProcess.new()
	reward.player_index = 0
	reward.consumable_data = load("res://items/consumables/item_box/item_box_data.tres")
	seed(host_seed)
	main._coop_upgrades_ui.emit_signal("item_take_button_pressed", data, reward)
	var message = host.messages.back().duplicate(true)
	message.player_index = 1
	# Both endpoints have identical starting inventory but deliberately different RNG.
	seed(client_seed)
	var expected_rng = randf()
	seed(client_seed)
	var applied = client._apply_item_box_item_added(1, message)
	check(applied, label + ": production receiver accepted host callback message")
	check(randf() == expected_rng, label + ": receiver consumes no random numbers")
	check(_state(0) == _state(1), label + ": final inventory, effects, evolution and gold agree")
	check(RunData.players_data[0].recently_mutated.size() == RunData.players_data[1].recently_mutated.size(), label + ": recent mutation markers restored")
	check(RunData.max_consumable_stats_gained_this_wave[0] == RunData.max_consumable_stats_gained_this_wave[1], label + ": mutation-adjusted wave caps restored")
	var before = _state(1)
	client.receive_run_page_action_sync("host", message, "client")
	client.receive_run_page_action_sync("host", message, "client")
	check(_state(1) == before, label + ": duplicate deliveries do not add or mutate twice")
	return message

func _run():
	ProgressData.apply_settings()
	ProgressData.settings.pause_on_focus_lost = false
	RunData.reset()
	RunData.set_player_count(2, true)
	RunData.set_coop_run(true)
	CoopService.connected_players = [[7, 0], [0, 1]]
	if not ProgressData.active_update_data.has("primal_dread"):
		ProgressData.active_update_data.append("primal_dread")
	if not RunData.enabled_dlcs.has("primal_dread"):
		RunData.enabled_dlcs.append("primal_dread")
	RunData.active_update_data_ids = ProgressData.active_update_data.duplicate()
	for i in 2:
		RunData.add_character(load("res://items/characters/well_rounded/well_rounded_data.tres"), i)
		RunData.add_weapon(load("res://weapons/ranged/pistol/1/pistol_data.tres"), i, true)
	RunData.current_wave = 1
	ZoneService.set_current_zone(ZoneService.get_zone_data(RunData.current_zone).duplicate())
	ItemService.init_unlocked_pool()
	DebugService.no_enemies = true
	RunData.invulnerable = true
	get_tree().current_scene = null
	get_tree().change_scene("res://main.tscn")
	for _i in 30:
		yield(get_tree(), "idle_frame")
	main = get_tree().current_scene
	var protocol = load("res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/scripts/protocol.gd")
	check(protocol.is_compatible("6.5.4", ProgressData.VERSION), "new authoritative crate protocol accepts current peer")
	check(not protocol.is_compatible("6.5.3", ProgressData.VERSION), "old rerolling peer is rejected at handshake")
	host = load("res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/tests/game_1202_compat_manager.gd").new()
	client = load("res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/tests/game_1202_compat_manager.gd").new()
	host.test_host = true
	add_child(host)
	add_child(client)
	host.set_process(false)
	client.set_process(false)
	host._ensure_host_item_box_take_sync_connection(main._coop_upgrades_ui)
	var hp = Keys.stat_max_hp_hash
	var damage = Keys.stat_percent_damage_hash
	_pickup_case("one remaining", [[hp, 2, 10]], [[hp, 2, 9]], true, [1, 0, 1])
	_pickup_case("already capped", [[hp, 2, 10]], [[hp, 2, 10]], true, [0, 0, 0])
	_pickup_case("exact remaining", [[hp, 2, 10]], [[hp, 2, 8]], true, [2, 0, 2])
	_pickup_case("uncapped", [[hp, 2]], [], true, [2, 0, 2])
	_pickup_case("not full health", [[hp, 2, 10]], [[hp, 2, 9]], false, [0, 0, 0])
	_pickup_case("independent effects", [[hp, 2, 10], [damage, 3, 5], [hp, 2]], [[hp, 2, 9], [damage, 3, 3]], true, [3, 2, 3])
	# Start crate checks from identical state; pickup checks intentionally changed seat 0.
	client._apply_one_serialized_player_run_data(1, host._serialize_player_run_data_for_shop_sync(0, "compact"), false)
	for i in 2:
		RunData.get_player_effects(i)[Keys.stat_evolution_hash] = -10
		RunData.get_player_effects(i)[Keys.mutate_item_on_equip_chance_hash] = 25
	var cake = load("res://items/all/00_base_game/cake/cake_data.tres")
	var first = _crate(cake, "host mutation/client losing seed", 0, 1)
	check(RunData.get_player_effect(Keys.stat_evolution_hash, 0) == -11, "host mutation actually occurred")
	_crate(cake, "host no mutation/client winning seed", 1, 0)
	check(RunData.get_player_effect(Keys.stat_evolution_hash, 0) == -11, "host no-mutation result is retained")
	_crate(cake, "second mutation updates existing tumor", 0, 1)
	check(RunData.get_player_effect(Keys.stat_evolution_hash, 1) == -12, "tumor growth changes evolution exactly once")
	var before = _state(1)
	check(not client._apply_item_box_item_added(1, first) and _state(1) == before, "older crate snapshot cannot roll back newer reward")
	check(not client._apply_item_box_item_added(1, {"item": client._serialize_item_parent_data(cake)}) and _state(1) == before, "legacy packet cannot re-run random equip")
	var pistol = load("res://weapons/ranged/pistol/1/pistol_data.tres")
	_crate(pistol, "weapon reward with free slot", 0, 1)
	for i in 2:
		while RunData.get_player_weapons(i).size() < 6:
			RunData.add_weapon(pistol, i)
	RunData.is_endless_run = true
	RunData.current_wave = 21
	_crate(pistol, "weapon reward combines when inventory is full", 0, 1)
	var transition = host._build_shop_run_data_sync_state(0, true, "incremental_only")
	check(not transition.run_data.get("items_incremental_only", false) and not transition.run_data.items.empty(), "endless shop transition carries complete inventory if it overtakes crate packet")
	check(RunData.get_player_weapons(1).size() == 6, "weapon reward respects slot limit")
	var found_tier_two = false
	for weapon in RunData.get_player_weapons(1):
		found_tier_two = found_tier_two or weapon.tier == 1
	check(found_tier_two, "combined weapon is present on client")
	before = _state(1)
	RunData.current_wave += 1
	check(not client._apply_item_box_item_added(1, first) and _state(1) == before, "previous-wave reward is rejected")
	check(not client._apply_item_box_item_added(-1, first), "invalid player rejected")
	var file = File.new()
	file.open(OS.get_environment("BROTATO_TEST_DIR").plus_file("checks.json"), File.WRITE)
	file.store_string(JSON.print(rows, "  "))
	file.close()
	print("GAME_1202_RESULT: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
