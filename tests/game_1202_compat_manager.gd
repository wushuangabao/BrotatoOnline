extends "res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/tests/shop_reconciliation_manager.gd"

var messages = []

func _is_online_session_active() -> bool:
	return true

func _queue_local_run_page_action(message: Dictionary) -> void:
	message["action_id"] = "compat:" + str(messages.size() + 1)
	messages.append(JSON.parse(JSON.print(message)).result)
