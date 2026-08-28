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
	var corridors := generator.get_node("Corridors")
	_validate_debug_lighting(failures)
	_validate_visible_doors(generator, player, failures)
	_validate_elevator_door(generator, failures)
	if not corridors.find_children("*", "Light3D", true, false).is_empty():
		failures.append("generated corridors still contain gameplay lights")
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


func _validate_debug_lighting(failures: Array[String]) -> void:
	if not InputMap.has_action("debug_lighting_toggle"):
		failures.append("debug_lighting_toggle input action is missing")
		return
	var has_k_key := false
	for input_event: InputEvent in InputMap.action_get_events("debug_lighting_toggle"):
		if input_event is InputEventKey and (input_event as InputEventKey).physical_keycode == KEY_K:
			has_k_key = true
			break
	if not has_k_key:
		failures.append("debug_lighting_toggle is not assigned to the K key")

	var world_environment := _main.get_node("WorldEnvironment") as WorldEnvironment
	var environment := world_environment.environment
	var original_ambient_energy := environment.ambient_light_energy
	var original_background_energy := environment.background_energy_multiplier
	_main.toggle_debug_lighting()
	if not is_zero_approx(environment.ambient_light_energy) or not is_zero_approx(environment.background_energy_multiplier):
		failures.append("debug lighting did not turn off")
	_main.toggle_debug_lighting()
	if not is_equal_approx(environment.ambient_light_energy, original_ambient_energy):
		failures.append("debug ambient lighting did not restore its original energy")
	if not is_equal_approx(environment.background_energy_multiplier, original_background_energy):
		failures.append("debug background lighting did not restore its original energy")


func _validate_visible_doors(generator: Node, player: CharacterBody3D, failures: Array[String]) -> void:
	var doors := generator.get_node("Rooms").find_children(
		"InteractiveDoor", "AnimatableBody3D", true, false
	)
	if doors.size() != generator.generated_door_count:
		failures.append("runtime visible door count does not match generator metadata")
	var camera := player.get_node("PlayerCamera") as Camera3D
	for door: AnimatableBody3D in doors:
		var entrance_wall := door.get_parent() as Node3D
		var expected_position := entrance_wall.global_transform * door.position
		if door.global_position.distance_to(expected_position) > 0.01:
			failures.append("%s did not inherit its entrance wall transform" % door.get_path())
		if door.global_position.y < 0.0:
			failures.append("%s remained below the room floor" % door.get_path())
		var visible_meshes := 0
		var combined_bounds := AABB()
		for mesh: MeshInstance3D in door.find_children("*", "MeshInstance3D", true, false):
			if mesh.visible and mesh.layers & camera.cull_mask != 0:
				visible_meshes += 1
				var world_bounds := mesh.global_transform * mesh.get_aabb()
				combined_bounds = world_bounds if combined_bounds.size == Vector3.ZERO else combined_bounds.merge(world_bounds)
		if visible_meshes == 0:
			failures.append("%s has no mesh visible to PlayerCamera" % door.get_path())
		elif combined_bounds.size.length() < 0.1:
			failures.append("%s has an empty visual AABB" % door.get_path())


func _validate_elevator_door(generator: Node, failures: Array[String]) -> void:
	var door := generator.get_node("ElevatorTerminal/ElevatorDoor") as Node3D
	var panel := door.get_node("DoorPanel") as AnimatableBody3D
	var expected_position := door.global_transform * panel.position
	if panel.global_position.distance_to(expected_position) > 0.01:
		failures.append("elevator door panel did not inherit its positioned parent transform")
	if panel.global_position.y < 0.0:
		failures.append("elevator door panel remained below the floor")
