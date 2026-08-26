extends Node


signal runtime_map_ready(seed_value: int)

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var map_generator: Node3D = $NavigationRegion3D/MapGenerator
@onready var player: CharacterBody3D = $Player
@onready var monster: CharacterBody3D = $demomonster
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var camera_change := 1
var is_runtime_map_ready := false


func _ready() -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	monster.process_mode = Node.PROCESS_MODE_DISABLED
	NavigationServer3D.map_set_use_async_iterations(
		navigation_region.get_navigation_map(),
		false
	)

	if not map_generator.generate_map():
		push_error("Runtime map generation failed.")
		return

	player.global_position = map_generator.player_spawn_position
	monster.global_position = map_generator.robot_spawn_position
	monster.player = player
	$Player/PlayerCamera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if world_environment != null and world_environment.environment != null:
		world_environment.environment.background_energy_multiplier = 0.0

	# Allow generated StaticBody3D nodes to enter the physics space before
	# parsing source geometry for the runtime NavigationMesh.
	await get_tree().physics_frame
	navigation_region.bake_navigation_mesh(true)
	await navigation_region.bake_finished
	# Reassign the baked resource so the NavigationServer receives the new
	# polygon data before actors start requesting paths in the same frame.
	var baked_navigation_mesh := navigation_region.navigation_mesh
	navigation_region.navigation_mesh = null
	navigation_region.navigation_mesh = baked_navigation_mesh
	NavigationServer3D.region_set_navigation_mesh(
		navigation_region.get_rid(),
		baked_navigation_mesh
	)
	# Navigation changes are consumed at physics-frame boundaries. Wait for the
	# region update before forcing the final synchronous map iteration.
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(navigation_region.get_navigation_map())
	await get_tree().physics_frame

	player.process_mode = Node.PROCESS_MODE_INHERIT
	monster.process_mode = Node.PROCESS_MODE_INHERIT
	is_runtime_map_ready = true
	runtime_map_ready.emit(map_generator.generated_seed)
	print(
		"Runtime map ready. seed=%d nav_polygons=%d"
		% [map_generator.generated_seed, navigation_region.navigation_mesh.get_polygon_count()]
	)


func _process(_delta: float) -> void:
	if not is_runtime_map_ready:
		return
	if camera_change == -1 and Input.is_action_just_pressed("debug_camera_change"):
		$Player/PlayerCamera.make_current()
		camera_change = 1
	elif camera_change == 1 and Input.is_action_just_pressed("debug_camera_change"):
		$demomonster/DebugCamera.make_current()
		camera_change = -1


func _on_player_hit() -> void:
	print("you die")
