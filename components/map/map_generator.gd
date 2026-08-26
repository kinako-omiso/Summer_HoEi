extends Node3D


signal map_generated(seed_value: int)

const ROOM_COUNT := 6
const MAIN_EDGE_COUNT := 6
const CORRIDOR_WIDTH := 8.0
const CORRIDOR_HALF_WIDTH := CORRIDOR_WIDTH * 0.5
const CORRIDOR_SOURCE_LENGTH := 28.0
const JUNCTION_HALF_SIZE := 4.0
const JUNCTION_SURFACE_SIZE := 12.0
const ROOM_HALF_SIZE := 7.0
const ROOM_DOOR_OFFSET := Vector2(-5.12, -6.87)
const ROOM_WALL_HEIGHT := 3.15
const MAX_LAYOUT_ATTEMPTS := 80
const MAX_BRANCH_ATTEMPTS := 96

const CORRIDOR_MODULE := preload("res://components/map/corridor_module.tscn")
const FLOOR_SQUARE := preload("res://assets/3DModel/floor_square.tscn")
const CEILING_SQUARE_WITH_LIGHT := preload("res://assets/3DModel/ceiling_square_with_light.tscn")
const ROOM_A := preload("res://components/rooms/room_a_office.tscn")
const ROOM_B := preload("res://components/rooms/room_b_storage.tscn")
const ROOM_ENTRANCE := preload("res://assets/3DModel/wall_with_door.tscn")
const ELEVATOR := preload("res://assets/3DModel/elevator.tscn")
const ELEVATOR_DOOR := preload("res://assets/3DModel/elevator_door.tscn")

@export_range(100.0, 500.0, 1.0) var minimum_corridor_length := 100.0
@export_range(100.0, 500.0, 1.0) var maximum_corridor_length := 500.0
@export var allow_diagonal_turns := true
@export_range(0.0, 1.0, 0.05) var elevator_room_attachment_chance := 0.35
@export var seed_override: int = 0

var generated_seed: int = 0
var player_spawn_position := Vector3.ZERO
var robot_spawn_position := Vector3.ZERO
var last_layout: Dictionary = {}

var _rng := RandomNumberGenerator.new()


func generate_map(requested_seed: int = 0) -> bool:
	_clear_generated_map()
	_configure_rng(requested_seed)
	var layout := _build_valid_layout()
	if not layout.is_empty():
		last_layout = layout
		_instantiate_layout(layout)
		map_generated.emit(generated_seed)
		return true
	push_error("MapGenerator could not create a non-overlapping map after %d attempts." % MAX_LAYOUT_ATTEMPTS)
	return false


func generate_layout_for_seed(test_seed: int) -> Dictionary:
	_configure_rng(test_seed)
	return _build_valid_layout()


func _build_valid_layout() -> Dictionary:
	for _attempt: int in range(MAX_LAYOUT_ATTEMPTS):
		var layout := _try_build_layout()
		if not layout.is_empty():
			return layout
	return {}


func _configure_rng(requested_seed: int) -> void:
	if requested_seed != 0:
		generated_seed = requested_seed
	elif seed_override != 0:
		generated_seed = seed_override
	else:
		_rng.randomize()
		generated_seed = _rng.seed
	_rng.seed = generated_seed


func _clear_generated_map() -> void:
	for child: Node in get_children():
		child.free()
	last_layout = {}


func _try_build_layout() -> Dictionary:
	var main_points := _try_build_main_corridor()
	if main_points.is_empty():
		return {}

	var main_polygons: Array[PackedVector2Array] = []
	for edge_index: int in range(main_points.size() - 1):
		main_polygons.append(
			_segment_polygon(main_points[edge_index], main_points[edge_index + 1], CORRIDOR_HALF_WIDTH + 0.2)
		)

	var branch_specs: Array[Dictionary] = []
	var branch_polygons: Array[PackedVector2Array] = []
	var room_polygons: Array[PackedVector2Array] = []
	var room_specs: Array[Dictionary] = []

	for room_index: int in range(ROOM_COUNT):
		var branch_spec := _try_place_room_branch(
			room_index,
			main_points,
			main_polygons,
			branch_polygons,
			room_polygons
		)
		if branch_spec.is_empty():
			return {}

		branch_specs.append(branch_spec)
		branch_polygons.append(branch_spec["corridor_polygon"])
		room_polygons.append(branch_spec["room_polygon"])
		room_specs.append(
			{
				"type": "A" if _rng.randi_range(0, 1) == 0 else "B",
				"origin": branch_spec["room_origin"],
				"yaw": branch_spec["room_yaw"],
				"door_point": branch_spec["end"],
			}
		)

	var direct_room_candidates: Array[int] = []
	for room_index: int in range(room_specs.size()):
		if room_specs[room_index]["type"] == "A":
			direct_room_candidates.append(room_index)

	var elevator_mode := "corridor"
	var elevator_room_index := -1
	if not direct_room_candidates.is_empty() and _rng.randf() < elevator_room_attachment_chance:
		elevator_mode = "room"
		elevator_room_index = direct_room_candidates[_rng.randi_range(0, direct_room_candidates.size() - 1)]

	var turn_report := _analyze_turns(main_points)
	return {
		"seed": generated_seed,
		"main_points": main_points,
		"branches": branch_specs,
		"rooms": room_specs,
		"elevator_mode": elevator_mode,
		"elevator_room_index": elevator_room_index,
		"right_angle_turns": turn_report["right_angle_turns"],
		"has_diagonal_turn": turn_report["has_diagonal_turn"],
	}


func _try_build_main_corridor() -> Array[Vector2]:
	for _attempt: int in range(80):
		var points: Array[Vector2] = [Vector2.ZERO]
		var segment_polygons: Array[PackedVector2Array] = []
		var yaw := float(_rng.randi_range(0, 3)) * PI * 0.5
		var valid := true

		for edge_index: int in range(MAIN_EDGE_COUNT):
			if edge_index == 1 or edge_index == 2:
				yaw += (PI * 0.5) * (-1.0 if _rng.randi_range(0, 1) == 0 else 1.0)
			elif edge_index > 2:
				var turn_options: Array[float] = [-PI * 0.5, PI * 0.5]
				if allow_diagonal_turns:
					turn_options.append_array([-PI * 0.25, PI * 0.25])
				yaw += turn_options[_rng.randi_range(0, turn_options.size() - 1)]

			var length := _rng.randf_range(minimum_corridor_length, maximum_corridor_length)
			var direction := _direction_from_yaw(yaw)
			var candidate_end := points[-1] + direction * length
			var candidate_polygon := _segment_polygon(
				points[-1], candidate_end, CORRIDOR_HALF_WIDTH + 1.0
			)

			for previous_index: int in range(segment_polygons.size() - 1):
				if _polygons_overlap(candidate_polygon, segment_polygons[previous_index]):
					valid = false
					break
			if not valid:
				break

			points.append(candidate_end)
			segment_polygons.append(candidate_polygon)

		if valid and points.size() == MAIN_EDGE_COUNT + 1:
			return points

	return []


func _try_place_room_branch(
	room_index: int,
	main_points: Array[Vector2],
	main_polygons: Array[PackedVector2Array],
	existing_branch_polygons: Array[PackedVector2Array],
	existing_room_polygons: Array[PackedVector2Array],
) -> Dictionary:
	var start := main_points[room_index]
	var connected_directions: Array[Vector2] = []
	if room_index > 0:
		connected_directions.append((main_points[room_index - 1] - start).normalized())
	if room_index < main_points.size() - 1:
		connected_directions.append((main_points[room_index + 1] - start).normalized())

	var angle_options: Array[float] = []
	var angle_step := PI * 0.25 if allow_diagonal_turns else PI * 0.5
	var option_count := 8 if allow_diagonal_turns else 4
	for angle_index: int in range(option_count):
		angle_options.append(float(angle_index) * angle_step)
	_shuffle_with_rng(angle_options)

	for attempt: int in range(MAX_BRANCH_ATTEMPTS):
		if attempt > 0 and attempt % angle_options.size() == 0:
			_shuffle_with_rng(angle_options)
		var yaw := angle_options[attempt % angle_options.size()]
		var direction := _direction_from_yaw(yaw)
		var direction_is_free := true
		for connected_direction: Vector2 in connected_directions:
			if direction.dot(connected_direction) > 0.70:
				direction_is_free = false
				break
		if not direction_is_free:
			continue

		var length := _rng.randf_range(minimum_corridor_length, maximum_corridor_length)
		var end := start + direction * length
		var corridor_polygon := _segment_polygon(start, end, CORRIDOR_HALF_WIDTH + 0.3)
		var intersects_existing := false

		for main_edge_index: int in range(main_polygons.size()):
			if main_edge_index == room_index or main_edge_index == room_index - 1:
				continue
			if _polygons_overlap(corridor_polygon, main_polygons[main_edge_index]):
				intersects_existing = true
				break
		if intersects_existing:
			continue

		for existing_polygon: PackedVector2Array in existing_branch_polygons:
			if _polygons_overlap(corridor_polygon, existing_polygon):
				intersects_existing = true
				break
		if intersects_existing:
			continue

		var room_yaw := atan2(direction.x, direction.y)
		var room_origin := end - _rotate_y_2d(ROOM_DOOR_OFFSET, room_yaw)
		var room_polygon := _oriented_square_polygon(room_origin, ROOM_HALF_SIZE + 0.5, room_yaw)

		for existing_room_polygon: PackedVector2Array in existing_room_polygons:
			if _polygons_overlap(room_polygon, existing_room_polygon):
				intersects_existing = true
				break
		if intersects_existing:
			continue

		for main_polygon: PackedVector2Array in main_polygons:
			if _polygons_overlap(room_polygon, main_polygon):
				intersects_existing = true
				break
		if intersects_existing:
			continue

		return {
			"start": start,
			"end": end,
			"length": length,
			"yaw": yaw,
			"room_origin": room_origin,
			"room_yaw": room_yaw,
			"corridor_polygon": corridor_polygon,
			"room_polygon": room_polygon,
		}

	return {}


func _instantiate_layout(layout: Dictionary) -> void:
	var main_corridors := Node3D.new()
	main_corridors.name = "MainCorridors"
	add_child(main_corridors)
	var branch_corridors := Node3D.new()
	branch_corridors.name = "BranchCorridors"
	add_child(branch_corridors)
	var junctions := Node3D.new()
	junctions.name = "Junctions"
	add_child(junctions)
	var rooms_node := Node3D.new()
	rooms_node.name = "Rooms"
	add_child(rooms_node)
	var elevator_node := Node3D.new()
	elevator_node.name = "ElevatorTerminal"
	add_child(elevator_node)

	var main_points: Array[Vector2] = layout["main_points"]
	for edge_index: int in range(main_points.size() - 1):
		_add_corridor_edge(
			main_corridors,
			main_points[edge_index],
			main_points[edge_index + 1],
			JUNCTION_HALF_SIZE,
			JUNCTION_HALF_SIZE,
			"MainEdge%02d" % (edge_index + 1)
		)
	for point_index: int in range(main_points.size()):
		_add_junction(junctions, main_points[point_index], "Junction%02d" % (point_index + 1))

	var branches: Array = layout["branches"]
	for branch_index: int in range(branches.size()):
		var branch: Dictionary = branches[branch_index]
		_add_corridor_edge(
			branch_corridors,
			branch["start"],
			branch["end"],
			JUNCTION_HALF_SIZE,
			0.0,
			"RoomBranch%02d" % (branch_index + 1)
		)

	var room_instances: Array[Node3D] = []
	var room_specs: Array = layout["rooms"]
	for room_index: int in range(room_specs.size()):
		var room_spec: Dictionary = room_specs[room_index]
		var room_scene: PackedScene = ROOM_A if room_spec["type"] == "A" else ROOM_B
		var room := room_scene.instantiate() as Node3D
		room.name = "Room%02d_%s" % [room_index + 1, room_spec["type"]]
		rooms_node.add_child(room)
		var origin: Vector2 = room_spec["origin"]
		room.position = Vector3(origin.x, 0.0, origin.y)
		room.rotation.y = room_spec["yaw"]
		room.set_meta("generated_room_type", room_spec["type"])

		var entrance := ROOM_ENTRANCE.instantiate() as Node3D
		entrance.name = "EntranceWallWithDoor"
		room.add_child(entrance)
		entrance.position = Vector3(0.0, ROOM_WALL_HEIGHT, -6.87)

		var candidate_counts := {
			"desks": _prune_candidate_group(room, &"random_desk_monitor_candidates"),
			"plants": _prune_candidate_group(room, &"random_plant_candidates"),
			"lockers": _prune_candidate_group(room, &"random_locker_candidates"),
		}
		room.set_meta("generated_candidate_counts", candidate_counts)
		room_instances.append(room)

	if layout["elevator_mode"] == "room":
		var target_room_index: int = layout["elevator_room_index"]
		var target_room := room_instances[target_room_index]
		var south_wall := target_room.get_node_or_null("Structure/WallSouth")
		if south_wall != null:
			south_wall.free()
		var breaker := target_room.get_node_or_null("Breaker") as Node3D
		if breaker != null:
			breaker.position = Vector3(6.62, 2.0, 4.8)
			breaker.rotation.y = PI * 0.5
		var room_spec: Dictionary = room_specs[target_room_index]
		var elevator_yaw: float = room_spec["yaw"]
		var local_door := _rotate_y_2d(Vector2(0.0, 6.87), elevator_yaw)
		var room_origin: Vector2 = room_spec["origin"]
		_add_elevator_terminal(elevator_node, room_origin + local_door, elevator_yaw)
	else:
		var last_direction := (main_points[-1] - main_points[-2]).normalized()
		var elevator_yaw := atan2(last_direction.x, last_direction.y)
		var elevator_door_point := main_points[-1] + last_direction * JUNCTION_HALF_SIZE
		_add_elevator_terminal(elevator_node, elevator_door_point, elevator_yaw)

	var first_direction := (main_points[1] - main_points[0]).normalized()
	player_spawn_position = _to_world(main_points[0] + first_direction * 12.0, 0.45)
	var robot_direction := (main_points[-2] - main_points[-1]).normalized()
	robot_spawn_position = _to_world(main_points[-2] + robot_direction * 12.0, 0.45)


func _add_corridor_edge(
	parent: Node3D,
	from: Vector2,
	to: Vector2,
	start_trim: float,
	end_trim: float,
	edge_name: String,
) -> void:
	var direction := (to - from).normalized()
	var trimmed_start := from + direction * start_trim
	var trimmed_end := to - direction * end_trim
	var available_length := trimmed_start.distance_to(trimmed_end)
	var module_count := maxi(1, ceili(available_length / CORRIDOR_SOURCE_LENGTH))
	var module_length := available_length / float(module_count)
	var yaw := atan2(direction.x, direction.y)

	var edge_root := Node3D.new()
	edge_root.name = edge_name
	parent.add_child(edge_root)
	edge_root.set_meta("centerline_length", from.distance_to(to))
	edge_root.set_meta("module_count", module_count)

	for module_index: int in range(module_count):
		var distance_from_start := module_length * (float(module_index) + 0.5)
		var module_center := trimmed_start + direction * distance_from_start
		var module := CORRIDOR_MODULE.instantiate() as Node3D
		module.name = "Module%02d" % (module_index + 1)
		edge_root.add_child(module)
		module.position = _to_world(module_center)
		module.rotation.y = yaw
		module.call("configure", module_length)


func _add_junction(parent: Node3D, point: Vector2, junction_name: String) -> void:
	var junction := Node3D.new()
	junction.name = junction_name
	parent.add_child(junction)
	junction.position = _to_world(point)

	var floor := FLOOR_SQUARE.instantiate() as Node3D
	floor.name = "Floor"
	junction.add_child(floor)
	floor.scale = Vector3(JUNCTION_SURFACE_SIZE / 14.0, 1.0, JUNCTION_SURFACE_SIZE / 14.0)

	var ceiling := CEILING_SQUARE_WITH_LIGHT.instantiate() as Node3D
	ceiling.name = "Ceiling"
	junction.add_child(ceiling)
	ceiling.position.y = 6.31
	ceiling.scale = Vector3(JUNCTION_SURFACE_SIZE / 14.0, 1.0, JUNCTION_SURFACE_SIZE / 14.0)


func _add_elevator_terminal(parent: Node3D, door_point: Vector2, yaw: float) -> void:
	parent.position = _to_world(door_point)
	parent.rotation.y = yaw

	var elevator := ELEVATOR.instantiate() as Node3D
	elevator.name = "Elevator"
	parent.add_child(elevator)
	elevator.position = Vector3(0.0, 3.0, 4.28)

	var door := ELEVATOR_DOOR.instantiate() as Node3D
	door.name = "ElevatorDoor"
	parent.add_child(door)
	door.position = Vector3(0.636, 2.622, 1.549)


func _prune_candidate_group(room: Node, group_name: StringName) -> int:
	var candidates: Array[Node] = []
	for child: Node in room.find_children("*", "Node3D", true, false):
		if child.is_in_group(group_name):
			candidates.append(child)
	var keep_count := _rng.randi_range(0, candidates.size())
	_shuffle_with_rng(candidates)
	for remove_index: int in range(keep_count, candidates.size()):
		candidates[remove_index].free()
	return keep_count


func _analyze_turns(points: Array[Vector2]) -> Dictionary:
	var right_angle_turns := 0
	var has_diagonal_turn := false
	for point_index: int in range(1, points.size() - 1):
		var incoming := (points[point_index] - points[point_index - 1]).normalized()
		var outgoing := (points[point_index + 1] - points[point_index]).normalized()
		var turn_degrees := absf(rad_to_deg(acos(clampf(incoming.dot(outgoing), -1.0, 1.0))))
		if absf(turn_degrees - 90.0) < 0.1:
			right_angle_turns += 1
		elif turn_degrees > 0.1:
			has_diagonal_turn = true
	return {
		"right_angle_turns": right_angle_turns,
		"has_diagonal_turn": has_diagonal_turn,
	}


func _direction_from_yaw(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw)).normalized()


func _rotate_y_2d(value: Vector2, yaw: float) -> Vector2:
	var cosine := cos(yaw)
	var sine := sin(yaw)
	return Vector2(
		cosine * value.x + sine * value.y,
		-sine * value.x + cosine * value.y
	)


func _to_world(value: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(value.x, height, value.y)


func _segment_polygon(from: Vector2, to: Vector2, half_width: float) -> PackedVector2Array:
	var direction := (to - from).normalized()
	var normal := Vector2(-direction.y, direction.x) * half_width
	return PackedVector2Array([
		from + normal,
		to + normal,
		to - normal,
		from - normal,
	])


func _oriented_square_polygon(center: Vector2, half_size: float, yaw: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + _rotate_y_2d(Vector2(-half_size, -half_size), yaw),
		center + _rotate_y_2d(Vector2(half_size, -half_size), yaw),
		center + _rotate_y_2d(Vector2(half_size, half_size), yaw),
		center + _rotate_y_2d(Vector2(-half_size, half_size), yaw),
	])


func _polygons_overlap(first: PackedVector2Array, second: PackedVector2Array) -> bool:
	return not Geometry2D.intersect_polygons(first, second).is_empty()


func _shuffle_with_rng(values: Array) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary
