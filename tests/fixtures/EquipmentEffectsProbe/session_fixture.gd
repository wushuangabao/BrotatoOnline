extends "res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/scripts/session_manager.gd"

func _start_steam_room(_open_overlay: bool) -> bool:
	# Two local test processes share one Steam account. Keep this fixture on real
	# ENet/LAN instead of also opening competing Steam lobbies for that account.
	_lobby_toggle_pending_create = false
	_open_invite_overlay_after_create = false
	return false
