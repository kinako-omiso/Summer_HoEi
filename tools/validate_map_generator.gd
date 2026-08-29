extends SceneTree


const GENERATOR_SCENE := preload("res://components/map/map_generator.tscn")
const ROOM_TEMPLATE := preload("res://components/rooms/room_template.tscn")
const ROOM_A := preload("res://components/rooms/room_a_office.tscn")
const ROOM_B := preload("res://components/rooms/room_b_storage.tscn")
const CENTERED_DOOR_WALL := preload("res://components/map/centered_wall_with_door.tscn")
const ELEVATOR_ENTRANCE_WALL := preload(
	"res://components/map/centered_wall_with_elevator_door.tscn"
)
const ELEVATOR_DOOR := preload("res://assets/3DModel/elevator_door.tscn")
const ROOM_COUNT := 6
const MINIMUM_LENGTH := 3.0
const MAXIMUM_LENGTH := 20.0
const ROOM_HALF_SIZE := 7.0

var _has_run := false


func _process(_delta: float) -> bool:
	if _has_run:
		return false
	_has_run = true
	_run_validation()
	return true


func _run_validation() -> void:
	var failures: Array[String] = []
	var observed_duplicate_selection := false
	var observed_extra_connection := false
	var observed_one_entrance := false
	var observed_three_entrances := false

	var generator := GENERATOR_SCENE.instantiate()
	root.add_child(generator)
	var available_room_scenes: Array[String] = generator.get_available_room_scene_paths()
	if available_room_scenes.is_empty():
		failures.append("no dynamically discoverable room scenes were found")
	if available_room_scenes.has("res://components/rooms/room_template.tscn"):
		failures.append("room_template.tscn must not be a random generation candidate")
	_validate_room_template(failures)
	_validate_room_floor_alignment(failures)
	_validate_centered_door_fit(generator, failures)
	_validate_elevator_door_fit(generator, failures)
	_validate_authored_breaker_transforms(generator, failures)
	_validate_authored_wall_preservation(generator, failures)

	for test_seed: int in range(1, 101):
		var layout: Dictionary = generator.generate_layout_for_seed(test_seed)
		if layout.is_empty():
			failures.append("seed %d: layout generation failed" % test_seed)
			continue
		_validate_layout(test_seed, layout, failures)
		observed_extra_connection = observed_extra_connection or layout["corridors"].size() > ROOM_COUNT - 1
		var selected_scene_paths: Dictionary = {}
		for room_spec: Dictionary in layout["rooms"]:
			var scene_path: String = room_spec["scene_path"]
			if not available_room_scenes.has(scene_path):
				failures.append("seed %d: selected an undiscovered room scene" % test_seed)
			selected_scene_paths[scene_path] = true
			var entrance_count: int = room_spec["entrances"].size()
			observed_one_entrance = observed_one_entrance or entrance_count == 1
			observed_three_entrances = observed_three_entrances or entrance_count == 3
		observed_duplicate_selection = observed_duplicate_selection or selected_scene_paths.size() < ROOM_COUNT

	if not observed_duplicate_selection:
		failures.append("room selection with replacement was not exercised")
	if not observed_extra_connection:
		failures.append("no loop-producing extra room connection was observed")
	if not observed_one_entrance or not observed_three_entrances:
		failures.append("the 1-3 entrance range was not exercised")
	_validate_door_swing_obstruction_guard(generator, failures)
	_validate_random_door_generation(generator, failures)

	if not generator.generate_map(20260826):
		failures.append("full compact scene generation failed")
	else:
		_validate_instantiated_map(generator, failures)

	generator.free()
	if failures.is_empty():
		print("Validated 100 compact layouts and one fully instantiated map.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _validate_room_template(failures: Array[String]) -> void:
	var room_template := ROOM_TEMPLATE.instantiate()
	if not room_template is Node3D:
		failures.append("room template root is not Node3D")
		room_template.free()
		return
	if room_template.get_child_count() != 1 or room_template.get_node_or_null("Structure") == null:
		failures.append("room template root must contain only Structure")
		room_template.free()
		return
	var structure := room_template.get_node("Structure")
	var expected_nodes: Array[String] = [
		"Floor", "Ceiling", "WallEast", "WallSouth", "WallWest"
	]
	if structure.get_child_count() != expected_nodes.size():
		failures.append("room template Structure must contain floor, ceiling, and three walls")
	for node_name: String in expected_nodes:
		if structure.get_node_or_null(node_name) == null:
			failures.append("room template is missing %s" % node_name)
	if structure.get_node_or_null("WallNorth") != null:
		failures.append("room template north side must remain open")
	if room_template.find_children("*", "Light3D", true, false).is_empty():
		failures.append("room template must contain lighting")
	var center_light := room_template.get_node_or_null("Structure/Floor/CenterLight") as OmniLight3D
	if center_light == null or not center_light.is_in_group("lights"):
		failures.append("room template floor center light is missing or not switchable")
	room_template.free()


func _validate_room_floor_alignment(failures: Array[String]) -> void:
	for room_scene: PackedScene in [ROOM_A, ROOM_B]:
		var room := room_scene.instantiate() as Node3D
		var floor := room.get_node_or_null("Structure/Floor") as Node3D
		if floor == null:
			failures.append("%s is missing Structure/Floor" % room.name)
		elif not floor.transform.is_equal_approx(Transform3D.IDENTITY):
			failures.append("%s floor is not aligned with the corridor floor" % room.name)
		room.free()


func _validate_door_swing_obstruction_guard(generator: Node, failures: Array[String]) -> void:
	var room := ROOM_TEMPLATE.instantiate() as Node3D
	generator.add_child(room)
	var entrance_wall := CENTERED_DOOR_WALL.instantiate() as Node3D
	room.get_node("Structure").add_child(entrance_wall)
	generator.call("_apply_wall_transform", entrance_wall, "north")

	var blocker := StaticBody3D.new()
	room.add_child(blocker)
	blocker.position = Vector3(0.0, 1.0, -5.6)
	var blocker_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(1.0, 2.0, 1.0)
	blocker_shape.shape = box_shape
	blocker.add_child(blocker_shape)
	if not generator.call("_door_swing_is_blocked", room, entrance_wall):
		failures.append("door swing obstruction was not detected")

	blocker.position = Vector3(5.0, 1.0, 0.0)
	if generator.call("_door_swing_is_blocked", room, entrance_wall):
		failures.append("object outside the door swing was reported as an obstruction")
	room.free()


func _validate_centered_door_fit(generator: Node, failures: Array[String]) -> void:
	var wall := CENTERED_DOOR_WALL.instantiate() as Node3D
	generator.add_child(wall)
	var door := wall.get_node("InteractiveDoor") as AnimatableBody3D
	var door_bounds := AABB()
	for mesh: MeshInstance3D in door.find_children("*", "MeshInstance3D", true, false):
		var wall_space_bounds := wall.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		door_bounds = wall_space_bounds if door_bounds.size == Vector3.ZERO else door_bounds.merge(wall_space_bounds)
	var left_bounds := _collision_bounds_in_wall_space(wall, "WallLeft/CollisionShape3D")
	var right_bounds := _collision_bounds_in_wall_space(wall, "WallRight/CollisionShape3D")
	if absf(left_bounds.end.x - door_bounds.position.x) > 0.02:
		failures.append("centered door has a gap at its left edge")
	if absf(right_bounds.position.x - door_bounds.end.x) > 0.02:
		failures.append("centered door has a gap at its right edge")
	wall.free()


func _validate_elevator_door_fit(generator: Node, failures: Array[String]) -> void:
	var wall := ELEVATOR_ENTRANCE_WALL.instantiate() as Node3D
	generator.add_child(wall)
	var door := ELEVATOR_DOOR.instantiate() as Node3D
	# Match the relative transforms used by MapGenerator.
	door.position = Vector3(0.0, 2.469953 - 3.15, 0.0)
	wall.add_child(door)

	var door_bounds := AABB()
	for mesh: MeshInstance3D in door.find_children("*", "MeshInstance3D", true, false):
		var mesh_to_wall := wall.global_transform.affine_inverse() * mesh.global_transform
		var mesh_bounds: AABB = mesh_to_wall * mesh.get_aabb()
		door_bounds = mesh_bounds if door_bounds.size == Vector3.ZERO else door_bounds.merge(mesh_bounds)
	var header_bounds := _collision_bounds_in_wall_space(
		wall, "WallHeader/CollisionShape3D"
	)
	var left_bounds := _collision_bounds_in_wall_space(wall, "WallLeft/CollisionShape3D")
	var right_bounds := _collision_bounds_in_wall_space(wall, "WallRight/CollisionShape3D")
	var maximum_frame_overlap := 0.025
	if absf(header_bounds.position.y - door_bounds.end.y) > maximum_frame_overlap:
		failures.append("elevator door does not meet the top of its generated opening")
	if absf(left_bounds.end.x - door_bounds.position.x) > maximum_frame_overlap:
		failures.append("elevator door does not meet the left of its generated opening")
	if absf(right_bounds.position.x - door_bounds.end.x) > maximum_frame_overlap:
		failures.append("elevator door does not meet the right of its generated opening")
	if absf(left_bounds.position.y - door_bounds.position.y) > 0.01:
		failures.append("elevator door does not meet the bottom of its generated opening")
	wall.free()


func _validate_authored_breaker_transforms(generator: Node, failures: Array[String]) -> void:
	for room_scene: PackedScene in [ROOM_A, ROOM_B]:
		var room := room_scene.instantiate() as Node3D
		generator.add_child(room)
		var breaker := room.get_node("Breaker") as Node3D
		var authored_transform := breaker.transform
		var original_side: String = generator.call("_side_from_room_position", breaker.position)
		var non_conflicting_side := "north" if original_side != "north" else "east"
		generator.call("_relocate_breaker", room, [non_conflicting_side])
		if not breaker.transform.is_equal_approx(authored_transform):
			failures.append("%s authored breaker Transform was overwritten without a wall conflict" % room.name)
		room.free()

		var moved_room := room_scene.instantiate() as Node3D
		generator.add_child(moved_room)
		var moved_breaker := moved_room.get_node("Breaker") as Node3D
		var original_yaw := moved_breaker.rotation.y
		var original_height := moved_breaker.position.y
		var original_canonical_yaw: float = generator.call("_canonical_breaker_yaw", original_side)
		generator.call("_relocate_breaker", moved_room, [original_side])
		var moved_side: String = generator.call("_side_from_room_position", moved_breaker.position)
		var moved_canonical_yaw: float = generator.call("_canonical_breaker_yaw", moved_side)
		var original_offset := wrapf(original_yaw - original_canonical_yaw, -PI, PI)
		var moved_offset := wrapf(moved_breaker.rotation.y - moved_canonical_yaw, -PI, PI)
		if absf(angle_difference(original_offset, moved_offset)) > 0.001:
			failures.append("%s breaker authored orientation was lost during required relocation" % moved_room.name)
		if not is_equal_approx(moved_breaker.position.y, original_height):
			failures.append("%s breaker authored height was lost during required relocation" % moved_room.name)
		moved_room.free()


func _validate_authored_wall_preservation(generator: Node, failures: Array[String]) -> void:
	var room := ROOM_A.instantiate() as Node3D
	generator.add_child(room)
	var authored_wall := room.get_node("Structure/WallEast") as Node3D
	var authored_transform := authored_wall.transform
	var authored_instance_id := authored_wall.get_instance_id()
	var custom_child := Node3D.new()
	custom_child.name = "AuthorSavedWallChild"
	authored_wall.add_child(custom_child)
	generator.call("_configure_room_walls", room, ["north"], "")
	var generated_wall := room.get_node_or_null("Structure/WallEast") as Node3D
	if generated_wall == null or generated_wall.get_instance_id() != authored_instance_id:
		failures.append("solid authored wall was replaced during map generation")
	elif not generated_wall.transform.is_equal_approx(authored_transform):
		failures.append("solid authored wall Transform was overwritten during map generation")
	elif generated_wall.get_node_or_null("AuthorSavedWallChild") == null:
		failures.append("solid authored wall custom children were discarded")
	room.free()

	var template_room := ROOM_TEMPLATE.instantiate() as Node3D
	generator.add_child(template_room)
	generator.call("_configure_room_walls", template_room, ["east"], "")
	if template_room.get_node_or_null("Structure/WallNorth") == null:
		failures.append("missing authored wall was not filled when generated as solid")
	template_room.free()


func _collision_bounds_in_wall_space(wall: Node3D, path: String) -> AABB:
	var collision_shape := wall.get_node(path) as CollisionShape3D
	var shape_to_wall := wall.global_transform.affine_inverse() * collision_shape.global_transform
	return shape_to_wall * collision_shape.shape.get_debug_mesh().get_aabb()


func _validate_random_door_generation(generator: Node, failures: Array[String]) -> void:
	var observed_door := false
	var observed_open_entrance := false
	var total_doors := 0
	var total_open_entrances := 0
	var total_obstructed_candidates := 0
	for test_seed: int in range(1001, 1011):
		if not generator.generate_map(test_seed):
			failures.append("seed %d: random door map generation failed" % test_seed)
			continue
		if generator.generated_door_count < 1:
			failures.append("seed %d: generated map has no doors" % test_seed)
		var instantiated_doors := generator.get_node("Rooms").find_children(
			"InteractiveDoor", "AnimatableBody3D", true, false
		)
		if instantiated_doors.size() != generator.generated_door_count:
			failures.append("seed %d: door metadata does not match instantiated doors" % test_seed)
		for room: Node in generator.get_node("Rooms").get_children():
			var entrance_count: int = room.get_meta("generated_entrance_count", 0)
			var door_sides: Array = room.get_meta("generated_door_sides", [])
			var open_sides: Array = room.get_meta("generated_open_entrance_sides", [])
			var obstructed_sides: Array = room.get_meta("generated_obstructed_door_sides", [])
			if door_sides.size() + open_sides.size() != entrance_count:
				failures.append("%s does not classify every entrance as door or open" % room.name)
			observed_door = observed_door or not door_sides.is_empty()
			observed_open_entrance = observed_open_entrance or not open_sides.is_empty()
			total_doors += door_sides.size()
			total_open_entrances += open_sides.size()
			total_obstructed_candidates += obstructed_sides.size()
	if not observed_door:
		failures.append("random door generation did not produce a door")
	if not observed_open_entrance:
		failures.append("random door generation did not produce an open entrance")
	print(
		"Random door sample: doors=%d open=%d obstructed=%d"
		% [total_doors, total_open_entrances, total_obstructed_candidates]
	)


func _validate_layout(test_seed: int, layout: Dictionary, failures: Array[String]) -> void:
	var rooms: Array = layout["rooms"]
	var corridors: Array = layout["corridors"]
	var connections: Array = layout["connections"]
	if rooms.size() != ROOM_COUNT:
		failures.append("seed %d: expected six rooms, found %d" % [test_seed, rooms.size()])
		return
	if corridors.size() < ROOM_COUNT - 1:
		failures.append("seed %d: room graph is missing required connections" % test_seed)

	for corridor: Dictionary in corridors:
		var length: float = corridor["length"]
		if length < MINIMUM_LENGTH - 0.01 or length > MAXIMUM_LENGTH + 0.01:
			failures.append("seed %d: corridor length %.3f is outside 3-20m" % [test_seed, length])

	for room_index: int in range(rooms.size()):
		var entrances: Array = rooms[room_index]["entrances"]
		if entrances.size() < 1 or entrances.size() > 3:
			failures.append("seed %d: room %d has %d entrances" % [test_seed, room_index, entrances.size()])
		var unique_sides: Dictionary = {}
		for side: String in entrances:
			unique_sides[side] = true
		if unique_sides.size() != entrances.size():
			failures.append("seed %d: room %d repeats an entrance side" % [test_seed, room_index])

		var first_origin: Vector2 = rooms[room_index]["origin"]
		for other_index: int in range(room_index + 1, rooms.size()):
			var second_origin: Vector2 = rooms[other_index]["origin"]
			if absf(first_origin.x - second_origin.x) < ROOM_HALF_SIZE * 2.0 and absf(first_origin.y - second_origin.y) < ROOM_HALF_SIZE * 2.0:
				failures.append("seed %d: rooms %d and %d overlap" % [test_seed, room_index, other_index])

	if not _all_rooms_connected(connections):
		failures.append("seed %d: room graph is disconnected" % test_seed)

	var start_room_index: int = layout["start_elevator_room_index"]
	var goal_room_index: int = layout["goal_elevator_room_index"]
	if start_room_index == goal_room_index:
		failures.append("seed %d: start and goal elevators share a room" % test_seed)
	for role: String in ["start", "goal"]:
		var elevator_room_index: int = layout["%s_elevator_room_index" % role]
		var elevator_side: String = layout["%s_elevator_side" % role]
		if elevator_room_index < 0 or elevator_room_index >= rooms.size():
			failures.append("seed %d: %s elevator room index is invalid" % [test_seed, role])
		elif not rooms[elevator_room_index]["entrances"].has(elevator_side):
			failures.append(
				"seed %d: %s elevator is not counted as a room entrance"
				% [test_seed, role]
			)
		elif rooms[elevator_room_index]["elevator_role"] != role:
			failures.append("seed %d: %s elevator role metadata is missing" % [test_seed, role])


func _all_rooms_connected(connections: Array) -> bool:
	var adjacency: Array[Array] = []
	for _room_index: int in range(ROOM_COUNT):
		adjacency.append([])
	for connection: Dictionary in connections:
		var first: int = connection["first"]
		var second: int = connection["second"]
		adjacency[first].append(second)
		adjacency[second].append(first)
	var visited: Dictionary = {0: true}
	var pending: Array[int] = [0]
	while not pending.is_empty():
		var current: int = pending.pop_back()
		for neighbor: int in adjacency[current]:
			if not visited.has(neighbor):
				visited[neighbor] = true
				pending.append(neighbor)
	return visited.size() == ROOM_COUNT


func _validate_instantiated_map(generator: Node, failures: Array[String]) -> void:
	var rooms_root := generator.get_node_or_null("Rooms")
	var corridors_root := generator.get_node_or_null("Corridors")
	if rooms_root == null or rooms_root.get_child_count() != ROOM_COUNT:
		failures.append("instantiated map does not contain six rooms")
	else:
		for room: Node in rooms_root.get_children():
			var scene_path: String = room.get_meta("generated_room_scene", "")
			if not generator.get_available_room_scene_paths().has(scene_path):
				failures.append("%s has invalid generated room scene metadata" % room.name)
			var entrance_count: int = room.get_meta("generated_entrance_count", 0)
			if entrance_count < 1 or entrance_count > 3:
				failures.append("%s instantiated entrance count is invalid" % room.name)
			var entrance_nodes := room.find_children("Entrance*", "Node3D", true, false)
			if entrance_nodes.size() != entrance_count:
				failures.append("%s entrance node count does not match metadata" % room.name)
	if corridors_root == null or corridors_root.get_child_count() < ROOM_COUNT - 1:
		failures.append("instantiated map has too few room corridors")
	for role: String in ["Start", "Goal"]:
		var terminal_path := "%sElevatorTerminal" % role
		var elevator := generator.get_node_or_null("%s/Elevator" % terminal_path)
		if elevator == null:
			failures.append("%s elevator model is missing" % role.to_lower())
			continue
		var expected_role := role.to_lower()
		if elevator.get("elevator_role") != expected_role:
			failures.append("%s elevator has the wrong role" % expected_role)
		var completion_area := elevator.get_node_or_null("GallePost") as Area3D
		if completion_area == null:
			failures.append("%s elevator completion area is missing" % expected_role)
		elif completion_area.is_in_group(&"goal_elevator") != (expected_role == "goal"):
			failures.append("only the goal elevator may have the completion group")
		var elevator_door := generator.get_node_or_null("%s/ElevatorDoor" % terminal_path) as Node3D
		if elevator_door == null:
			failures.append("%s elevator door is missing" % expected_role)
		elif not elevator_door.position.is_equal_approx(Vector3(0.0, 2.469953, 0.0)):
			failures.append("%s elevator door is offset from its entrance" % expected_role)
		elif elevator_door.get("is_start_door") != (expected_role == "start"):
			failures.append("%s elevator door has the wrong access mode" % expected_role)

	var start_terminal := generator.get_node_or_null("StartElevatorTerminal") as Node3D
	if start_terminal != null:
		var expected_spawn := start_terminal.global_transform * Vector3(0.0, 0.45, 2.6)
		if not generator.player_spawn_position.is_equal_approx(expected_spawn):
			failures.append("player spawn is not inside the start elevator")
