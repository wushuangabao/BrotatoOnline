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
