extends Node

var checks = 0
var failures = 0

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	DebugService.disable_saving = true
	get_tree().create_timer(45).connect("timeout", self, "_timeout")
	call_deferred("_run")

func _timeout():
	printerr("SHOP_RECONCILIATION_FAIL: watchdog")
	get_tree().quit(2)

func _check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("SHOP_RECONCILIATION_FAIL: " + label)
	else:
		print("SHOP_RECONCILIATION_PASS: " + label)

func _set_current_shop(shop):
	get_tree().current_scene = shop

func _run():
	ProgressData.apply_settings()
	ProgressData.settings.pause_on_focus_lost = false
	ProgressData.settings.keep_lock = true
	RunData.reset()
	RunData.set_player_count(2, true)
	RunData.set_coop_run(true)
	CoopService.connected_players = [[7, 0], [0, 1]]
	for i in 2:
		RunData.add_character(load("res://items/characters/well_rounded/well_rounded_data.tres"), i)
		RunData.add_weapon(load("res://weapons/ranged/pistol/1/pistol_data.tres"), i, true)
		RunData.players_data[i].gold = 10000
	RunData.current_wave = 22
	RunData.is_endless_run = true
	ZoneService.set_current_zone(ZoneService.get_zone_data(RunData.current_zone).duplicate())
	ItemService.init_unlocked_pool()
	var host = load("res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/tests/shop_reconciliation_manager.gd").new()
	var client = load("res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/tests/shop_reconciliation_manager.gd").new()
	host.test_host = true
	add_child(host)
	add_child(client)
	host.set_process(false)
	client.set_process(false)
	get_tree().current_scene = null
	for item_path in ["res://weapons/ranged/smg/1/smg_data.tres", "res://items/all/00_base_game/lens/lens_data.tres"]:
		RunData.locked_shop_items[1] = [[load(item_path), 21]]
		RunData.shop_effects_checked = false
		var shop = load("res://ui/menus/shop/coop_shop.tscn").instance()
		shop.connect("tree_entered", self, "_set_current_shop", [shop])
		get_tree().root.add_child(shop)
		get_tree().current_scene = shop
		for _i in 8:
			yield(get_tree(), "idle_frame")
		host.test_shop = shop
		client.test_shop = shop
		client._ensure_shop_state_diff_cache_for_instance(shop)
		var initial = host._build_shop_player_state(1, shop, true)
		# Capture the real rejection payload BEFORE changing the client's UI. Delivery
		# below is controlled; real ShopItem/RunData and production repair paths execute.
		var rejected_lock = host._build_shop_action_delta_state(1, "shop_lock", {}, false)
		var rejected_buy = initial.duplicate(true)
		host._append_forced_shop_run_data_repair_to_delta_state(rejected_buy, 1, "shop_buy_failed")
		initial = parse_json(JSON.print(initial))
		rejected_lock = parse_json(JSON.print(rejected_lock))
		rejected_buy = parse_json(JSON.print(rejected_buy))
		client._apply_all_shop_states_to_ui([initial])
		var card = shop._get_shop_items_container(1)._shop_items[0]
		_check(card.locked and card.active and card.wave_value == 21, "retained ordinary offer starts locked: " + card.item_data.my_id)
		client._on_client_shop_item_lock_toggled(false, card, 1)
		_check(not card.locked, "unlock prediction visible")
		client._apply_all_shop_states_to_ui([rejected_lock])
		_check(card.locked, "rejected unlock restores identical cached host state")
		var before_gold = RunData.get_player_gold(1)
		var before_items = RunData.get_player_items(1).size()
		var before_weapons = RunData.get_player_weapons(1).size()
		var request = client._build_client_shop_item_action("shop_buy", card, 1)
		_check(client._apply_client_local_shop_purchase(request, 1) and not card.active, "optimistic purchase deactivates offer")
		if host.has_method("_take_shop_state_revision"):
			rejected_buy["shop_state_revision"] = host._take_shop_state_revision()
		client._apply_all_shop_states_to_ui([rejected_buy])
		_check(card.active and card.locked and not card._button.disabled and not card._lock_button.disabled, "rejected buy restores active locked buttons despite cached slot key")
		_check(RunData.get_player_gold(1) == before_gold and RunData.get_player_items(1).size() == before_items and RunData.get_player_weapons(1).size() == before_weapons, "rejection restores currency and inventory exactly")
		client._apply_shop_lock_action(1, {"target": "item_0", "desired_locked": false})
		_check(not card.locked, "repaired offer can unlock again")
		request = client._build_client_shop_item_action("shop_buy", card, 1)
		_check(client._apply_client_local_shop_purchase(request, 1) and not card.active, "repaired offer can be purchased again")
		if host.has_method("_build_shop_purchase_receipt"):
			client.consume_local_run_page_action_messages()
			var receipt = host._build_shop_purchase_receipt(1)
			var committed = host._build_shop_player_state(1, shop, true)
			host._append_forced_shop_run_data_repair_to_delta_state(committed, 1, "receipt_mismatch")
			committed["shop_purchase_receipt"] = receipt
			committed = parse_json(JSON.print(committed))
			var ack = {"action_id": item_path + ":receipt", "action_type": "shop_buy", "player_index": 1, "shop_buy_result": "success", "shop_purchase_receipt": receipt}
			client.receive_run_page_action_sync("host", ack, "client")
			_check(client.consume_local_run_page_action_messages().empty(), "matching purchase receipt needs no full repair")
			client._apply_all_shop_states_to_ui([rejected_buy])
			var repairs = client.consume_local_run_page_action_messages()
			_check(repairs.size() == 1 and repairs[0].action_type == "shop_purchase_repair", "late older state after success requests repair")
			client._apply_all_shop_states_to_ui([rejected_buy])
			_check(client.consume_local_run_page_action_messages().empty(), "only one repair is in flight")
			client.receive_run_page_action_sync("host", {"action_id": item_path + ":repair", "action_type": "shop_purchase_repair", "player_index": 1, "host_state_after": committed}, "client")
			_check(JSON.print(host._build_shop_purchase_receipt(1), "", true) == JSON.print(receipt, "", true) and not card.active, "repair restores confirmed purchase without buying twice")
			_check(client.consume_local_run_page_action_messages().empty(), "repair does not recursively request itself")
			client._apply_all_shop_states_to_ui([rejected_buy])
			_check(JSON.print(host._build_shop_purchase_receipt(1), "", true) == JSON.print(receipt, "", true) and client.consume_local_run_page_action_messages().empty(), "older correction cannot roll back completed repair")
			client.receive_run_page_action_sync("host", {"action_id": item_path + ":reroll", "action_type": "shop_reroll", "player_index": 1, "host_state_after": rejected_buy}, "client")
			_check(JSON.print(host._build_shop_purchase_receipt(1), "", true) == JSON.print(receipt, "", true), "stale reroll does not replay native gold and slot mutations")
			var older_receipt = receipt.duplicate(true)
			older_receipt["shop_state_revision"] = rejected_buy.shop_state_revision
			older_receipt.gold = -1
			client._request_shop_purchase_repair_if_needed(1, older_receipt)
			_check(client.consume_local_run_page_action_messages().empty(), "older purchase receipt cannot supersede a newer repair")
			var stale_receipt = receipt.duplicate(true)
			stale_receipt.current_wave -= 1
			stale_receipt.gold = -1
			client._request_shop_purchase_repair_if_needed(1, stale_receipt)
			_check(client.consume_local_run_page_action_messages().empty(), "previous wave receipt is ignored")
			# A partial lock delta cannot cover the inventory in an earlier receipt or
			# repair. Exercise both message orderings without rolling the lock back.
			var delayed_receipt = host._build_shop_purchase_receipt(1, true)
			var action_origin = "shop_test_" + str(checks)
			var newer_lock = host._build_shop_action_delta_state(1, "shop_lock", {"shop_index": 1}, true)
			client.receive_run_page_action_sync("host", {"action_type": "shop_lock", "action_id": action_origin + ":2", "player_index": 1, "host_state_after": parse_json(JSON.print(newer_lock))}, "client")
			client.receive_run_page_action_sync("host", {"action_type": "shop_buy", "action_id": action_origin + ":1", "player_index": 1, "shop_buy_result": "success", "shop_purchase_receipt": delayed_receipt}, "client")
			repairs = client.consume_local_run_page_action_messages()
			_check(repairs.size() == 1 and repairs[0].action_type == "shop_purchase_repair", "receipt older than partial delta still recovers missing inventory")
			var delayed_repair = host._build_shop_player_state(1, shop, true)
			host._append_forced_shop_run_data_repair_to_delta_state(delayed_repair, 1, "receipt_mismatch")
			var other_card = shop._get_shop_items_container(1)._shop_items[1]
			var desired_lock = not other_card.locked
			host._apply_shop_lock_action(1, {"target": "item_1", "desired_locked": desired_lock})
			# This fixture shares the native shop between the two managers. Drain the
			# lock signal's simulated outbound request before examining repair traffic.
			client.consume_local_run_page_action_messages()
			newer_lock = host._build_shop_action_delta_state(1, "shop_lock", {"shop_index": 1}, true)
			client.receive_run_page_action_sync("host", {"action_type": "shop_lock", "action_id": action_origin + ":4", "player_index": 1, "host_state_after": parse_json(JSON.print(newer_lock))}, "client")
			client.receive_run_page_action_sync("host", {"action_type": "shop_purchase_repair", "action_id": action_origin + ":3", "player_index": 1, "host_state_after": parse_json(JSON.print(delayed_repair))}, "client")
			repairs = client.consume_local_run_page_action_messages()
			_check(other_card.locked == desired_lock and repairs.size() == 1 and repairs[0].action_type == "shop_purchase_repair", "partial delta overtaking repair requests current state without reverting lock")
			var current_repair = host._build_shop_player_state(1, shop, true)
			host._append_forced_shop_run_data_repair_to_delta_state(current_repair, 1, "receipt_mismatch")
			current_repair["shop_purchase_receipt"] = host._build_shop_purchase_receipt(1)
			current_repair.shop_purchase_receipt["shop_state_revision"] = current_repair.shop_state_revision
			client.receive_run_page_action_sync("host", {"action_type": "shop_purchase_repair", "action_id": action_origin + ":5", "player_index": 1, "host_state_after": parse_json(JSON.print(current_repair))}, "client")
			_check(other_card.locked == desired_lock and not card.active and client.consume_local_run_page_action_messages().empty(), "current full repair settles inventory and newer lock without a loop")
		get_tree().current_scene = self
		host.test_shop = null
		client.test_shop = null
		shop.free()
	print("SHOP_RECONCILIATION_RESULT: ", checks, " checks, ", failures, " failures")
	get_tree().quit(1 if failures else 0)
