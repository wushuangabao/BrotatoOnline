extends "res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/scripts/menu_sync_manager.gd"

var test_host = false
var test_shop = null

func _build_shop_player_state(index: int, shop: Node = null, force_full: bool = false, include_sync: bool = true) -> Dictionary:
	# This suite exercises the existing reconciliation/bootstrap path before a
	# client is granted its shop epoch. Owner-mode behavior has a separate LAN suite.
	var state = ._build_shop_player_state(index, shop, force_full, include_sync)
	state.erase("shop_owner_epoch")
	state.erase("shop_owner_revision")
	return state

func _build_shop_action_delta_state(index: int, action: String, message: Dictionary = {}, applied: bool = true) -> Dictionary:
	var state = ._build_shop_action_delta_state(index, action, message, applied)
	state.erase("shop_owner_epoch")
	state.erase("shop_owner_revision")
	return state

func _is_game_host() -> bool:
	return test_host

func _get_local_client_player_index() -> int:
	return 1

func _find_shop_node():
	return test_shop

func _resolve_run_page_action_player_index(_origin: String, _from: String, _self_id: String, message: Dictionary) -> int:
	return int(message.get("player_index", 1))
