extends SceneTree


const ROOM_A := "res://components/rooms/room_a_office.tscn"
const ROOM_B := "res://components/rooms/room_b_storage.tscn"

const DESK_GROUP := &"random_desk_monitor_candidates"
const PLANT_GROUP := &"random_plant_candidates"
const LOCKER_GROUP := &"random_locker_candidates"

var _has_run := false


func _process(_delta: float) -> bool:
	if _has_run:
		return false
	_has_run = true
	_run_validation()
	return true


func _run_validation() -> void:
	var failures: Array[String] = []
	_validate_room(ROOM_A, {DESK_GROUP: 5, PLANT_GROUP: 0, LOCKER_GROUP: 0}, failures)
	_validate_room(ROOM_B, {DESK_GROUP: 0, PLANT_GROUP: 5, LOCKER_GROUP: 5}, failures)

	if failures.is_empty():
		print("Validated both room component scenes.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _validate_room(
	scene_path: String,
	expected_counts: Dictionary,
	failures: Array[String],
) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		failures.append("%s: could not load scene" % scene_path)
		return

	var room := packed.instantiate() as Node3D
	if room == null:
		failures.append("%s: root is not Node3D" % scene_path)
		return
	root.add_child(room)

	var structure := room.get_node_or_null("Structure")
	if structure == null:
		failures.append("%s: Structure node is missing" % scene_path)
	else:
		var wall_count := 0
		for child: Node in structure.get_children():
			if child.name.to_lower().begins_with("wall"):
				wall_count += 1
		if wall_count != 3:
			failures.append("%s: expected 3 walls, found %d" % [scene_path, wall_count])
		if structure.get_node_or_null("WallNorth") != null:
			failures.append("%s: north wall must remain open" % scene_path)
		if structure.get_node_or_null("Floor") == null:
			failures.append("%s: floor is missing" % scene_path)
		if structure.get_node_or_null("Ceiling") == null:
			failures.append("%s: ceiling is missing" % scene_path)

	if not room.find_children("*", "NavigationRegion3D", true, false).is_empty():
		failures.append("%s: room must not contain NavigationRegion3D" % scene_path)

	var breaker := room.get_node_or_null("Breaker")
	if breaker == null:
		failures.append("%s: breaker is missing" % scene_path)
	elif not breaker.is_connected("lights_out", Callable(room, "_on_breaker_lights_out")):
		failures.append("%s: breaker is not connected to light control" % scene_path)

	var all_candidates: Array[Node3D] = []
	var central_route := AABB(Vector3(-1.5, 0.15, -6.7), Vector3(3.0, 2.5, 12.2))
	for group_name: StringName in expected_counts:
		var candidates := _find_group_members(room, group_name)
		all_candidates.append_array(candidates)
		var expected_count: int = expected_counts[group_name]
		if candidates.size() != expected_count:
			failures.append(
				"%s: group %s expected %d candidates, found %d"
				% [scene_path, group_name, expected_count, candidates.size()]
			)
		for candidate: Node3D in candidates:
			var bounds := _mesh_bounds_in_room(candidate, room)
			if bounds.intersects(central_route):
				failures.append(
					"%s: %s obstructs the central north-south route"
					% [scene_path, candidate.get_path()]
				)

	for first_index: int in range(all_candidates.size()):
		var first := all_candidates[first_index]
		var first_bounds := _mesh_bounds_in_room(first, room).grow(0.02)
		for second_index: int in range(first_index + 1, all_candidates.size()):
			var second := all_candidates[second_index]
			var second_bounds := _mesh_bounds_in_room(second, room).grow(0.02)
			if first_bounds.intersects(second_bounds):
				failures.append(
					"%s: candidates overlap: %s and %s"
					% [scene_path, first.get_path(), second.get_path()]
				)

	var lights := room.find_children("*", "AreaLight3D", true, false)
	if lights.size() != 5:
		failures.append("%s: expected 5 inherited room lights, found %d" % [scene_path, lights.size()])
	elif breaker != null:
		breaker.emit_signal("lights_out")
		for light: AreaLight3D in lights:
			if not is_zero_approx(light.light_energy):
				failures.append("%s: breaker did not turn off %s" % [scene_path, light.get_path()])

	room.free()


func _find_group_members(room: Node, group_name: StringName) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child: Node in room.find_children("*", "Node3D", true, false):
		if child.is_in_group(group_name):
			result.append(child as Node3D)
	return result


func _mesh_bounds_in_room(candidate: Node3D, room: Node3D) -> AABB:
	var result := AABB()
	var has_point := false
	for child: Node in candidate.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var transform_to_room := room.global_transform.affine_inverse() * mesh_instance.global_transform
		var mesh_bounds := mesh_instance.mesh.get_aabb()
		for endpoint_index: int in range(8):
			var point := transform_to_room * mesh_bounds.get_endpoint(endpoint_index)
			if has_point:
				result = result.expand(point)
			else:
				result = AABB(point, Vector3.ZERO)
				has_point = true
	return result
