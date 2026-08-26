extends SceneTree


const GENERATOR_SCENE := preload("res://components/map/map_generator.tscn")
const MINIMUM_LENGTH := 100.0
const MAXIMUM_LENGTH := 500.0

var _has_run := false


func _process(_delta: float) -> bool:
	if _has_run:
		return false
	_has_run = true
	_run_validation()
	return true


func _run_validation() -> void:
	var failures: Array[String] = []
	var observed_room_a := false
	var observed_room_b := false
	var observed_diagonal_turn := false
	var observed_corridor_elevator := false
	var observed_room_elevator := false

	var generator := GENERATOR_SCENE.instantiate()
	root.add_child(generator)
	generator.elevator_room_attachment_chance = 0.5

	for test_seed: int in range(1, 101):
		var layout: Dictionary = generator.generate_layout_for_seed(test_seed)
		if layout.is_empty():
			failures.append("seed %d: layout generation failed" % test_seed)
			continue
		_validate_layout(test_seed, layout, failures)
		for room_spec: Dictionary in layout["rooms"]:
			observed_room_a = observed_room_a or room_spec["type"] == "A"
			observed_room_b = observed_room_b or room_spec["type"] == "B"
		observed_diagonal_turn = observed_diagonal_turn or layout["has_diagonal_turn"]
		observed_corridor_elevator = observed_corridor_elevator or layout["elevator_mode"] == "corridor"
		observed_room_elevator = observed_room_elevator or layout["elevator_mode"] == "room"

	if not observed_room_a or not observed_room_b:
		failures.append("room A/B randomization did not produce both types")
	if not observed_diagonal_turn:
		failures.append("diagonal-turn-capable branch was never exercised")
	if not observed_corridor_elevator or not observed_room_elevator:
		failures.append("both corridor and room elevator attachment modes were not exercised")

	if not generator.generate_map(20260826):
		failures.append("full scene generation failed")
	else:
		_validate_instantiated_map(generator, failures)

	generator.free()
	if failures.is_empty():
		print("Validated 100 layouts and one fully instantiated random map.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _validate_layout(test_seed: int, layout: Dictionary, failures: Array[String]) -> void:
	var main_points: Array[Vector2] = layout["main_points"]
	var branches: Array = layout["branches"]
	var rooms: Array = layout["rooms"]
	if main_points.size() != 7:
		failures.append("seed %d: expected 7 main nodes, found %d" % [test_seed, main_points.size()])
	if branches.size() != 6 or rooms.size() != 6:
		failures.append("seed %d: expected 6 branches and rooms" % test_seed)
	if layout["right_angle_turns"] < 2:
		failures.append("seed %d: fewer than two right-angle turns" % test_seed)

	for edge_index: int in range(main_points.size() - 1):
		var length := main_points[edge_index].distance_to(main_points[edge_index + 1])
		if length < MINIMUM_LENGTH - 0.01 or length > MAXIMUM_LENGTH + 0.01:
			failures.append("seed %d: main edge length %.3f is out of range" % [test_seed, length])
	for branch: Dictionary in branches:
		var length: float = branch["length"]
		if length < MINIMUM_LENGTH or length > MAXIMUM_LENGTH:
			failures.append("seed %d: branch length %.3f is out of range" % [test_seed, length])

	for first_index: int in range(branches.size()):
		var first_room: PackedVector2Array = branches[first_index]["room_polygon"]
		for second_index: int in range(first_index + 1, branches.size()):
			var second_room: PackedVector2Array = branches[second_index]["room_polygon"]
			if not Geometry2D.intersect_polygons(first_room, second_room).is_empty():
				failures.append("seed %d: rooms %d and %d overlap" % [test_seed, first_index, second_index])


func _validate_instantiated_map(generator: Node, failures: Array[String]) -> void:
	var rooms_root := generator.get_node_or_null("Rooms")
	if rooms_root == null or rooms_root.get_child_count() != 6:
		failures.append("instantiated map does not contain exactly six rooms")
	else:
		for room: Node in rooms_root.get_children():
			if room.get_node_or_null("EntranceWallWithDoor") == null:
				failures.append("%s is missing its only corridor entrance" % room.name)
			var counts: Dictionary = room.get_meta("generated_candidate_counts", {})
			for count_name: String in counts:
				var count: int = counts[count_name]
				if count < 0 or count > 5:
					failures.append("%s candidate count %s=%d is out of range" % [room.name, count_name, count])

	var main_corridors := generator.get_node_or_null("MainCorridors")
	var branch_corridors := generator.get_node_or_null("BranchCorridors")
	if main_corridors == null or main_corridors.get_child_count() != 6:
		failures.append("instantiated map does not contain six main corridor edges")
	if branch_corridors == null or branch_corridors.get_child_count() != 6:
		failures.append("instantiated map does not contain six room corridor branches")
	if generator.get_node_or_null("ElevatorTerminal/Elevator") == null:
		failures.append("elevator model is missing")
	if generator.get_node_or_null("ElevatorTerminal/ElevatorDoor") == null:
		failures.append("closed elevator door is missing")
