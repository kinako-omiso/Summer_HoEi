extends Node3D


# The future map generator can remove children from these groups until the
# requested count (0-5) remains. This component intentionally does not perform
# random selection by itself.
const DESK_CANDIDATE_GROUP := &"random_desk_monitor_candidates"
const PLANT_CANDIDATE_GROUP := &"random_plant_candidates"
const LOCKER_CANDIDATE_GROUP := &"random_locker_candidates"


# Match the current breaker behavior in temp_main.gd: a breaker can be used
# once, turns the world lights off, and enables the emergency/player lights.
func _on_breaker_lights_out() -> void:
	get_tree().set_group("lights", "light_energy", 0.0)
	get_tree().set_group("player_lights", "light_energy", 1.0)
	get_tree().set_group("robot_lights", "light_energy", 6.0)
