extends "res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/scripts/session_manager.gd"

func _start_steam_room(_open_overlay: bool) -> bool:
	_lobby_toggle_pending_create = false
	_open_invite_overlay_after_create = false
	return false
