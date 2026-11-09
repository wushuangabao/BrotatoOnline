extends SceneTree

class TestTransport:
	extends "res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/scripts/steam_transport.gd"
	var test_steam = null
	func _get_steam_singleton():
		return test_steam

class SteamAPI:
	extends Reference
	signal lobby_created(result, lobby_id)
	var user_id = 0
	var running = true
	var init_calls = 0
	var status = 0
	var id_after_init = 12345
	func getSteamID():
		return user_id
	func isSteamRunning():
		return running

class SteamEx:
	extends SteamAPI
	func steamInitEx(_app_id, _callbacks):
		init_calls += 1
		if status == 0:
			user_id = id_after_init
		return {"status": status}

class SteamLegacy:
	extends SteamAPI
	func steamInit():
		init_calls += 1
		if status == 0:
			user_id = id_after_init
		return status == 0

var checks = 0
var failures = 0
var callbacks = 0

func _check(condition, label):
	checks += 1
	if not condition:
		failures += 1
	print("STEAM_INIT_", "PASS" if condition else "FAIL", ": ", label)

func _on_lobby(_result, _id):
	callbacks += 1

func _init():
	var transport = TestTransport.new()
	transport._setup_steam()
	_check(not transport.is_available() and transport.get_steam() == null, "missing singleton keeps transport unavailable")
	var steam = SteamEx.new()
	steam.user_id = 12345
	steam.status = 1 # A second initialization would fail; it must not be called.
	transport.test_steam = steam
	transport._setup_steam()
	transport._setup_steam()
	_check(transport.is_available() and transport.get_steam() == steam and steam.init_calls == 0, "already initialized API reused without a second init")
	transport.connect("lobby_created", self, "_on_lobby")
	transport._connect_callbacks()
	transport._connect_callbacks()
	steam.emit_signal("lobby_created", 1, 42)
	_check(callbacks == 1, "reused API callback forwarded exactly once")
	steam = SteamEx.new()
	transport.test_steam = steam
	transport._setup_steam()
	_check(transport.is_available() and steam.init_calls == 1, "uninitialized API initialized once")
	transport._setup_steam()
	_check(transport.is_available() and steam.init_calls == 1, "subsequent setup reuses newly initialized API")
	steam = SteamEx.new()
	steam.status = 1
	transport.test_steam = steam
	transport._setup_steam()
	_check(not transport.is_available() and transport.get_steam() == null and steam.init_calls == 1, "init failure remains unavailable")
	steam = SteamEx.new()
	steam.running = false
	transport.test_steam = steam
	transport._setup_steam()
	_check(not transport.is_available() and steam.init_calls == 0, "Steam not running skips initialization")
	steam = SteamLegacy.new()
	transport.test_steam = steam
	transport._setup_steam()
	transport._setup_steam()
	_check(transport.is_available() and steam.init_calls == 1, "legacy initialization and reuse supported")
	steam = SteamEx.new()
	steam.id_after_init = 0
	transport.test_steam = steam
	transport._setup_steam()
	_check(not transport.is_available() and transport.get_steam() == null, "init success without a user ID is unavailable")
	steam = SteamAPI.new()
	steam.user_id = 12345
	transport.test_steam = steam
	transport._setup_steam()
	_check(transport.is_available(), "live API needs no initialization method")
	transport.free()
	print("STEAM_INIT_RESULT: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
