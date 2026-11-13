extends "res://main.gd"

func _on_WaveTimer_timeout() -> void:
	# Exercise a successful cleanup entry that bypasses WaveTimer's effects.
	# The production drain barrier must route back through the native effects.
	if OS.get_environment("BROTATO_TEST_ROLE") == "client" and OS.get_environment("BROTATO_SETTLEMENT_MODE") == "cleanup" and not get_meta("test_cleanup_injected", false):
		set_meta("test_cleanup_injected", true)
		clean_up_room()
		return
	# Fault injection only: delay the client's entry into the real callback.
	if OS.get_environment("BROTATO_TEST_ROLE") == "client" and OS.get_environment("BROTATO_SETTLEMENT_MODE") == "wave" and not get_meta("test_release_wave", false):
		return
	._on_WaveTimer_timeout()

func _on_EndWaveTimer_timeout() -> void:
	._on_EndWaveTimer_timeout()
	_verify_after_native_callback()

func _on_HarvestingTimer_timeout() -> void:
	._on_HarvestingTimer_timeout()
	_verify_after_native_callback()

func _verify_after_native_callback():
	if OS.get_environment("BROTATO_TEST_ROLE") == "client" and get_tree() != null:
		get_tree().root.get_node("WaveSettlementLanRegression")._verify_native_duplicates()

# Different endpoint seeds reproduce the 1.2.0.2 divergence if native equip is replayed.
func on_item_box_take_button_pressed(item_data: ItemParentData, consumable: UpgradesUI.ConsumableToProcess) -> void:
	if OS.get_environment("BROTATO_SETTLEMENT_MODE") == "compat":
		get_tree().root.get_node("WaveSettlementLanRegression").crate_native_calls += 1
		seed(0 if OS.get_environment("BROTATO_TEST_ROLE") == "host" else 1)
	.on_item_box_take_button_pressed(item_data, consumable)
