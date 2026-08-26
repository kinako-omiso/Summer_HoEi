extends Node3D


signal map_generated(seed_value: int)

const ROOM_COUNT := 6
const ROOM_SCENE_DIRECTORY := "res://components/rooms"
const GRID_SIZE := 3
const ROOM_HALF_SIZE := 7.0
const ROOM_WALL_OFFSET := 6.87
const ROOM_WALL_HEIGHT := 3.15
const CORRIDOR_SOURCE_LENGTH := 28.0
const MAX_LAYOUT_ATTEMPTS := 160
const DOOR_SWING_CLEARANCE := AABB(
	Vector3(-1.4, -3.2, -0.35),
	Vector3(2.8, 4.6, 2.9)
)

const SIDE_NORTH := "north"
const SIDE_EAST := "east"
const SIDE_SOUTH := "south"
const SIDE_WEST := "west"
const ALL_SIDES: Array[String] = [SIDE_NORTH, SIDE_EAST, SIDE_SOUTH, SIDE_WEST]
const SIDE_VECTORS := {
	SIDE_NORTH: Vector2(0.0, -1.0),
	SIDE_EAST: Vector2(1.0, 0.0),
	SIDE_SOUTH: Vector2(0.0, 1.0),
	SIDE_WEST: Vector2(-1.0, 0.0),
}

const CORRIDOR_MODULE := preload("res://components/map/corridor_module.tscn")
const ROOM_WALL := preload("res://assets/3DModel/wall_no_door.tscn")
const CENTERED_DOOR_WALL := preload("res://components/map/centered_wall_with_door.tscn")
const ELEVATOR := preload("res://assets/3DModel/elevator.tscn")
const ELEVATOR_DOOR := preload("res://assets/3DModel/elevator_door.tscn")

@export_range(3.0, 20.0, 0.5) var minimum_corridor_length := 3.0
@export_range(3.0, 20.0, 0.5) var maximum_corridor_length := 20.0
@export_range(0.0, 1.0, 0.05) var extra_connection_chance := 0.45
@export_range(0.0, 1.0, 0.05) var door_spawn_chance := 0.5
@export var seed_override: int = 0

var generated_seed: int = 0
var generated_door_count: int = 0
var player_spawn_position := Vector3.ZERO
var robot_spawn_position := Vector3.ZERO
var last_layout: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _room_scene_paths: Array[String] = []
var _room_scenes_by_path: Dictionary = {}


func generate_map(requested_seed: int = 0) -> bool:
	_clear_generated_map()
	if not _refresh_room_scene_paths():
		return false
	_configure_rng(requested_seed)
	var layout := _build_valid_layout()
	if layout.is_empty():
		push_error("MapGenerator could not create a compact connected map after %d attempts." % MAX_LAYOUT_ATTEMPTS)
		return false
	last_layout = layout
	_instantiate_layout(layout)
	map_generated.emit(generated_seed)
	return true


func generate_layout_for_seed(test_seed: int) -> Dictionary:
	if not _refresh_room_scene_paths():
		return {}
	_configure_rng(test_seed)
	return _build_valid_layout()


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
	generated_door_count = 0


func _build_valid_layout() -> Dictionary:
	for _attempt: int in range(MAX_LAYOUT_ATTEMPTS):
		var layout := _try_build_compact_layout()
		if not layout.is_empty():
			return layout
	return {}


func _try_build_compact_layout() -> Dictionary:
	var cells := _grow_connected_cells()
	var connections := _select_room_connections(cells)
	if connections.size() < ROOM_COUNT - 1:
		return {}

	var column_gaps: Array[float] = [
		_rng.randf_range(minimum_corridor_length, maximum_corridor_length),
		_rng.randf_range(minimum_corridor_length, maximum_corridor_length),
	]
	var row_gaps: Array[float] = [
		_rng.randf_range(minimum_corridor_length, maximum_corridor_length),
		_rng.randf_range(minimum_corridor_length, maximum_corridor_length),
	]
	var column_positions := _grid_axis_positions(column_gaps)
	var row_positions := _grid_axis_positions(row_gaps)

	var room_specs: Array[Dictionary] = []
	for cell: Vector2i in cells:
		var scene_path := _room_scene_paths[_rng.randi_range(0, _room_scene_paths.size() - 1)]
		var scene_id := scene_path.get_file().get_basename()
		room_specs.append({
			"cell": cell,
			"origin": Vector2(column_positions[cell.x], row_positions[cell.y]),
			"scene_path": scene_path,
			"scene_id": scene_id,
			"type": scene_id.substr(5, 1).to_upper(),
			"entrances": [] as Array[String],
			"elevator_side": "",
		})

	var corridor_specs: Array[Dictionary] = []
	for connection: Dictionary in connections:
		var first_index: int = connection["first"]
		var second_index: int = connection["second"]
		var first_cell: Vector2i = cells[first_index]
		var second_cell: Vector2i = cells[second_index]
		var sides := _connection_sides(first_cell, second_cell)
		var first_side: String = sides[0]
		var second_side: String = sides[1]
		var first_entrances: Array = room_specs[first_index]["entrances"]
		var second_entrances: Array = room_specs[second_index]["entrances"]
		first_entrances.append(first_side)
		second_entrances.append(second_side)

		var first_origin: Vector2 = room_specs[first_index]["origin"]
		var second_origin: Vector2 = room_specs[second_index]["origin"]
		var start := first_origin + _side_vector(first_side) * ROOM_WALL_OFFSET
		var end := second_origin + _side_vector(second_side) * ROOM_WALL_OFFSET
		corridor_specs.append({
			"from": start,
			"to": end,
			"length": start.distance_to(end),
			"first_room": first_index,
			"second_room": second_index,
		})

	var elevator_attachment := _choose_elevator_attachment(cells, room_specs)
	if elevator_attachment.is_empty():
		return {}
	var elevator_room_index: int = elevator_attachment["room_index"]
	var elevator_side: String = elevator_attachment["side"]
	var elevator_entrances: Array = room_specs[elevator_room_index]["entrances"]
	elevator_entrances.append(elevator_side)
	room_specs[elevator_room_index]["elevator_side"] = elevator_side

	return {
		"seed": generated_seed,
		"cells": cells,
		"rooms": room_specs,
		"corridors": corridor_specs,
		"connections": connections,
		"elevator_mode": "room",
		"elevator_room_index": elevator_room_index,
		"elevator_side": elevator_side,
	}


func _grow_connected_cells() -> Array[Vector2i]:
	var occupied: Array[Vector2i] = [
		Vector2i(_rng.randi_range(0, GRID_SIZE - 1), _rng.randi_range(0, GRID_SIZE - 1))
	]
	while occupied.size() < ROOM_COUNT:
		var candidates: Array[Vector2i] = []
		for cell: Vector2i in occupied:
			for offset: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var candidate := cell + offset
				if _cell_is_inside_grid(candidate) and not occupied.has(candidate) and not candidates.has(candidate):
					candidates.append(candidate)
		if candidates.is_empty():
			return []
		occupied.append(candidates[_rng.randi_range(0, candidates.size() - 1)])
	return occupied


func _select_room_connections(cells: Array[Vector2i]) -> Array[Dictionary]:
	var cell_indices: Dictionary = {}
	for room_index: int in range(cells.size()):
		cell_indices[cells[room_index]] = room_index

	var candidate_edges: Array[Dictionary] = []
	for room_index: int in range(cells.size()):
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor := cells[room_index] + offset
			if cell_indices.has(neighbor):
				candidate_edges.append({
					"first": room_index,
					"second": int(cell_indices[neighbor]),
				})
	_shuffle_with_rng(candidate_edges)

	var parents: Array[int] = []
	var degrees: Array[int] = []
	for room_index: int in range(cells.size()):
		parents.append(room_index)
		degrees.append(0)

	var selected: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	for edge: Dictionary in candidate_edges:
		var first: int = edge["first"]
		var second: int = edge["second"]
		if _find_set(parents, first) != _find_set(parents, second) and degrees[first] < 3 and degrees[second] < 3:
			_union_sets(parents, first, second)
			degrees[first] += 1
			degrees[second] += 1
			selected.append(edge)
		else:
			remaining.append(edge)
	if selected.size() != ROOM_COUNT - 1:
		return []

	_shuffle_with_rng(remaining)
	for edge: Dictionary in remaining:
		var first: int = edge["first"]
		var second: int = edge["second"]
		if degrees[first] >= 3 or degrees[second] >= 3:
			continue
		if _rng.randf() <= extra_connection_chance:
			degrees[first] += 1
			degrees[second] += 1
			selected.append(edge)
	return selected


func _choose_elevator_attachment(cells: Array[Vector2i], room_specs: Array[Dictionary]) -> Dictionary:
	var occupied: Dictionary = {}
	for cell: Vector2i in cells:
		occupied[cell] = true

	var candidates: Array[Dictionary] = []
	for room_index: int in range(room_specs.size()):
		var entrances: Array = room_specs[room_index]["entrances"]
		if entrances.size() >= 3:
			continue
		var cell: Vector2i = cells[room_index]
		for side: String in ALL_SIDES:
			if entrances.has(side):
				continue
			var neighbor_cell := cell + _side_grid_offset(side)
			if not _cell_is_inside_grid(neighbor_cell) or not occupied.has(neighbor_cell):
				candidates.append({"room_index": room_index, "side": side})
	if candidates.is_empty():
		return {}
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _grid_axis_positions(gaps: Array[float]) -> Array[float]:
	var positions: Array[float] = [0.0]
	for gap: float in gaps:
		positions.append(positions[-1] + ROOM_WALL_OFFSET * 2.0 + gap)
	var center := (positions[0] + positions[-1]) * 0.5
	for index: int in range(positions.size()):
		positions[index] -= center
	return positions


func _connection_sides(first: Vector2i, second: Vector2i) -> Array[String]:
	var delta := second - first
	if delta == Vector2i.RIGHT:
		return [SIDE_EAST, SIDE_WEST]
	if delta == Vector2i.LEFT:
		return [SIDE_WEST, SIDE_EAST]
	if delta == Vector2i.DOWN:
		return [SIDE_SOUTH, SIDE_NORTH]
	return [SIDE_NORTH, SIDE_SOUTH]


func _instantiate_layout(layout: Dictionary) -> void:
	var corridors_root := Node3D.new()
	corridors_root.name = "Corridors"
	add_child(corridors_root)
	var rooms_root := Node3D.new()
	rooms_root.name = "Rooms"
	add_child(rooms_root)
	var elevator_root := Node3D.new()
	elevator_root.name = "ElevatorTerminal"
	add_child(elevator_root)

	var corridors: Array = layout["corridors"]
	for corridor_index: int in range(corridors.size()):
		var corridor: Dictionary = corridors[corridor_index]
		_add_corridor_edge(
			corridors_root,
			corridor["from"],
			corridor["to"],
			"RoomConnection%02d" % (corridor_index + 1)
		)

	var room_instances: Array[Node3D] = []
	var room_specs: Array = layout["rooms"]
	for room_index: int in range(room_specs.size()):
		var room_spec: Dictionary = room_specs[room_index]
		var room_scene: PackedScene = _room_scenes_by_path[room_spec["scene_path"]] as PackedScene
		var room := room_scene.instantiate() as Node3D
		room.name = "Room%02d_%s" % [room_index + 1, room_spec["scene_id"]]
		rooms_root.add_child(room)
		var origin: Vector2 = room_spec["origin"]
		room.position = _to_world(origin)
		var entrances: Array = room_spec["entrances"]
		var elevator_side: String = room_spec["elevator_side"]
		_remove_fixed_entrance_obstructions(room, entrances)
		var candidate_counts := {
			"desks": _prune_candidate_group(room, &"random_desk_monitor_candidates"),
			"plants": _prune_candidate_group(room, &"random_plant_candidates"),
			"lockers": _prune_candidate_group(room, &"random_locker_candidates"),
		}
		var door_report := _configure_room_walls(room, entrances, elevator_side)
		room.set_meta("generated_room_type", room_spec["type"])
		room.set_meta("generated_room_scene", room_spec["scene_path"])
		room.set_meta("generated_entrance_count", entrances.size())
		room.set_meta("generated_entrance_sides", entrances.duplicate())
		room.set_meta("generated_candidate_counts", candidate_counts)
		room.set_meta("generated_door_sides", door_report["doors"])
		room.set_meta("generated_open_entrance_sides", door_report["open"])
		room.set_meta("generated_obstructed_door_sides", door_report["obstructed"])
		room_instances.append(room)

	_ensure_at_least_one_generated_door(room_instances, room_specs)
	generated_door_count = _count_generated_doors(room_instances)

	var elevator_room_index: int = layout["elevator_room_index"]
	var elevator_side: String = layout["elevator_side"]
	var target_origin: Vector2 = room_specs[elevator_room_index]["origin"]
	var outward := _side_vector(elevator_side)
	var elevator_door_point := target_origin + outward * ROOM_WALL_OFFSET
	_add_elevator_terminal(elevator_root, elevator_door_point, _yaw_from_direction(outward))

	player_spawn_position = room_instances[0].global_position + Vector3(0.0, 0.45, 0.0)
	robot_spawn_position = room_instances[-1].global_position + Vector3(0.0, 0.45, 0.0)


func _configure_room_walls(room: Node3D, entrances: Array, elevator_side: String) -> Dictionary:
	var structure := room.get_node("Structure") as Node3D
	var door_sides: Array[String] = []
	var open_sides: Array[String] = []
	var obstructed_sides: Array[String] = []

	for side: String in ALL_SIDES:
		var authored_wall_name := "Wall%s" % side.capitalize()
		var authored_wall := structure.get_node_or_null(authored_wall_name) as Node3D
		var wall: Node3D = null
		if entrances.has(side):
			# Only an entrance side must replace authored content. Solid walls keep
			# every saved transform, material override, and custom child node.
			if authored_wall != null:
				authored_wall.free()
			wall = CENTERED_DOOR_WALL.instantiate() as Node3D
			wall.name = "Entrance%s" % side.capitalize()
		elif authored_wall == null:
			# Templates may intentionally omit one side. Fill it only when the
			# generated layout needs that side to be solid.
			wall = ROOM_WALL.instantiate() as Node3D
			wall.name = authored_wall_name
		if wall == null:
			continue
		_apply_wall_transform(wall, side)
		# AnimatableBody3D children synchronize their global transform when they
		# enter the tree. Set the wall transform first so doors do not remain at
		# the room origin (and below the floor) when the wall is moved afterward.
		structure.add_child(wall)
		if not entrances.has(side):
			continue
		if side == elevator_side:
			_remove_door_from_entrance(wall)
			open_sides.append(side)
			continue
		var swing_is_blocked := _door_swing_is_blocked(room, wall)
		if swing_is_blocked or _rng.randf() > door_spawn_chance:
			_remove_door_from_entrance(wall)
			open_sides.append(side)
			if swing_is_blocked:
				obstructed_sides.append(side)
		else:
			door_sides.append(side)

	return {
		"doors": door_sides,
		"open": open_sides,
		"obstructed": obstructed_sides,
	}


func _remove_fixed_entrance_obstructions(room: Node3D, entrances: Array) -> void:
	if entrances.has(SIDE_SOUTH):
		var center_locker := room.get_node_or_null("RandomLockerCandidates/Locker03")
		if center_locker != null:
			center_locker.free()
	_relocate_breaker(room, entrances)


func _remove_door_from_entrance(wall: Node3D) -> void:
	var interactive_door := wall.get_node_or_null("InteractiveDoor")
	if interactive_door != null:
		interactive_door.free()
	var navigation_link := wall.get_node_or_null("NavigationLink3D")
	if navigation_link != null:
		navigation_link.free()


func _ensure_at_least_one_generated_door(
	room_instances: Array[Node3D],
	room_specs: Array,
) -> void:
	if _count_generated_doors(room_instances) > 0:
		return

	var safe_candidates: Array[Dictionary] = []
	for room_index: int in range(room_instances.size()):
		var room := room_instances[room_index]
		var open_sides: Array = room.get_meta("generated_open_entrance_sides", [])
		var obstructed_sides: Array = room.get_meta("generated_obstructed_door_sides", [])
		var elevator_side: String = room_specs[room_index]["elevator_side"]
		for side: String in open_sides:
			if side != elevator_side and not obstructed_sides.has(side):
				safe_candidates.append({"room": room, "side": side})
	if safe_candidates.is_empty():
		return

	var selected: Dictionary = safe_candidates[_rng.randi_range(0, safe_candidates.size() - 1)]
	var room: Node3D = selected["room"]
	var side: String = selected["side"]
	var structure := room.get_node("Structure") as Node3D
	var entrance_name := "Entrance%s" % side.capitalize()
	var open_wall := structure.get_node_or_null(entrance_name)
	if open_wall != null:
		open_wall.free()
	var door_wall := CENTERED_DOOR_WALL.instantiate() as Node3D
	door_wall.name = entrance_name
	_apply_wall_transform(door_wall, side)
	structure.add_child(door_wall)

	var open_sides: Array = room.get_meta("generated_open_entrance_sides", [])
	var door_sides: Array = room.get_meta("generated_door_sides", [])
	open_sides.erase(side)
	door_sides.append(side)
	room.set_meta("generated_open_entrance_sides", open_sides)
	room.set_meta("generated_door_sides", door_sides)
	room.set_meta("generated_minimum_door_fallback", true)


func _count_generated_doors(room_instances: Array[Node3D]) -> int:
	var door_count := 0
	for room: Node3D in room_instances:
		var door_sides: Array = room.get_meta("generated_door_sides", [])
		door_count += door_sides.size()
	return door_count


func _door_swing_is_blocked(room: Node3D, entrance_wall: Node3D) -> bool:
	var structure := room.get_node("Structure")
	for node: Node in room.find_children("*", "CollisionShape3D", true, false):
		var collision_shape := node as CollisionShape3D
		if collision_shape == null or collision_shape.disabled or collision_shape.shape == null:
			continue
		if structure.is_ancestor_of(collision_shape):
			continue
		var debug_mesh := collision_shape.shape.get_debug_mesh()
		if debug_mesh == null:
			continue
		var shape_to_wall := entrance_wall.global_transform.affine_inverse() * collision_shape.global_transform
		var wall_space_bounds: AABB = shape_to_wall * debug_mesh.get_aabb()
		if DOOR_SWING_CLEARANCE.intersects(wall_space_bounds):
			return true
	return false


func _apply_wall_transform(wall: Node3D, side: String) -> void:
	wall.position.y = ROOM_WALL_HEIGHT
	match side:
		SIDE_NORTH:
			wall.position.z = -ROOM_WALL_OFFSET
			wall.rotation.y = 0.0
		SIDE_EAST:
			wall.position.x = ROOM_WALL_OFFSET
			wall.rotation.y = -PI * 0.5
		SIDE_SOUTH:
			wall.position.z = ROOM_WALL_OFFSET
			wall.rotation.y = PI
		SIDE_WEST:
			wall.position.x = -ROOM_WALL_OFFSET
			wall.rotation.y = PI * 0.5


func _relocate_breaker(room: Node3D, entrances: Array) -> void:
	var breaker := room.get_node_or_null("Breaker") as Node3D
	if breaker == null:
		return
	var original_side := _side_from_room_position(breaker.position)
	# Preserve the room author's complete Transform when its mounting wall is
	# still solid. Previously every generated room overwrote the authored yaw.
	if not entrances.has(original_side):
		return
	var solid_side := SIDE_NORTH
	for side: String in ALL_SIDES:
		if not entrances.has(side):
			solid_side = side
			break
	var preserved_y := breaker.position.y
	var yaw_delta := _canonical_breaker_yaw(solid_side) - _canonical_breaker_yaw(original_side)
	match solid_side:
		SIDE_NORTH:
			breaker.position = Vector3(4.8, preserved_y, -6.62)
		SIDE_EAST:
			breaker.position = Vector3(6.62, preserved_y, 4.8)
		SIDE_SOUTH:
			breaker.position = Vector3(4.8, preserved_y, 6.62)
		SIDE_WEST:
			breaker.position = Vector3(-6.62, preserved_y, 4.8)
	breaker.rotation.y = wrapf(breaker.rotation.y + yaw_delta, -PI, PI)


func _side_from_room_position(position: Vector3) -> String:
	if absf(position.x) > absf(position.z):
		return SIDE_EAST if position.x >= 0.0 else SIDE_WEST
	return SIDE_SOUTH if position.z >= 0.0 else SIDE_NORTH


func _canonical_breaker_yaw(side: String) -> float:
	match side:
		SIDE_EAST:
			return -PI * 0.5
		SIDE_SOUTH:
			return PI
		SIDE_WEST:
			return PI * 0.5
	return 0.0


func _add_corridor_edge(parent: Node3D, from: Vector2, to: Vector2, edge_name: String) -> void:
	var length := from.distance_to(to)
	var direction := (to - from).normalized()
	var center := from.lerp(to, 0.5)
	var module := CORRIDOR_MODULE.instantiate() as Node3D
	module.name = edge_name
	parent.add_child(module)
	module.position = _to_world(center)
	module.rotation.y = _yaw_from_direction(direction)
	module.call("configure", length)
	module.set_meta("centerline_length", length)


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
	door.position = Vector3(0.0, 2.622, 0.0)


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


func _find_set(parents: Array[int], value: int) -> int:
	var root := value
	while parents[root] != root:
		root = parents[root]
	var current := value
	while parents[current] != current:
		var next := parents[current]
		parents[current] = root
		current = next
	return root


func get_available_room_scene_paths() -> Array[String]:
	if _room_scene_paths.is_empty():
		_refresh_room_scene_paths()
	return _room_scene_paths.duplicate()


func _refresh_room_scene_paths() -> bool:
	_room_scene_paths.clear()
	_room_scenes_by_path.clear()
	var directory: DirAccess = DirAccess.open(ROOM_SCENE_DIRECTORY)
	if directory == null:
		push_error("MapGenerator cannot open %s." % ROOM_SCENE_DIRECTORY)
		return false

	var filenames := directory.get_files()
	filenames.sort()
	for filename: String in filenames:
		if not _is_room_scene_filename(filename):
			continue
		var scene_path := "%s/%s" % [ROOM_SCENE_DIRECTORY, filename]
		# Reload the saved scene and all of its external dependencies for every
		# map generation. This bypasses stale ResourceLoader cache entries during
		# an editor play session without requiring a project restart.
		var resource: Resource = ResourceLoader.load(
			scene_path,
			"PackedScene",
			ResourceLoader.CACHE_MODE_REPLACE_DEEP
		)
		if not resource is PackedScene:
			push_warning("Skipping room scene that cannot be loaded: %s" % scene_path)
			continue
		var preview: Node = (resource as PackedScene).instantiate()
		var is_compatible := preview is Node3D and preview.has_node("Structure")
		preview.free()
		if not is_compatible:
			push_warning("Skipping room scene without a Node3D root and Structure child: %s" % scene_path)
			continue
		_room_scene_paths.append(scene_path)
		_room_scenes_by_path[scene_path] = resource as PackedScene

	if _room_scene_paths.is_empty():
		push_error(
			"MapGenerator found no compatible room_[letter]_[name].tscn scenes in %s."
			% ROOM_SCENE_DIRECTORY
		)
		return false
	return true


func _is_room_scene_filename(filename: String) -> bool:
	if not filename.ends_with(".tscn"):
		return false
	var scene_id := filename.get_basename()
	if not scene_id.begins_with("room_") or scene_id.length() < 8:
		return false
	var category := scene_id.substr(5, 1)
	if scene_id.substr(6, 1) != "_":
		return false
	var category_code := category.unicode_at(0)
	var is_ascii_letter := (
		(category_code >= 65 and category_code <= 90)
		or (category_code >= 97 and category_code <= 122)
	)
	return is_ascii_letter and scene_id.substr(7).length() > 0


func _union_sets(parents: Array[int], first: int, second: int) -> void:
	var first_root := _find_set(parents, first)
	var second_root := _find_set(parents, second)
	parents[second_root] = first_root


func _cell_is_inside_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_SIZE and cell.y >= 0 and cell.y < GRID_SIZE


func _side_vector(side: String) -> Vector2:
	return SIDE_VECTORS[side]


func _side_grid_offset(side: String) -> Vector2i:
	var direction := _side_vector(side)
	return Vector2i(int(direction.x), int(direction.y))


func _yaw_from_direction(direction: Vector2) -> float:
	return atan2(direction.x, direction.y)


func _to_world(value: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(value.x, height, value.y)


func _shuffle_with_rng(values: Array) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary
