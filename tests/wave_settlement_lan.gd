extends "res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/tests/meca_upgrade_lan.gd"

var mode = OS.get_environment("BROTATO_SETTLEMENT_MODE")
var current_main = null
var delayed_timer = null
var delayed = false
var released = false
var wave_callbacks = 0
var start_steps = 0
var diagnostic_at = 0
var native_duplicates_checked = false
var box_seeded = false
var upgrade_seeded = false
var box_taken = false
var upgrade_taken = false
var starting_max_hp = 0
var crate_native_calls = 0

func _drive_rewards():
	if not mode in ["rewards", "compat"] or not is_instance_valid(current_main):
		return
	var ui = current_main._coop_upgrades_ui
	if not ui.visible:
		return
	var container = ui._get_player_container(1)
	if role == "host":
		# Controlled reward data, while keeping native queues, choice callbacks and
		# transport intact. The client waits until this exact offer is published.
		if container._items_container.visible and not box_seeded:
			container.show_item(load("res://items/all/00_base_game/cake/cake_data.tres"))
			box_seeded = true
		if container._upgrades_container.visible and not upgrade_seeded:
			container._upgrade_ui_1.set_upgrade(load("res://items/upgrades/range/1/range_data.tres"), 1)
			upgrade_seeded = true
	else:
		if container._items_container.visible and container._item_data != null and container._item_data.my_id == "item_cake" and not box_taken and not container._take_button.disabled and container._take_button.is_connected("pressed", menu, "_on_client_item_box_take_pressed"):
			box_taken = true
			container._take_button.emit_signal("pressed")
		if container._upgrades_container.visible and container._upgrade_ui_1.upgrade_data != null and container._upgrade_ui_1.upgrade_data.upgrade_id_hash == load("res://items/upgrades/range/1/range_data.tres").upgrade_id_hash and not upgrade_taken and not container._upgrade_ui_1.button.disabled and container._upgrade_ui_1.is_connected("choose_button_pressed", menu, "_on_client_upgrade_choose_button_pressed"):
			upgrade_taken = true
			container._upgrade_ui_1.button.emit_signal("pressed")

func _read(name: String):
	var file = File.new()
	file.open(folder.plus_file(name), File.READ)
	var value = JSON.parse(file.get_as_text()).result
	file.close()
	return value

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	DebugService.disable_saving = true
	DebugService.no_enemies = true
	ModLoaderMod.install_script_extension("res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/tests/wave_settlement_delay_main.gd")
	# Godot invokes the inherited _ready too; the base schedules _run once.

func _check(ok: bool, label: String):
	print("WAVE_SETTLEMENT_", "PASS" if ok else "FAIL", ": ", role, " ", label)
	if not ok:
		failures += 1

func _on_wave():
	wave_callbacks += 1

func _verify_native_duplicates():
	if native_duplicates_checked or not current_main.get_meta("bo_wave_run_data_settled", false) or not bool(current_main.get("_bo_harvesting_applied")):
		return
	native_duplicates_checked = true
	var before = JSON.print(_state())
	var steps = int(ProgressData.data.steps_taken)
	current_main._on_WaveTimer_timeout()
	current_main._on_EndWaveTimer_timeout()
	current_main._on_HarvestingTimer_timeout()
	_check(before == JSON.print(_state()) and steps == int(ProgressData.data.steps_taken) and wave_callbacks == 1, "duplicate native callbacks cannot repeat rewards or side effects")

func _process(_delta):
	_drive_rewards()
	if session != null and OS.get_ticks_msec() > diagnostic_at:
		diagnostic_at = OS.get_ticks_msec() + 1000
		var scene = get_tree().current_scene
		_write(role + "-status.json", {"scene": scene.filename if is_instance_valid(scene) else "", "pending": session._pending_host_game_start, "wave": RunData.current_wave, "callbacks": wave_callbacks, "box_seeded": box_seeded, "upgrade_seeded": upgrade_seeded, "box_taken": box_taken, "upgrade_taken": upgrade_taken})
	if role != "client" or not is_instance_valid(current_main) or released:
		return
	if mode == "wave":
		delayed = true
		return
	if not delayed and current_main._cleaning_up:
		# Reward choices require the native EndWaveTimer to open their UI. Delay
		# harvesting instead, so the host can legitimately finish those choices.
		delayed_timer = current_main._harvesting_timer if mode in ["harvest", "rewards", "compat"] else current_main._end_wave_timer
		delayed_timer.paused = true
		delayed = true
		_write("delayed.json", {})

func _host_mutation_state(index = 0):
	var dlc = ItemService.get_dlc_data_by_id("primal_dread")
	var result = {"pending": RunData.players_data[index].pending_mutations, "evolution": RunData.get_player_effect(Keys.stat_evolution_hash, index), "tumors": 0, "count_effects": 0, "mutation_count": 0, "lens": 0, "character": 0, "items": []}
	for item in RunData.players_data[index].items:
		if item.my_id == "item_lens": result.lens += 1
		if item.my_id == "character_well_rounded": result.character += 1
		var effects = []
		for effect in item.effects:
			effects.append(JSON.print(effect.serialize(), "", true))
			if dlc.is_tumor(item) and effect.text_key == DLC2Data.TUMOR_MUTATION_COUNT_TEXT_KEY:
				result.count_effects += 1
				result.mutation_count += effect.value
		effects.sort()
		result.items.append(JSON.print({"id": item.my_id, "mutant": item.is_mutant, "effects": effects}, "", true))
		if dlc.is_tumor(item): result.tumors += 1
	result.items.sort()
	return result

func _state():
	var p = RunData.players_data[1]
	var ids = []
	for item in p.items:
		ids.append(item.my_id + (":mutant" if item.is_mutant else ""))
	ids.sort()
	var mutants = 0
	for item in RunData.players_data[0].items:
		# Characters are legitimate mutation targets too. Exclude the incidental
		# tumor created by some mutant effects, not the chosen character.
		if item.is_mutant and item.my_id in ["item_lens", "character_well_rounded"]:
			mutants += 1
	return {"gold": p.gold, "xp": p.current_xp, "level": p.current_level, "armor": RunData.get_player_effect(Keys.stat_armor_hash, 1), "range": RunData.get_player_effect(Keys.stat_range_hash, 1), "max_hp": RunData.get_player_max_health(1), "harvest": RunData.get_player_effect(Keys.stat_harvesting_hash, 1), "items": ids, "mutants": mutants, "host_mutation": _host_mutation_state(), "crate_mutation": _host_mutation_state(1), "bonus": RunData.bonus_gold, "total_bonus": RunData.total_bonus_gold, "pending_mutations": p.pending_mutations}

func _run():
	ProgressData.apply_settings()
	ProgressData.settings.pause_on_focus_lost = false
	session = get_tree().root.find_node("BrotatoOnlineSessionManager", true, false)
	menu = get_tree().root.find_node("BrotatoOnlineMenuSyncManager", true, false)
	get_tree().current_scene = null
	get_tree().change_scene(MenuData.character_selection_scene if role == "host" else MenuData.title_screen_scene)
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
			RunData.add_weapon(load("res://weapons/ranged/pistol/1/pistol_data.tres"), index, true)
			RunData.players_data[index].gold = 1000
			RunData.players_data[index].current_level = 10
		RunData.add_item(load("res://items/all/04_primal_dread/dino_egg/dino_egg.tres"), 1)
		RunData.add_item(load("res://items/all/00_base_game/lens/lens_data.tres"), 0)
		RunData.add_stat(Keys.stat_evolution_hash, -10, 0)
		RunData.players_data[0].pending_mutations = 1
		if mode in ["rewards", "compat"]:
			RunData.players_data[1].current_level = 1
			RunData.players_data[1].current_xp = 24
		if mode == "compat":
			RunData.add_stat(Keys.stat_evolution_hash, -10, 1)
			RunData.get_player_effects(1)[Keys.mutate_item_on_equip_chance_hash] = 25
		RunData.add_stat(Keys.stat_harvesting_hash, 20 - RunData.get_player_effect(Keys.stat_harvesting_hash, 1), 1)
		RunData.get_player_effects(1)[Keys.stats_end_of_wave_hash] = [[Keys.stat_armor_hash, 7]]
		RunData.current_wave = 2
		if mode == "endless":
			RunData.is_endless_run = true
			RunData.current_wave = 21
			load("res://items/characters/demon/demon_effect_1.tres").apply(1)
		ZoneService.set_current_zone(ZoneService.get_zone_data(RunData.current_zone).duplicate())
		ItemService.init_unlocked_pool()
		get_tree().change_scene("res://ui/menus/shop/coop_shop.tscn")
	else:
		while get_tree().current_scene == null or not get_tree().current_scene.has_method("_get_shop_items_container"):
			yield(get_tree().create_timer(0.1), "timeout")
		while not menu._get_trusted_shop_sync().owns(1):
			yield(get_tree().create_timer(0.1), "timeout")
		_write("shop-ready.json", {})
	if role == "host":
		yield(_wait_file("shop-ready.json"), "completed")
		while not get_tree().current_scene._get_go_button(0).is_connected("pressed", menu, "_on_host_shop_go_pressed"):
			yield(get_tree().create_timer(0.1), "timeout")
		session.request_synced_shop_game_start(get_tree().current_scene, 0)
	while get_tree().current_scene == null or str(get_tree().current_scene.filename) != "res://main.tscn":
		yield(get_tree().create_timer(0.1), "timeout")
	current_main = get_tree().current_scene
	current_main.connect("end_of_the_wave", self, "_on_wave")
	start_steps = int(ProgressData.data.steps_taken)
	starting_max_hp = RunData.get_player_max_health(1)
	RunData.steps_taken_this_wave = [11, 37, 0, 0]
	if role == "host":
		if mode in ["rewards", "compat"]:
			var reward = UpgradesUI.ConsumableToProcess.new()
			reward.consumable_data = load("res://items/consumables/item_box/item_box_data.tres")
			reward.player_index = 1
			current_main._consumables_to_process[1].append(reward)
		# Controlled leftover-material ledger; not a pickup claim test.
		RunData.add_bonus_gold(13, false)
		_write("host-before.json", _state())
		_write("battle-ready-host.json", {})
		yield(_wait_file("battle-ready-client.json"), "completed")
		current_main._wave_timer.start(10)
	else:
		_write("battle-ready-client.json", _state())
	if role == "host":
		while get_tree().current_scene == current_main:
			yield(get_tree().create_timer(0.1), "timeout")
		# Deliver a full authoritative shop transition over real ENet while the
		# other peer is intentionally behind. This also exercises late resends.
		yield(get_tree().create_timer(0.5), "timeout")
		session.broadcast_message(menu.build_menu_scene_state(true, true, true))
		_write("host-shop.json", _state())
		_check(wave_callbacks == 1, "native end_of_the_wave callback once")
		_check(int(ProgressData.data.steps_taken) - start_steps == 37, "native step accounting exactly once")
		_check(RunData.get_player_gold(1) == (526 if mode == "endless" else 1020), "material conversion precedes exactly 20 harvesting materials")
		_check(RunData.players_data[1].current_xp == (19 if mode in ["rewards", "compat"] else 20), "harvesting grants exactly 20 XP with correct level rollover")
		_check(RunData.get_player_effect(Keys.stat_armor_hash, 1) == 7, "wave-end armor grants exactly seven")
		_check(RunData.get_player_effect(Keys.stat_harvesting_hash, 1) == (16 if mode == "endless" else 21), "harvesting growth or endless decay occurs exactly once")
		if mode == "endless":
			_check(RunData.get_player_max_health(1) == starting_max_hp + 38, "native demon conversion adds exactly 38 maximum HP")
		_check(_state().items.has(load("res://items/all/04_primal_dread/dino_egg/dino_egg.tres").replaced_by.my_id), "dinosaur egg advances exactly one stage")
		var mutation = _state().host_mutation
		_check(mutation.pending == 0 and mutation.tumors == 1 and mutation.count_effects == 1 and mutation.mutation_count == 1 and mutation.evolution == -11 and mutation.lens == 1 and mutation.character == 1, "one pending mutation creates exactly one tumor mutation, consumes one evolution and preserves target inventory")
		if mode in ["rewards", "compat"]:
			_check(RunData.players_data[1].current_level == 2 and RunData.get_player_effect(Keys.stat_range_hash, 1) == 15, "one earned upgrade applies exactly once")
			_check(_state().items.count("item_cake") + _state().items.count("item_cake:mutant") == 1, "one item box grants exactly one chosen item")
		if mode == "compat":
			var crate = _host_mutation_state(1)
			_check(crate.tumors == 1 and crate.mutation_count == 1 and crate.evolution == -11, "crate equip mutation creates one authoritative tumor and evolution loss")
			_check(crate_native_calls == 1, "host executes native crate reward exactly once")
		yield(_wait_file("client-result.json"), "completed")
	else:
		yield(_wait_file("host-shop.json"), "completed")
		yield(get_tree().create_timer(1), "timeout")
		_check(delayed, "client native settlement timer deliberately delayed")
		_check(is_instance_valid(current_main) and get_tree().current_scene == current_main, "host shop waits for local settlement callbacks")
		released = true
		if is_instance_valid(current_main):
			current_main.set_meta("test_release_wave", true)
		if is_instance_valid(delayed_timer):
			delayed_timer.paused = false
		while get_tree().current_scene == current_main:
			yield(get_tree().create_timer(0.1), "timeout")
		var expected = _read("host-shop.json")
		_check(JSON.print(_state()) == JSON.print(expected), "all personal rewards and bonus material ledger equal host")
		_check(int(ProgressData.data.steps_taken) - start_steps == 37, "client native step accounting exactly once")
		_check(RunData.steps_taken_this_wave == [0, 0, 0, 0] and not RunData.wave_in_progress, "per-wave counters reset before shop")
		_check(wave_callbacks == 1, "client end_of_the_wave callback once")
		_check(native_duplicates_checked, "native duplicate-callback injection was exercised")
		var before = JSON.print(_state())
		var state = menu._last_menu_scene_state_from_host.duplicate(true)
		for _i in 3:
			menu.receive_menu_scene_state_from_host(state)
		yield(get_tree().create_timer(0.5), "timeout")
		_check(before == JSON.print(_state()) and int(ProgressData.data.steps_taken) - start_steps == 37 and wave_callbacks == 1, "duplicate shop messages cannot repeat settlement")
		if mode == "compat":
			_check(crate_native_calls == 0, "client never replays native crate RNG after real LAN delivery")
		_write("client-result.json", _state())
	print("WAVE_SETTLEMENT_RESULT: ", role, " ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
