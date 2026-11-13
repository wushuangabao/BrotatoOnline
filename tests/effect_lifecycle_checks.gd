extends Reference
const FLAME = "res://weapons/melee/wrench/2/wrench_2_data.tres"
const SHELL = "res://dlcs/dlc_1/items/seashell/seashell_data.tres"
const JAVELIN = "res://dlcs/dlc_1/weapons/ranged/javelin/1/javelin_data.tres"
const BUILDER = "res://dlcs/dlc_1/characters/builder/builder_data.tres"
var checks = []
func check(ok, label, detail = null):
    checks.append({"passed":bool(ok), "name":label, "detail":detail})
func restore(runtime_sync, source, target):
    var state = JSON.parse(JSON.print(runtime_sync.serialize_item_effect_state(source))).result
    runtime_sync.apply_item_effect_state(target, state)
    return target
func run(manager):
    checks = []
    var protocol = load("res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/scripts/protocol.gd")
    check(protocol.is_compatible("6.5.4", ProgressData.VERSION), "replacement protocol accepts current peers")
    check(not protocol.is_compatible("6.5.3", ProgressData.VERSION), "replacement protocol rejects superseded 6.8.4 peers")
    var runtime_sync = manager._get_upgrade_runtime_sync()
    for rendered in [false, true]:
        var source = load(FLAME).duplicate()
        source.effects = [source.effects[0].duplicate()]
        source.effects[0].custom_args = []
        source.effects[0]._custom_args_added = false
        if rendered:
            source.effects[0].get_text(0)
        var template_before = JSON.print(load(FLAME).effects[0].serialize(), "", true)
        var first = restore(runtime_sync, source, load(FLAME).duplicate())
        check(first.effects[0]._custom_args_added == rendered and first.effects[0].custom_args.size() == int(rendered), "restore exact description initialization " + str(rendered))
        var expected_text = first.effects[0].get_text(0)
        var expected_size = JSON.print(runtime_sync.serialize_item_effect_state(first)).length()
        var stable = true
        for _i in 25:
            first = restore(runtime_sync, first, load(FLAME).duplicate())
            stable = stable and first.effects[0].get_text(0) == expected_text
            stable = stable and first.effects[0].custom_args.size() == 1
            stable = stable and JSON.print(runtime_sync.serialize_item_effect_state(first)).length() == expected_size
        check(stable, "25 rendered roundtrips keep text, args and payload stable " + str(rendered), expected_size)
        check(JSON.print(load(FLAME).effects[0].serialize(), "", true) == template_before, "flame template unchanged " + str(rendered))
    for path in [SHELL, JAVELIN, BUILDER]:
        var source = load(path).duplicate()
        var before = JSON.print(load(path).serialize(), "", true)
        var native = JSON.print(source.serialize(), "", true)
        var ok = true
        for _i in 10:
            source = restore(runtime_sync, source, load(path).duplicate())
            ok = ok and JSON.print(source.serialize(), "", true) == native
        check(ok, "native subclass roundtrip preserves all values " + path)
        check(JSON.print(load(path).serialize(), "", true) == before, "shared template remains unchanged " + path)
    for count in [0, 1, 2]:
        var source = load(SHELL).duplicate()
        source.effects = [source.effects[0].duplicate()]
        source.effects[0].sub_effects = []
        for i in count:
            var child = Effect.new()
            child.key = "projectiles"
            child._generate_hashes()
            child.value = i + 1
            source.effects[0].sub_effects.append(child)
        var native = JSON.print(source.serialize(), "", true)
        for _i in 10:
            source = restore(runtime_sync, source, load(SHELL).duplicate())
        check(source.effects[0].sub_effects.size() == count and JSON.print(source.serialize(), "", true) == native, "zero/single/multiple subeffects replace instead of append " + str(count))
    var source = load(SHELL)
    var shared = source.duplicate()
    var before = JSON.print(shared.serialize(), "", true)
    restore(runtime_sync, source, source.duplicate())
    check(JSON.print(shared.serialize(), "", true) == before, "restoring one owner does not mutate another shared-source item")
    var old_state = runtime_sync.serialize_item_effect_state(load(FLAME))
    old_state[0].erase("custom_args_added")
    var legacy = load(FLAME).duplicate()
    runtime_sync.apply_item_effect_state(legacy, JSON.parse(JSON.print(old_state)).result)
    check(legacy.effects[0].get_text(0) != "", "legacy metadata without initialization flag remains readable")
    old_state = runtime_sync.serialize_item_effect_state(load(SHELL))
    for entry in old_state:
        entry.erase("serialized_effect")
        entry.erase("custom_args_added")
    legacy = load(SHELL).duplicate()
    runtime_sync.apply_item_effect_state(legacy, JSON.parse(JSON.print(old_state)).result)
    check(legacy.effects[0].sub_effects.size() == 1, "properties-only legacy data retains template subeffects")
    var old_registry = RunData.players_data[0].effects[Keys.modify_every_x_projectile_hash]
    RunData.players_data[0].effects[Keys.modify_every_x_projectile_hash] = []
    var shell = restore(runtime_sync, load(SHELL), load(SHELL).duplicate())
    var effect = shell.effects[0]
    var projectiles_before = RunData.get_player_effect(Keys.projectiles_hash, 0)
    effect.apply(0)
    var args = WeaponServiceInitStatsArgs.new()
    var stats = WeaponService.init_stats_every_x_projectiles(load("res://weapons/ranged/pistol/1/pistol_stats.tres"), 0, args)
    check(stats[effect.value].nb_projectiles == 4, "native seashell special shot has four projectiles", stats[effect.value].nb_projectiles)
    check(RunData.get_player_effect(Keys.projectiles_hash, 0) == projectiles_before, "native projectile calculation restores temporary attributes")
    effect.unapply(0)
    check(RunData.get_player_effect(Keys.modify_every_x_projectile_hash, 0).empty(), "restored seashell unapply removes its registered reference")
    var javelin = restore(runtime_sync, load(JAVELIN), load(JAVELIN).duplicate())
    args.effects = javelin.effects
    stats = WeaponService.init_stats_every_x_projectiles(javelin.stats, 0, args)
    var expected = WeaponService.init_stats_every_x_projectiles(load(JAVELIN).stats, 0, _javelin_args())
    check(stats[5].crit_chance == expected[5].crit_chance and stats[5].crit_chance == 1.0, "native javelin special-shot crit remains 100 percent", stats[5].crit_chance)
    RunData.players_data[0].effects[Keys.modify_every_x_projectile_hash] = old_registry
    # Exercise native conversion, preserving the pre-check lobby state.
    var old_total = RunData.total_bonus_gold
    var old_bonus = RunData.bonus_gold
    var old_tracking = RunData.tracked_item_effects.duplicate(true)
    var old_converters = []
    for player in RunData.players_data:
        old_converters.append(player.effects[Keys.convert_bonus_gold_hash])
        player.effects[Keys.convert_bonus_gold_hash] = []
    var builder = restore(runtime_sync, load(BUILDER), load(BUILDER).duplicate())
    for _i in 10:
        builder = restore(runtime_sync, builder, load(BUILDER).duplicate())
    for conversion in builder.effects:
        if conversion.key_hash != Keys.convert_bonus_gold_hash:
            continue
        var before_values = []
        for child in conversion.sub_effects:
            before_values.append(RunData.get_player_effect(child.key_hash, 0))
        RunData.tracked_item_effects[0][Keys.character_builder_hash] = [0, 0]
        RunData.total_bonus_gold = 0
        conversion.apply(0)
        RunData.add_bonus_gold(conversion.value * RunData.get_player_count())
        var correct = conversion.sub_effects.size() == 2
        for i in conversion.sub_effects.size():
            var child = conversion.sub_effects[i]
            correct = correct and RunData.get_player_effect(child.key_hash, 0) == before_values[i] + 1
            RunData.players_data[0].effects[child.key_hash] = before_values[i]
        check(correct, "native builder conversion adds each of two attributes once")
        check(RunData.tracked_item_effects[0][Keys.character_builder_hash][1] == 2, "native builder conversion tracks exactly two stat gains")
        conversion.unapply(0)
        check(RunData.get_player_effect(Keys.convert_bonus_gold_hash, 0).empty(), "restored builder conversion unregisters cleanly")
    for i in RunData.players_data.size():
        RunData.players_data[i].effects[Keys.convert_bonus_gold_hash] = old_converters[i]
    RunData.total_bonus_gold = old_total
    RunData.bonus_gold = old_bonus
    RunData.tracked_item_effects = old_tracking
    Utils.reset_stat_cache(0)
    return checks
func _javelin_args():
    var args = WeaponServiceInitStatsArgs.new()
    args.effects = load(JAVELIN).effects
    return args
func fixture(probe):
    var layout = CoopService.connected_players.duplicate(true)
    RunData.reset()
    RunData.set_player_count(2, true)
    RunData.set_coop_run(true)
    CoopService.connected_players = layout
    for i in 2:
        RunData.add_character(load("res://items/characters/well_rounded/well_rounded_data.tres"), i)
        RunData.add_weapon(load(FLAME), i)
        RunData.add_weapon(load("res://weapons/ranged/pistol/1/pistol_data.tres"), i)
        var shell = load("res://dlcs/dlc_1/dlc_1_data.gd").new().curse_item(load(SHELL), i, true, 0.4)
        RunData.add_item(shell, i)
        RunData.players_data[i].gold = 1000
    RunData.current_wave = int(OS.get_environment("BROTATO_TEST_WAVE"))
    RunData.is_endless_run = RunData.current_wave >= 20
    ProgressData.settings.endless_mode_toggled = RunData.is_endless_run
    RunData.invulnerable = true
    ZoneService.set_current_zone(ZoneService.get_zone_data(RunData.current_zone).duplicate())
    ItemService.init_unlocked_pool()
    probe.get_tree().change_scene("res://ui/menus/shop/coop_shop.tscn")
func snapshot(index):
    var d = {"flame_args":[], "shell_counts":[], "shell_bound":true, "shell_cursed":false, "special_shots":{}}
    for weapon in RunData.get_player_weapons_ref(index):
        if weapon.my_id == "weapon_wrench_2":
            d.flame_args.append(weapon.effects[0].custom_args.size())
    for item in RunData.get_player_items_ref(index):
        if item.my_id == "item_seashell":
            d.shell_cursed = item.is_cursed
            for effect in item.effects:
                if effect is EffectWithSubEffects:
                    d.shell_counts.append(effect.sub_effects.size())
                    d.shell_bound = d.shell_bound and RunData.get_player_effect(Keys.modify_every_x_projectile_hash, index).has(effect)
    var args = WeaponServiceInitStatsArgs.new()
    var stats = WeaponService.init_stats_every_x_projectiles(load("res://weapons/ranged/pistol/1/pistol_stats.tres"), index, args)
    for interval in stats:
        d.special_shots[str(interval)] = stats[interval].nb_projectiles
    d.projectiles = RunData.get_player_effect(Keys.projectiles_hash, index)
    return d
