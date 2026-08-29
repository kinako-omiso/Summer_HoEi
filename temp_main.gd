extends Node


signal runtime_map_ready(seed_value: int)

@export_category("Audio")
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var bgm_volume_db := 6.0
@export var audio_output_device := "Default"

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var map_generator: Node3D = $NavigationRegion3D/MapGenerator
@onready var player: CharacterBody3D = $Player
@onready var monster: CharacterBody3D = $demomonster
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var result_ui: CanvasLayer = $ResultUserInterface
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer

var camera_change := 1
var is_runtime_map_ready := false
var debug_lighting_enabled := true
var _debug_ambient_energy := 0.0
var _debug_background_energy := 0.0


func _ready() -> void:
	_start_bgm()
	var environment := world_environment.environment
	if environment != null:
		_debug_ambient_energy = environment.ambient_light_energy
		_debug_background_energy = environment.background_energy_multiplier
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
	player.global_rotation.y = map_generator.player_spawn_yaw
	monster.global_position = map_generator.robot_spawn_position
	monster.player = player
	$Player/PlayerCamera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
		"Runtime map ready. seed=%d doors=%d nav_polygons=%d"
		% [
			map_generator.generated_seed,
			map_generator.generated_door_count,
			navigation_region.navigation_mesh.get_polygon_count(),
		]
	)


func _start_bgm() -> void:
	_configure_audio_output()
	bgm_player.volume_db = bgm_volume_db
	if bgm_player.stream == null:
		push_error("BGMPlayer has no audio stream assigned.")
		return
	bgm_player.play()


func _configure_audio_output() -> void:
	var available_devices := AudioServer.get_output_device_list()
	var requested_device := audio_output_device.strip_edges()
	if requested_device.is_empty() or requested_device == "Default":
		AudioServer.output_device = "Default"
	elif available_devices.has(requested_device):
		AudioServer.output_device = requested_device
	else:
		AudioServer.output_device = "Default"
		push_warning(
			"Audio output device '%s' is unavailable; using Default."
			% requested_device
		)


func _on_bgm_player_finished() -> void:
	# Fallback for stream formats that do not expose an internal loop setting.
	bgm_player.play()


func _exit_tree() -> void:
	if is_instance_valid(bgm_player):
		bgm_player.stop()


func _process(_delta: float) -> void:
	if not is_runtime_map_ready:
		return
	if camera_change == -1 and Input.is_action_just_pressed("debug_camera_change"):
		$Player/PlayerCamera.make_current()
		camera_change = 1
	elif camera_change == 1 and Input.is_action_just_pressed("debug_camera_change"):
		$demomonster/DebugCamera.make_current()
		camera_change = -1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_lighting_toggle") and not event.is_echo():
		toggle_debug_lighting()
		get_viewport().set_input_as_handled()


func toggle_debug_lighting() -> void:
	debug_lighting_enabled = not debug_lighting_enabled
	var environment := world_environment.environment
	if environment == null:
		return
	environment.ambient_light_energy = _debug_ambient_energy if debug_lighting_enabled else 0.0
	environment.background_energy_multiplier = _debug_background_energy if debug_lighting_enabled else 0.0
	print("Debug lighting: %s" % ("ON" if debug_lighting_enabled else "OFF"))


func _on_player_hit() -> void:
	print("you die")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if result_ui:
		result_ui.show_game_over()

func _on_player_survive() -> void:
	print("success")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if result_ui:
			result_ui.show_game_clear()
