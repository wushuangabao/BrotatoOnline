extends "res://effect_behaviors/player/for_every_step_effect_behavior.gd"

func on_moved(delta_position: Vector2) -> void:
	var sync = get_tree().root.find_node("BrotatoOnlineMovementRewards", true, false)
	if sync == null or not sync.active():
		.on_moved(delta_position)
		return
	# Proxies must never execute the owning player's movement rewards a second time.
	if not sync.owns(_player_index) or sync.sealed:
		return
	var before = sync.capture(_player_index)
	.on_moved(delta_position)
	sync.record(_player_index, before)
