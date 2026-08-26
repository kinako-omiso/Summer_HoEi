extends SceneTree


const MAIN_SCENE := preload("res://temp_main.tscn")
const TEST_SEED := 20260826
const TIMEOUT_MSEC := 120_000

var _main: Node
var _started := false
var _map_ready := false
var _ready_seed := 0
var _started_at_msec := 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_started_at_msec = Time.get_ticks_msec()
		_main = MAIN_SCENE.instantiate()
		var generator := _main.get_node("NavigationRegion3D/MapGenerator")
		generator.seed_override = TEST_SEED
		_main.runtime_map_ready.connect(_on_runtime_map_ready)
		root.add_child(_main)
		return false

	if _map_ready:
		_validate_ready_map()
		return true

	if Time.get_ticks_msec() - _started_at_msec > TIMEOUT_MSEC:
		push_error("Runtime map validation timed out while baking NavigationMesh.")
		quit(1)
		return true
	return false


func _on_runtime_map_ready(seed_value: int) -> void:
	_ready_seed = seed_value
	_map_ready = true


func _validate_ready_map() -> void:
	var failures: Array[String] = []
	if _ready_seed != TEST_SEED:
		failures.append("expected seed %d, got %d" % [TEST_SEED, _ready_seed])

	var navigation_region := _main.get_node("NavigationRegion3D") as NavigationRegion3D
	var generator := _main.get_node("NavigationRegion3D/MapGenerator")
	var player := _main.get_node("Player") as CharacterBody3D
	var monster := _main.get_node("demomonster") as CharacterBody3D
	var rooms := generator.get_node("Rooms")
	if navigation_region.navigation_mesh.get_polygon_count() <= 0:
		failures.append("runtime NavigationMesh has no polygons")
	if rooms.get_child_count() != 6:
		failures.append("runtime map does not contain six rooms")
	if player.process_mode == Node.PROCESS_MODE_DISABLED:
		failures.append("player remained disabled after baking")
	if monster.process_mode == Node.PROCESS_MODE_DISABLED:
		failures.append("monster remained disabled after baking")
	if monster.player != player:
		failures.append("monster player reference is incorrect")

	var map_rid := navigation_region.get_navigation_map()
	var elevator_terminal := generator.get_node("ElevatorTerminal") as Node3D
	var elevator_front := elevator_terminal.global_transform * Vector3(0.0, 0.45, -2.0)
	for room: Node3D in rooms.get_children():
		var room_start := room.global_position + Vector3(0.0, 0.45, 0.0)
		var path := NavigationServer3D.map_get_path(map_rid, room_start, elevator_front, true)
		if path.is_empty():
			failures.append("%s has no navigation path to the elevator" % room.name)

	var chase_path := NavigationServer3D.map_get_path(
		map_rid,
		monster.global_position,
		player.global_position,
		true
	)
	if chase_path.is_empty():
		failures.append("monster spawn has no path to player spawn")

	_main.free()
	if failures.is_empty():
		print("Validated runtime generation, NavigationMesh, and all room-to-elevator paths.")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)
