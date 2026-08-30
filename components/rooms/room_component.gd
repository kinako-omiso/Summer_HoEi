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
	for node: Node in get_tree().get_nodes_in_group(&"power_emissive_surfaces"):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var material := (
				mesh_instance.get_active_material(surface_index) as BaseMaterial3D
			)
			if material != null:
				material.emission_enabled = false
	get_tree().set_group("player_lights", "light_energy", 1.0)
	get_tree().set_group("robot_lights", "light_energy", 6.0)
