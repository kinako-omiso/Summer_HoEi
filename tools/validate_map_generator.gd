extends SceneTree


const GENERATOR_SCENE := preload("res://components/map/map_generator.tscn")
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
	var observed_room_a := false
	var observed_room_b := false
	var observed_extra_connection := false
	var observed_one_entrance := false
	var observed_three_entrances := false

	var generator := GENERATOR_SCENE.instantiate()
	root.add_child(generator)

	for test_seed: int in range(1, 101):
		var layout: Dictionary = generator.generate_layout_for_seed(test_seed)
		if layout.is_empty():
			failures.append("seed %d: layout generation failed" % test_seed)
			continue
		_validate_layout(test_seed, layout, failures)
		observed_extra_connection = observed_extra_connection or layout["corridors"].size() > ROOM_COUNT - 1
		for room_spec: Dictionary in layout["rooms"]:
			observed_room_a = observed_room_a or room_spec["type"] == "A"
			observed_room_b = observed_room_b or room_spec["type"] == "B"
			var entrance_count: int = room_spec["entrances"].size()
			observed_one_entrance = observed_one_entrance or entrance_count == 1
			observed_three_entrances = observed_three_entrances or entrance_count == 3

	if not observed_room_a or not observed_room_b:
		failures.append("room A/B randomization did not produce both types")
	if not observed_extra_connection:
		failures.append("no loop-producing extra room connection was observed")
	if not observed_one_entrance or not observed_three_entrances:
		failures.append("the 1-3 entrance range was not exercised")

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

	var elevator_room_index: int = layout["elevator_room_index"]
	var elevator_side: String = layout["elevator_side"]
	if elevator_room_index < 0 or elevator_room_index >= rooms.size():
		failures.append("seed %d: elevator room index is invalid" % test_seed)
	elif not rooms[elevator_room_index]["entrances"].has(elevator_side):
		failures.append("seed %d: elevator is not counted as a room entrance" % test_seed)


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
			var entrance_count: int = room.get_meta("generated_entrance_count", 0)
			if entrance_count < 1 or entrance_count > 3:
				failures.append("%s instantiated entrance count is invalid" % room.name)
			var entrance_nodes := room.find_children("Entrance*", "Node3D", true, false)
			if entrance_nodes.size() != entrance_count:
				failures.append("%s entrance node count does not match metadata" % room.name)
	if corridors_root == null or corridors_root.get_child_count() < ROOM_COUNT - 1:
		failures.append("instantiated map has too few room corridors")
	if generator.get_node_or_null("ElevatorTerminal/Elevator") == null:
		failures.append("elevator model is missing")
	if generator.get_node_or_null("ElevatorTerminal/ElevatorDoor") == null:
		failures.append("closed elevator door is missing")
