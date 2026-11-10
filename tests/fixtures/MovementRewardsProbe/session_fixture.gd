extends "res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/scripts/session_manager.gd"

func _start_steam_room(_open_overlay: bool) -> bool:
	# Two local test processes share one Steam account. Keep this fixture on real
	# ENet/LAN instead of also opening competing Steam lobbies for that account.
	_lobby_toggle_pending_create = false
	_open_invite_overlay_after_create = false
	return false

var drop_reports = 0
var drop_acks = 0
var dropped_reports = 0
var dropped_acks = 0

func send_battle_message_to_host(message: Dictionary, reliable: bool = true) -> bool:
	if message.get("msg_type", "") == "movement_rewards" and drop_reports > 0:
		drop_reports -= 1
		dropped_reports += 1
		return true
	return .send_battle_message_to_host(message, reliable)

func _send_p2p_json(target_steam_id: String, message: Dictionary, reliable: bool = true) -> bool:
	if message.get("msg_type", "") == "movement_rewards_ack" and drop_acks > 0:
		drop_acks -= 1
		dropped_acks += 1
		return true
	return ._send_p2p_json(target_steam_id, message, reliable)
