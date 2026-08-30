extends Node3D


signal map_generated(seed_value: int)

const ROOM_COUNT := 6
const ROOM_SCENE_DIRECTORY := "res://components/rooms"
const MAP_BREAKER_GROUP := &"map_breaker"
const RANDOM_CANDIDATE_GROUPS := {
	"desks": &"random_desk_monitor_candidates",
	"plants": &"random_plant_candidates",
	"lockers": &"random_locker_candidates",
	"pillars": &"pillar",
}
const GRID_SIZE := 3
const ROOM_HALF_SIZE := 7.0
const ROOM_WALL_OFFSET := 6.87
const ROOM_WALL_HEIGHT := 3.15
const CORRIDOR_SOURCE_LENGTH := 28.0
const FLOOR_EMISSION_COLOR := Color(0.38, 0.46, 0.56)
const FLOOR_EMISSION_ENERGY := 0.10
const WALL_EMISSION_COLOR := Color(0.55, 0.62, 0.72)
const WALL_EMISSION_ENERGY := 0.16
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

const CORRIDOR_HALF_WIDTH := 3.87
const ELEVATOR_FOOTPRINT_WIDTH := 3.532126
const ELEVATOR_OPENING_WIDTH := 2.683478
const CORRIDOR_SIDE_LEFT := "left"
const CORRIDOR_SIDE_RIGHT := "right"
const CORRIDOR_MODULE := preload("res://components/map/corridor_module.tscn")
const CORRIDOR_CEILING_NORMAL := preload(
	"res://assets/3DModel/corridor_ceiling_without_light.tscn"
)
const CORRIDOR_CEILING_WITH_LIGHT := preload(
	"res://assets/3DModel/corridor_ceiling.tscn"
)
const ROOM_CEILING_NORMAL := preload("res://assets/3DModel/ceiling_square.tscn")
const ROOM_CEILING_WITH_LIGHT := preload(
	"res://assets/3DModel/ceiling_square_with_light.tscn"
)
const ROOM_WALL := preload("res://assets/3DModel/wall_no_door.tscn")
const CENTERED_DOOR_WALL := preload("res://components/map/centered_wall_with_door.tscn")
const ELEVATOR_ENTRANCE_WALL := preload(
	"res://components/map/centered_wall_with_elevator_door.tscn"
)
const ELEVATOR := preload("res://assets/3DModel/elevator.tscn")
const ELEVATOR_DOOR := preload("res://assets/3DModel/elevator_door.tscn")
const ELEVATOR_LIGHT_POSITION := Vector3(0.0, 2.45, -2.28)
const CEILING_LIGHT_ENERGY := 4.0
const CEILING_LIGHT_RANGE := 10.0
const CEILING_LIGHT_ATTENUATION := 1.25

@export_range(3.0, 20.0, 0.5) var minimum_corridor_length := 3.0
@export_range(3.0, 20.0, 0.5) var maximum_corridor_length := 20.0
@export_range(0.0, 1.0, 0.05) var extra_connection_chance := 0.45
@export_range(0.0, 1.0, 0.05) var door_spawn_chance := 0.5
@export var seed_override: int = 0

var generated_seed: int = 0
var generated_door_count: int = 0
var player_spawn_position := Vector3.ZERO
var player_spawn_yaw := 0.0
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
	player_spawn_position = Vector3.ZERO
	player_spawn_yaw = 0.0
	robot_spawn_position = Vector3.ZERO


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
	var selected_room_scene_paths := _select_room_scene_paths()

	var room_specs: Array[Dictionary] = []
	for room_index: int in range(cells.size()):
		var cell: Vector2i = cells[room_index]
		var scene_path := selected_room_scene_paths[room_index]
		var scene_id := scene_path.get_file().get_basename()
		room_specs.append({
			"cell": cell,
			"origin": Vector2(column_positions[cell.x], row_positions[cell.y]),
			"scene_path": scene_path,
			"scene_id": scene_id,
			"type": scene_id.substr(5, 1).to_upper(),
			"entrances": [] as Array[String],
			"elevator_side": "",
			"elevator_role": "",
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
			"first_side": first_side,
			"second_side": second_side,
			"elevator_side": "",
			"elevator_role": "",
		})

	var elevator_attachments := _choose_elevator_attachments(
		cells,
		room_specs,
		corridor_specs,
	)
	if elevator_attachments.is_empty():
		return {}
	var start_elevator: Dictionary = elevator_attachments["start"]
	var goal_elevator: Dictionary = elevator_attachments["goal"]
	for role: String in ["start", "goal"]:
		var attachment: Dictionary = elevator_attachments[role]
		if attachment["mode"] == "room":
			var room_index: int = attachment["room_index"]
			var elevator_side: String = attachment["side"]
			var elevator_entrances: Array = room_specs[room_index]["entrances"]
			elevator_entrances.append(elevator_side)
			room_specs[room_index]["elevator_side"] = elevator_side
			room_specs[room_index]["elevator_role"] = role
		else:
			var corridor_index: int = attachment["corridor_index"]
			corridor_specs[corridor_index]["elevator_side"] = attachment["side"]
			corridor_specs[corridor_index]["elevator_role"] = role

	return {
		"seed": generated_seed,
		"cells": cells,
		"rooms": room_specs,
		"corridors": corridor_specs,
		"connections": connections,
		"start_elevator": start_elevator,
		"goal_elevator": goal_elevator,
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


func _choose_elevator_attachments(
	cells: Array[Vector2i],
	room_specs: Array[Dictionary],
	corridor_specs: Array[Dictionary],
) -> Dictionary:
	var occupied: Dictionary = {}
	for cell: Vector2i in cells:
		occupied[cell] = true

	var candidates: Array[Dictionary] = []
	for room_index: int in range(room_specs.size()):
		var entrances: Array = room_specs[room_index]["entrances"]
		if entrances.size() >= 3:
			continue
		var cell: Vector2i = cells[room_index]
		var room_origin: Vector2 = room_specs[room_index]["origin"]
		for side: String in ALL_SIDES:
			if entrances.has(side):
				continue
			var neighbor_cell := cell + _side_grid_offset(side)
			if not _cell_is_inside_grid(neighbor_cell) or not occupied.has(neighbor_cell):
				var outward := _side_vector(side)
				candidates.append({
					"mode": "room",
					"room_index": room_index,
					"side": side,
					"host_key": "room:%d" % room_index,
					"position": room_origin + outward * ROOM_WALL_OFFSET,
				})

	for corridor_index: int in range(corridor_specs.size()):
		var corridor: Dictionary = corridor_specs[corridor_index]
		var corridor_length: float = corridor["length"]
		# A short corridor cannot contain the full elevator footprint. Reject
		# it here and let selection retry with another candidate.
		if corridor_length + 0.001 < ELEVATOR_FOOTPRINT_WIDTH:
			continue
		var from: Vector2 = corridor["from"]
		var to: Vector2 = corridor["to"]
		var direction := (to - from).normalized()
		var center := from.lerp(to, 0.5)
		var right := Vector2(direction.y, -direction.x)
		for side: String in [CORRIDOR_SIDE_LEFT, CORRIDOR_SIDE_RIGHT]:
			var outward := -right if side == CORRIDOR_SIDE_LEFT else right
			candidates.append({
				"mode": "corridor",
				"corridor_index": corridor_index,
				"side": side,
				"host_key": "corridor:%d" % corridor_index,
				"position": center + outward * CORRIDOR_HALF_WIDTH,
			})

	if candidates.size() < 2:
		return {}

	var start_mode := "corridor" if _rng.randi_range(0, 1) == 1 else "room"
	var start_options := _filter_elevator_candidates(candidates, start_mode, "")
	if start_options.is_empty():
		start_options = candidates.duplicate()
	var start: Dictionary = start_options[_rng.randi_range(0, start_options.size() - 1)]

	var goal_mode := "corridor" if _rng.randi_range(0, 1) == 1 else "room"
	var goal_options := _filter_elevator_candidates(
		candidates,
		goal_mode,
		start["host_key"],
	)
	if goal_options.is_empty():
		goal_options = _filter_elevator_candidates(candidates, "", start["host_key"])
	if goal_options.is_empty():
		return {}

	var farthest_options: Array[Dictionary] = []
	var farthest_distance_squared := -1.0
	var start_position: Vector2 = start["position"]
	for candidate: Dictionary in goal_options:
		var candidate_position: Vector2 = candidate["position"]
		var distance_squared := start_position.distance_squared_to(candidate_position)
		if distance_squared > farthest_distance_squared + 0.001:
			farthest_distance_squared = distance_squared
			farthest_options = [candidate]
		elif is_equal_approx(distance_squared, farthest_distance_squared):
			farthest_options.append(candidate)
	var goal: Dictionary = farthest_options[
		_rng.randi_range(0, farthest_options.size() - 1)
	]
	return {"start": start, "goal": goal}


func _filter_elevator_candidates(
	candidates: Array[Dictionary],
	preferred_mode: String,
	excluded_host: String,
) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if not excluded_host.is_empty() and candidate["host_key"] == excluded_host:
			continue
		if not preferred_mode.is_empty() and candidate["mode"] != preferred_mode:
			continue
		filtered.append(candidate)
	return filtered


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
	var start_elevator_root := Node3D.new()
	start_elevator_root.name = "StartElevatorTerminal"
	add_child(start_elevator_root)
	var goal_elevator_root := Node3D.new()
	goal_elevator_root.name = "GoalElevatorTerminal"
	add_child(goal_elevator_root)

	var corridors: Array = layout["corridors"]
	var corridor_light_variants := _build_corridor_light_variants(corridors.size())
	var unlit_corridor_sides_by_room: Dictionary = {}
	for room_index: int in range(layout["rooms"].size()):
		unlit_corridor_sides_by_room[room_index] = [] as Array[String]
	for corridor_index: int in range(corridors.size()):
		var corridor: Dictionary = corridors[corridor_index]
		if not corridor_light_variants[corridor_index]:
			var first_sides: Array = unlit_corridor_sides_by_room[corridor["first_room"]]
			var second_sides: Array = unlit_corridor_sides_by_room[corridor["second_room"]]
			first_sides.append(corridor["first_side"])
			second_sides.append(corridor["second_side"])
		_add_corridor_edge(
			corridors_root,
			corridor["from"],
			corridor["to"],
			"RoomConnection%02d" % (corridor_index + 1),
			corridor_light_variants[corridor_index],
			corridor["elevator_side"],
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
		_randomize_room_ceiling(room)
		var entrances: Array = room_spec["entrances"]
		var elevator_side: String = room_spec["elevator_side"]
		_remove_fixed_entrance_obstructions(room, entrances)
		var candidate_counts := _prune_room_candidates(room)
		var door_report := _configure_room_walls(room, entrances, elevator_side)
		var room_has_lights: bool = (
			room.get_meta("generated_ceiling_variant", "") == "with_light"
		)
		if not room_has_lights:
			_make_room_walls_dimly_emissive(room)
		else:
			_make_room_entrance_walls_dimly_emissive(
				room,
				unlit_corridor_sides_by_room[room_index],
			)
		room.set_meta("wall_is_emissive", not room_has_lights)
		room.set_meta(
			"generated_unlit_corridor_sides",
			unlit_corridor_sides_by_room[room_index].duplicate(),
		)
		room.set_meta("generated_room_type", room_spec["type"])
		room.set_meta("generated_room_scene", room_spec["scene_path"])
		room.set_meta("generated_entrance_count", entrances.size())
		room.set_meta("generated_entrance_sides", entrances.duplicate())
		room.set_meta("generated_candidate_counts", candidate_counts)
		room.set_meta("generated_door_sides", door_report["doors"])
		room.set_meta("generated_open_entrance_sides", door_report["open"])
		room.set_meta("generated_obstructed_door_sides", door_report["obstructed"])
		room_instances.append(room)

	_keep_one_map_breaker(room_instances)
	_ensure_at_least_one_generated_door(room_instances, room_specs)
	generated_door_count = _count_generated_doors(room_instances)

	_add_layout_elevator(layout, room_specs, start_elevator_root, "start")
	_add_layout_elevator(layout, room_specs, goal_elevator_root, "goal")

	# The terminal-local positive Z axis points into the elevator enclosure.
	player_spawn_position = (
		start_elevator_root.global_transform * Vector3(0.0, 0.45, 2.6)
	)
	player_spawn_yaw = start_elevator_root.global_rotation.y
	var goal_attachment: Dictionary = layout["goal_elevator"]
	var goal_room_index: int
	if goal_attachment["mode"] == "room":
		goal_room_index = goal_attachment["room_index"]
	else:
		var goal_corridor: Dictionary = layout["corridors"][
			goal_attachment["corridor_index"]
		]
		goal_room_index = goal_corridor["second_room"]
	robot_spawn_position = (
		room_instances[goal_room_index].global_position + Vector3(0.0, 0.45, 0.0)
	)


func _add_layout_elevator(
	layout: Dictionary,
	room_specs: Array,
	terminal_root: Node3D,
	role: String,
) -> void:
	var attachment: Dictionary = layout["%s_elevator" % role]
	var outward: Vector2
	var elevator_door_point: Vector2
	if attachment["mode"] == "room":
		var room_index: int = attachment["room_index"]
		var side: String = attachment["side"]
		var target_origin: Vector2 = room_specs[room_index]["origin"]
		outward = _side_vector(side)
		elevator_door_point = target_origin + outward * ROOM_WALL_OFFSET
	else:
		var corridor: Dictionary = layout["corridors"][attachment["corridor_index"]]
		var from: Vector2 = corridor["from"]
		var to: Vector2 = corridor["to"]
		var direction := (to - from).normalized()
		var center := from.lerp(to, 0.5)
		var right := Vector2(direction.y, -direction.x)
		outward = (
			-right
			if attachment["side"] == CORRIDOR_SIDE_LEFT
			else right
		)
		elevator_door_point = center + outward * CORRIDOR_HALF_WIDTH
	_add_elevator_terminal(
		terminal_root,
		elevator_door_point,
		_yaw_from_direction(outward),
		role,
	)


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
			var entrance_scene := (
				ELEVATOR_ENTRANCE_WALL if side == elevator_side else CENTERED_DOOR_WALL
			)
			wall = entrance_scene.instantiate() as Node3D
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


func _keep_one_map_breaker(room_instances: Array[Node3D]) -> void:
	var breakers: Array[Node3D] = []
	for room: Node3D in room_instances:
		var breaker := _find_room_breaker(room)
		if breaker != null:
			breakers.append(breaker)
	if breakers.size() <= 1:
		return

	var kept_breaker_index := _rng.randi_range(0, breakers.size() - 1)
	for breaker_index: int in range(breakers.size()):
		if breaker_index != kept_breaker_index:
			breakers[breaker_index].free()


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
	var breaker := _find_room_breaker(room)
	if breaker == null:
		return
	if not breaker.get_meta("wall_mounted", true):
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


func _find_room_breaker(room: Node3D) -> Node3D:
	for child: Node in room.get_children():
		if child is Node3D and child.is_in_group(MAP_BREAKER_GROUP):
			return child as Node3D
	return null


func _side_from_room_position(position: Vector3) -> String:
	if absf(position.x) > absf(position.z):
		return SIDE_EAST if position.x >= 0.0 else SIDE_WEST
	return SIDE_SOUTH if position.z >= 0.0 else SIDE_NORTH


func _canonical_breaker_yaw(side: String) -> float:
	match side:
		SIDE_EAST:
			return PI * 0.5
		SIDE_SOUTH:
			return 0.0
		SIDE_WEST:
			return -PI * 0.5
	return PI


func _build_corridor_light_variants(corridor_count: int) -> Array[bool]:
	var variants: Array[bool] = []
	for _corridor_index: int in range(corridor_count):
		variants.append(_rng.randi_range(0, 1) == 1)
	if corridor_count >= 2:
		# Keep the placement random while guaranteeing that a generated map
		# contains both a lighted and an unlighted corridor ceiling.
		if not variants.has(true):
			variants[_rng.randi_range(0, corridor_count - 1)] = true
		if not variants.has(false):
			variants[_rng.randi_range(0, corridor_count - 1)] = false
	return variants


func _add_corridor_edge(
	parent: Node3D,
	from: Vector2,
	to: Vector2,
	edge_name: String,
	ceiling_has_lights: bool,
	elevator_side: String,
) -> void:
	var length := from.distance_to(to)
	var direction := (to - from).normalized()
	var center := from.lerp(to, 0.5)
	var module := CORRIDOR_MODULE.instantiate() as Node3D
	module.name = edge_name
	parent.add_child(module)
	module.position = _to_world(center)
	module.rotation.y = _yaw_from_direction(direction)
	var ceiling_scene: PackedScene = (
		CORRIDOR_CEILING_WITH_LIGHT if ceiling_has_lights else CORRIDOR_CEILING_NORMAL
	)
	module.call(
		"configure",
		length,
		ceiling_scene,
		not ceiling_has_lights,
		elevator_side,
		ELEVATOR_OPENING_WIDTH,
	)
	module.set_meta("centerline_length", length)
	module.set_meta("generated_ceiling_variant", "with_light" if ceiling_has_lights else "normal")
	module.set_meta("generated_elevator_side", elevator_side)


func _randomize_room_ceiling(room: Node3D) -> void:
	var structure := room.get_node_or_null("Structure") as Node3D
	if structure == null:
		return
	var authored_ceiling := structure.get_node_or_null("Ceiling") as Node3D
	var ceiling_transform := Transform3D(Basis.IDENTITY, Vector3(0.0, 6.31, 0.0))
	if authored_ceiling != null:
		ceiling_transform = authored_ceiling.transform
		authored_ceiling.free()

	var ceiling_has_lights := _rng.randi_range(0, 1) == 1
	var ceiling_scene: PackedScene = (
		ROOM_CEILING_WITH_LIGHT if ceiling_has_lights else ROOM_CEILING_NORMAL
	)
	var ceiling := ceiling_scene.instantiate() as Node3D
	ceiling.name = "Ceiling"
	ceiling.transform = ceiling_transform
	structure.add_child(ceiling)
	if not ceiling_has_lights:
		var floor := structure.get_node_or_null("Floor")
		if floor != null:
			_make_surface_dimly_emissive(
				floor,
				FLOOR_EMISSION_COLOR,
				FLOOR_EMISSION_ENERGY,
			)
	room.set_meta("generated_ceiling_variant", "with_light" if ceiling_has_lights else "normal")
	room.set_meta("floor_is_emissive", not ceiling_has_lights)


func _make_surface_dimly_emissive(
	surface_root: Node,
	emission_color: Color,
	emission_energy: float,
) -> void:
	for mesh_instance: MeshInstance3D in surface_root.find_children(
		"*", "MeshInstance3D", true, false
	):
		if mesh_instance.mesh == null:
			continue
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var source_material := (
				mesh_instance.get_active_material(surface_index) as BaseMaterial3D
			)
			if source_material == null:
				continue
			var emissive_material := source_material.duplicate() as BaseMaterial3D
			emissive_material.emission_enabled = true
			emissive_material.emission = emission_color
			emissive_material.emission_texture = source_material.albedo_texture
			emissive_material.emission_energy_multiplier = emission_energy
			mesh_instance.set_surface_override_material(surface_index, emissive_material)
			mesh_instance.add_to_group(&"power_emissive_surfaces")


func _make_room_walls_dimly_emissive(room: Node3D) -> void:
	var structure := room.get_node_or_null("Structure")
	if structure == null:
		return
	for wall: Node in structure.find_children("Wall*", "StaticBody3D", true, false):
		_make_surface_dimly_emissive(wall, WALL_EMISSION_COLOR, WALL_EMISSION_ENERGY)


func _make_room_entrance_walls_dimly_emissive(
	room: Node3D,
	entrance_sides: Array,
) -> void:
	var structure := room.get_node_or_null("Structure")
	if structure == null:
		return
	for side: String in entrance_sides:
		var entrance := structure.get_node_or_null("Entrance%s" % side.capitalize())
		if entrance == null:
			continue
		for wall: Node in entrance.find_children("Wall*", "StaticBody3D", true, false):
			_make_surface_dimly_emissive(wall, WALL_EMISSION_COLOR, WALL_EMISSION_ENERGY)


func _add_elevator_terminal(
	parent: Node3D,
	door_point: Vector2,
	yaw: float,
	role: String,
) -> void:
	parent.position = _to_world(door_point)
	parent.rotation.y = yaw
	parent.set_meta("elevator_role", role)
	parent.add_to_group("%s_elevator_terminal" % role)

	var elevator := ELEVATOR.instantiate() as Node3D
	elevator.name = "Elevator"
	elevator.set("elevator_role", role)
	parent.add_child(elevator)
	# Room floors top out at Y=0.15. Raising the enclosure by 0.15 aligns
	# its floor collision with the room and removes the doorway step.
	elevator.position = Vector3(0.0, 3.15, 4.28)
	if role == "start":
		_add_start_elevator_light(elevator)

	var door := ELEVATOR_DOOR.instantiate() as Node3D
	door.name = "ElevatorDoor"
	door.position = Vector3(0.0, 2.469953, 0.0)
	door.set("is_start_door", role == "start")
	# DoorPanel is an AnimatableBody3D, so it captures its global transform when
	# entering the tree. Position its parent first to keep the closed panel at
	# the elevator entrance instead of synchronized below the floor.
	parent.add_child(door)


func _add_start_elevator_light(elevator: Node3D) -> void:
	var ceiling_light := OmniLight3D.new()
	ceiling_light.name = "CeilingLight"
	ceiling_light.position = ELEVATOR_LIGHT_POSITION
	ceiling_light.layers = 4
	ceiling_light.light_energy = CEILING_LIGHT_ENERGY
	ceiling_light.omni_range = CEILING_LIGHT_RANGE
	ceiling_light.omni_attenuation = CEILING_LIGHT_ATTENUATION
	ceiling_light.add_to_group(&"lights")
	elevator.add_child(ceiling_light)


func _prune_room_candidates(room: Node) -> Dictionary:
	var candidates_by_type: Dictionary = {}
	var keep_counts: Dictionary = {}
	var nonempty_types: Array[String] = []
	var total_candidate_count := 0
	var total_keep_count := 0
	for candidate_type: String in RANDOM_CANDIDATE_GROUPS:
		var group_name: StringName = RANDOM_CANDIDATE_GROUPS[candidate_type]
		var candidates: Array[Node] = []
		for child: Node in room.find_children("*", "Node3D", true, false):
			if child.is_in_group(group_name):
				candidates.append(child)
		candidates_by_type[candidate_type] = candidates
		var keep_count := _rng.randi_range(0, candidates.size())
		keep_counts[candidate_type] = keep_count
		total_candidate_count += candidates.size()
		total_keep_count += keep_count
		if not candidates.is_empty():
			nonempty_types.append(candidate_type)

	if total_candidate_count > 0 and total_keep_count == 0:
		var selected_type := nonempty_types[_rng.randi_range(0, nonempty_types.size() - 1)]
		keep_counts[selected_type] = 1

	for candidate_type: String in RANDOM_CANDIDATE_GROUPS:
		var candidates: Array = candidates_by_type[candidate_type]
		var keep_count: int = keep_counts[candidate_type]
		_shuffle_with_rng(candidates)
		for remove_index: int in range(keep_count, candidates.size()):
			candidates[remove_index].free()
	room.set_meta("generated_had_furniture_candidates", total_candidate_count > 0)
	return keep_counts


func _select_room_scene_paths() -> Array[String]:
	var selected_paths: Array[String] = _room_scene_paths.duplicate()
	_shuffle_with_rng(selected_paths)
	if selected_paths.size() > ROOM_COUNT:
		selected_paths.resize(ROOM_COUNT)
	while selected_paths.size() < ROOM_COUNT:
		selected_paths.append(
			_room_scene_paths[_rng.randi_range(0, _room_scene_paths.size() - 1)]
		)
	_shuffle_with_rng(selected_paths)
	return selected_paths


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
