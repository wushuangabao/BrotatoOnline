extends Node

const Catalog = preload("res://mods-unpacked/wushuangabao-NoobsWantToLive/catalog.gd")
var checks = 0
var failures = 0
var roster = []
var scene

func _ready():
	if OS.get_environment("BROTATO_TEST_DIR") == "":
		return
	DebugService.disable_saving = true
	get_tree().create_timer(90).connect("timeout", self, "_timeout")
	call_deferred("_run")

func check(ok, message):
	checks += 1
	if not ok:
		failures += 1
		printerr("NWTL_FAIL: " + message)
	else:
		print("NWTL_PASS: " + message)

func settle(count = 8):
	for _i in count:
		yield(get_tree(), "idle_frame")

func shot(name):
	var image = get_viewport().get_texture().get_data()
	image.flip_y()
	check(image.save_png(OS.get_environment("BROTATO_TEST_DIR").plus_file(name + ".png")) == OK, "screenshot " + name)

func _setup_run(characters):
	RunData.reset()
	RunData.set_player_count(characters.size(), true)
	RunData.set_coop_run(characters.size() > 1)
	CoopService.connected_players.clear()
	for i in characters.size():
		CoopService.connected_players.append([7 if i == 0 else i - 1, 0 if i == 0 else 1])
		RunData.add_character(characters[i], i)
		if not characters[i].starting_weapons.empty():
			RunData.add_weapon(characters[i].starting_weapons[0], i, true)
	RunData.current_wave = 1
	ZoneService.set_current_zone(ZoneService.get_zone_data(RunData.current_zone).duplicate())
	ItemService.init_unlocked_pool()
	DebugService.no_enemies = true
	RunData.invulnerable = true

func _run():
	print("NWTL_USER_DATA: " + OS.get_user_data_dir())
	TranslationServer.set_locale("zh")
	for character in ItemService.characters:
		if character.my_id.begins_with(Catalog.PREFIX):
			roster.append(character)
	check(roster.size() == 11, "11 new characters registered")
	if roster.size() != 11:
		_finish()
		return
	var hashes = {}
	for character in roster:
		check(not hashes.has(character.my_id_hash), character.my_id + " unique ID")
		hashes[character.my_id_hash] = true
		check(ProgressData.characters_unlocked.has(character.my_id_hash), character.my_id + " unlocked")
		check(character.icon.get_width() == 96 and tr(character.name) != character.name, character.my_id + " icon and localized name")
		check(ProgressData.get_character_difficulty_info(character.my_id_hash, RunData.current_zone) != null, character.my_id + " difficulty progress")
		for weapon in character.starting_weapons:
			check(weapon != null, character.my_id + " starting weapon")
	var total = ItemService.characters.size()
	ItemService.invalidate_characters_cache()
	check(ItemService.characters.size() == total, "rebuilding catalog does not duplicate characters")
	_setup_run([roster[0]])
	get_tree().change_scene("res://ui/menus/run/character_selection.tscn")
	yield(settle(20), "completed")
	scene = get_tree().current_scene
	var seen = 0
	for entry in scene.displayed_elements[0]:
		if entry.my_id.begins_with(Catalog.PREFIX):
			seen += 1
			check(not entry.is_locked, "selectable " + entry.my_id)
	check(seen == 11, "all new characters visible in native selection")
	Utils.focus_player_control(scene._find_inventory_element_by_id(roster[-1].my_id_hash, 0), 0)
	yield(settle(8), "completed")
	check(not scene._get_panels()[0].get_node("%Character/Legs").visible, "selection preview hides potato legs")
	shot("character-selection")
	for batch in 3:
		var selected = []
		for index in range(batch * 4, min(batch * 4 + 4, roster.size())):
			selected.append(roster[index])
		if batch == 2:
			selected.append(load("res://items/characters/well_rounded/well_rounded_data.tres"))
		_setup_run(selected)
		get_tree().change_scene("res://main.tscn")
		yield(settle(40), "completed")
		scene = get_tree().current_scene
		# Wait for the actual parachute/landing animation, not a frame-count guess.
		for _wait in 100:
			if scene._players.size() == selected.size() and scene._players[0]._animation_player.current_animation != scene._players[0].animation_landing:
				break
			yield(get_tree().create_timer(0.05), "timeout")
		check(scene._players.size() == selected.size(), "real combat spawned batch " + str(batch))
		for i in scene._players.size():
			var player = scene._players[i]
			player.position = Vector2(650 + i * 150, 500)
			if not selected[i].my_id.begins_with(Catalog.PREFIX):
				check(not player.has_node("NoobsAnimation") and player._legs.visible, "vanilla character untouched")
				continue
			check(player.has_node("NoobsAnimation"), selected[i].my_id + " animated actor attached")
			if not player.has_node("NoobsAnimation"):
				continue
			var actor = player.get_node("NoobsAnimation")
			check(player.sprite.flip_h, "Unity left-facing art corrected for Brotato " + selected[i].my_id)
			check(actor.clips.size() == 5 and not player._legs.visible, selected[i].my_id + " five animation states and hidden potato legs")
			check(player.current_weapons.size() == (0 if selected[i].starting_weapons.empty() else 1), selected[i].my_id + " correct weapon count")
			for state in actor.clips:
				check(actor.clips[state].frames.size() >= 2, selected[i].my_id + " decoded " + state)
			player._move_locked = true
			player._current_movement = Vector2.RIGHT
			var restored = PlayerRunData.new().deserialize(JSON.parse(JSON.print(RunData.players_data[i].serialize())).result)
			check(restored.current_character.my_id == selected[i].my_id, "native save roundtrip " + selected[i].my_id)
		yield(get_tree().create_timer(0.24), "timeout")
		for player in scene._players:
			if player.has_node("NoobsAnimation"):
				var actor = player.get_node("NoobsAnimation")
				check(actor.state == "run" and actor.frame_index > 0, "movement advances original frames " + str(player.player_index))
		shot("combat-batch-" + str(batch))
		for player in scene._players:
			if not player.has_node("NoobsAnimation"):
				continue
			var actor = player.get_node("NoobsAnimation")
			player._current_movement = Vector2.LEFT
			yield(settle(3), "completed")
			check(player.sprite.scale.x < 0, "left facing " + str(player.player_index))
			player._current_movement = Vector2.ZERO
			player.on_damage_effect(1, false, false)
			yield(settle(2), "completed")
			check(actor.state == "hurt", "real damage plays hurt " + str(player.player_index))
			yield(get_tree().create_timer(actor.clips.hurt.duration + 0.05), "timeout")
			check(actor.state == "idle", "hurt returns to idle " + str(player.player_index))
			player.dance()
			yield(settle(3), "completed")
			check(actor.state == "special", "victory uses original special " + str(player.player_index))
			player._animation_player.play(player.animation_idle)
		# Keep one survivor to avoid the game-over menu interrupting the probe.
		var victim = scene._players[0]
		victim.on_damage_effect(9999, false, false)
		yield(settle(3), "completed")
		check(victim.dead and victim.get_node("NoobsAnimation").state == "death", "native lethal damage plays death")
		get_tree().change_scene("res://ui/menus/run/character_selection.tscn")
		yield(settle(20), "completed")
	_setup_run([roster[0]])
	DebugService.no_enemies = false
	get_tree().change_scene("res://main.tscn")
	yield(get_tree().create_timer(8.0), "timeout")
	scene = get_tree().current_scene
	check(scene.filename == "res://main.tscn" and scene._players[0].has_node("NoobsAnimation"), "solo real wave running with animated character")
	shot("solo-live-combat")
	var reached_shop = false
	for _i in 250:
		yield(get_tree().create_timer(0.1), "timeout")
		var current = get_tree().current_scene
		if current.filename == "res://main.tscn" and current._upgrades_ui.visible:
			# Choose the first available upgrade or take the crate through its
			# native button. Level-up rewards must be processed before the shop.
			_press_reward_button(current._upgrades_ui)
		if get_tree().current_scene.filename == "res://ui/menus/shop/shop.tscn":
			reached_shop = true
			break
	check(reached_shop, "natural wave ends in native shop")
	if not reached_shop:
		shot("failed-wave-transition")
	if reached_shop:
		scene = get_tree().current_scene
		yield(settle(8), "completed")
		shot("solo-shop")
		scene._on_GoButton_pressed(0)
		yield(get_tree().create_timer(2.0), "timeout")
		scene = get_tree().current_scene
		check(scene.filename == "res://main.tscn" and RunData.current_wave == 2, "native shop advances to wave two")
		if scene.filename == "res://main.tscn":
			check(scene._players[0].has_node("NoobsAnimation"), "animation reattached after wave transition")
	_finish()

func _press_reward_button(node):
	if node is Button and node.name in ["ChooseButton", "TakeButton"] and node.is_visible_in_tree() and not node.disabled:
		node.emit_signal("pressed")
		return true
	for child in node.get_children():
		if _press_reward_button(child):
			return true
	return false

func _finish():
	print("NWTL_RESULT: %s checks, %s failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _timeout():
	check(false, "test timeout")
	_finish()
