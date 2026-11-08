extends "res://mods-unpacked/six666-BrotatoOnline/scripts/menu_sync_manager.gd"

var test_host = false
var test_shop = null

func _is_game_host() -> bool:
	return test_host

func _get_local_client_player_index() -> int:
	return 1

func _find_shop_node():
	return test_shop

func _resolve_run_page_action_player_index(_origin: String, _from: String, _self_id: String, message: Dictionary) -> int:
	return int(message.get("player_index", 1))
