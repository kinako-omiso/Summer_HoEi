extends Node


signal runtime_map_ready(seed_value: int)

const CAPTURE_MOVIE_UI_TIME := 3.71
const ENDING_FADE_DURATION := 2.0
const ENDING_MOVIE_SCENE := "res://assets/Video/event_movie.tscn"
const CHASE_BGM_FADE_OUT_DELAY_FRAMES := 20

@export_category("Game Rules")
@export_range(1, 10, 1) var building_floors_number: int = 3

@export_category("Audio")
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var bgm_volume_db := 6.0
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var announcement_bgm_volume_db := -40.0
@export_range(-80.0, 12.0, 0.5, "suffix:dB") var announcement_volume_db := 0.0
@export_range(0.1, 5.0, 0.1, "suffix:s") var chase_bgm_fade_duration := 1.0
@export var audio_output_device := "Default"

@export_category("Breaker Announcement")
@export_range(0.05, 1.0, 0.05) var breaker_center_area_ratio := 0.35

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var map_generator: Node3D = $NavigationRegion3D/MapGenerator
@onready var player: CharacterBody3D = $Player
@onready var monster: CharacterBody3D = $demomonster
@onready var result_ui: CanvasLayer = $ResultUserInterface
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
@onready var announcement_1_player: AudioStreamPlayer = $Announcement1Player
@onready var announcement_2_player: AudioStreamPlayer = $Announcement2Player
@onready var player_camera: Camera3D = $Player/PlayerCamera
@onready var capture_movie_player: VideoStreamPlayer = $CaptureMoviePlayer
@onready var ending_fade: ColorRect = $EndingFadeLayer/EndingFade

var camera_change := 1
var is_runtime_map_ready := false
var _breaker_announcement_played := false
var _breaker_announcement_pending := false
var _breaker_is_off := false
var _bgm_fade_tween: Tween
var _bgm_fading_out := false
var _chase_lost_frame_count := 0
var _capture_sequence_playing := false
var _game_over_ui_shown := false
var _ending_transition_playing := false


func _ready() -> void:
	if GameManager.retry_count >= building_floors_number:
		get_tree().change_scene_to_file("res://assets/Video/event_movie.tscn")
		return

	GameManager.floors_number = building_floors_number
	_configure_audio_output()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	monster.process_mode = Node.PROCESS_MODE_DISABLED
	NavigationServer3D.map_set_use_async_iterations(
		navigation_region.get_navigation_map(),
		false
	)

	if not map_generator.generate_map():
		push_error("Runtime map generation failed.")
		return
	_connect_breaker_signals()
	_connect_start_elevator_signal()

	player.global_position = map_generator.player_spawn_position
	player.global_rotation.y = map_generator.player_spawn_yaw
	monster.global_position = map_generator.robot_spawn_position
	monster.player = player
	player_camera.make_current()
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

	print("現在のリトライ回数:", GameManager.check_retry_count())


func _start_bgm() -> void:
	if bgm_player.stream == null:
		push_error("BGMPlayer has no audio stream assigned.")
		return
	bgm_player.volume_db = -80.0
	bgm_player.play()


func _play_game_start_announcement() -> void:
	announcement_1_player.volume_db = announcement_volume_db
	announcement_1_player.play()
	_update_bgm_ducking()


func _update_bgm_ducking() -> void:
	var announcement_is_playing := (
		announcement_1_player.playing or announcement_2_player.playing
	)
	bgm_player.volume_db = (
		announcement_bgm_volume_db if announcement_is_playing else bgm_volume_db
	)


func _on_game_start_announcement_finished() -> void:
	if _breaker_announcement_pending:
		_breaker_announcement_pending = false
		_play_breaker_announcement()
	else:
		_update_bgm_ducking()


func _on_breaker_announcement_finished() -> void:
	_update_bgm_ducking()


func _connect_breaker_signals() -> void:
	var callback := Callable(self, "_on_breaker_lights_out")
	for breaker in get_tree().get_nodes_in_group(&"map_breaker"):
		if breaker.has_signal(&"lights_out") and not breaker.is_connected(&"lights_out", callback):
			breaker.connect(&"lights_out", callback)


func _connect_start_elevator_signal() -> void:
	var callback := Callable(self, "_play_game_start_announcement")
	for door in get_tree().get_nodes_in_group(&"elevator_doors"):
		if (
			door.get("is_start_door") == true
			and door.has_signal(&"player_left_start_elevator")
			and not door.is_connected(&"player_left_start_elevator", callback)
		):
			door.connect(&"player_left_start_elevator", callback)


func _on_breaker_lights_out() -> void:
	_breaker_is_off = true
	_breaker_announcement_pending = false
	var game_start_announcement_was_playing := announcement_1_player.playing
	var announcement_was_stopped := game_start_announcement_was_playing
	if game_start_announcement_was_playing:
		announcement_1_player.stop()
	if announcement_2_player.playing:
		announcement_2_player.stop()
		announcement_was_stopped = true
	if announcement_was_stopped:
		_update_bgm_ducking()
	_update_chase_bgm()


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
	if _should_play_chase_bgm():
		_cancel_bgm_fade()
		_bgm_fading_out = false
		bgm_player.volume_db = _get_bgm_target_volume()
		bgm_player.play()


func _exit_tree() -> void:
	if is_instance_valid(bgm_player):
		bgm_player.stop()


func _process(_delta: float) -> void:
	if not is_runtime_map_ready or _capture_sequence_playing or _ending_transition_playing:
		return
	_update_chase_bgm()
	_check_breaker_in_center_view()
	if camera_change == -1 and Input.is_action_just_pressed("debug_camera_change"):
		player_camera.make_current()
		camera_change = 1
	elif camera_change == 1 and Input.is_action_just_pressed("debug_camera_change"):
		$demomonster/DebugCamera.make_current()
		camera_change = -1


func _update_chase_bgm() -> void:
	if _should_play_chase_bgm():
		_chase_lost_frame_count = 0
		_fade_in_chase_bgm()
		return

	if not bgm_player.playing:
		_chase_lost_frame_count = 0
		return

	_chase_lost_frame_count += 1
	if _chase_lost_frame_count >= CHASE_BGM_FADE_OUT_DELAY_FRAMES:
		_fade_out_chase_bgm()


func _fade_in_chase_bgm() -> void:
	if not bgm_player.playing:
		_start_bgm()
		if not bgm_player.playing:
			return
		_bgm_fading_out = false
		_tween_bgm_volume(_get_bgm_target_volume())
		return

	if _bgm_fading_out:
		_bgm_fading_out = false
		_tween_bgm_volume(_get_bgm_target_volume())


func _fade_out_chase_bgm() -> void:
	if not bgm_player.playing or _bgm_fading_out:
		return
	_bgm_fading_out = true
	_cancel_bgm_fade()
	_bgm_fade_tween = create_tween()
	_bgm_fade_tween.tween_property(
		bgm_player, "volume_db", -80.0, chase_bgm_fade_duration
	)
	_bgm_fade_tween.tween_callback(_stop_bgm_after_fade_out)


func _tween_bgm_volume(target_volume_db: float) -> void:
	_cancel_bgm_fade()
	_bgm_fade_tween = create_tween()
	_bgm_fade_tween.tween_property(
		bgm_player, "volume_db", target_volume_db, chase_bgm_fade_duration
	)


func _cancel_bgm_fade() -> void:
	if _bgm_fade_tween != null and _bgm_fade_tween.is_valid():
		_bgm_fade_tween.kill()
	_bgm_fade_tween = null


func _stop_bgm_after_fade_out() -> void:
	_bgm_fading_out = false
	_bgm_fade_tween = null
	if not _should_play_chase_bgm():
		bgm_player.stop()


func _get_bgm_target_volume() -> float:
	return (
		announcement_bgm_volume_db
		if announcement_1_player.playing or announcement_2_player.playing
		else bgm_volume_db
	)


func _should_play_chase_bgm() -> bool:
	return (
		_breaker_is_off
		and is_instance_valid(monster)
		and bool(monster.call(&"is_chasing_player"))
	)


func _check_breaker_in_center_view() -> void:
	if _breaker_announcement_played or not is_instance_valid(player_camera) or not player_camera.is_current():
		return

	for breaker_node in get_tree().get_nodes_in_group(&"map_breaker"):
		var breaker := breaker_node as Node3D
		if breaker != null and _is_breaker_visible_in_center(breaker):
			_breaker_announcement_played = true
			if announcement_1_player.playing:
				_breaker_announcement_pending = true
			else:
				_play_breaker_announcement()
			return


func _play_breaker_announcement() -> void:
	announcement_2_player.volume_db = announcement_volume_db
	announcement_2_player.play()
	_update_bgm_ducking()


func _is_breaker_visible_in_center(breaker: Node3D) -> bool:
	var target := _get_breaker_view_target(breaker)
	if player_camera.is_position_behind(target):
		return false

	var visible_rect := player_camera.get_viewport().get_visible_rect()
	var screen_center := visible_rect.position + visible_rect.size * 0.5
	var breaker_screen_position := player_camera.unproject_position(target)
	var center_half_size := visible_rect.size * breaker_center_area_ratio * 0.5
	var center_offset := breaker_screen_position - screen_center
	if absf(center_offset.x) > center_half_size.x or absf(center_offset.y) > center_half_size.y:
		return false

	var query := PhysicsRayQueryParameters3D.create(player_camera.global_position, target)
	query.collision_mask = 4
	var hit := player_camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false

	var collider := hit.get("collider") as Node
	return collider != null and (collider == breaker or breaker.is_ancestor_of(collider))


func _get_breaker_view_target(breaker: Node3D) -> Vector3:
	var collision_shape := breaker.get_node_or_null("Breaker/CollisionShape3D") as CollisionShape3D
	if collision_shape != null:
		return collision_shape.global_position
	return breaker.global_position


func _unhandled_input(event: InputEvent) -> void:
	if _capture_sequence_playing or _ending_transition_playing:
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if result_ui:
			result_ui.show_pause_menu()


func _on_player_hit() -> void:
	if _capture_sequence_playing or _ending_transition_playing:
		return
	_capture_sequence_playing = true
	print("you die")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	monster.process_mode = Node.PROCESS_MODE_DISABLED
	bgm_player.stop()
	announcement_1_player.stop()
	announcement_2_player.stop()
	if capture_movie_player.stream != null:
		capture_movie_player.show()
		capture_movie_player.play()
		_show_game_over_after_capture_time()
		return
	_show_game_over_after_capture_movie()


func _show_game_over_after_capture_time() -> void:
	await get_tree().create_timer(CAPTURE_MOVIE_UI_TIME).timeout
	if not is_inside_tree() or not _capture_sequence_playing:
		return
	_show_game_over_after_capture_movie()

func _on_capture_movie_finished() -> void:
	capture_movie_player.hide()
	_show_game_over_after_capture_movie()


func _show_game_over_after_capture_movie() -> void:
	if _game_over_ui_shown:
		return
	_game_over_ui_shown = true
	if is_instance_valid(capture_movie_player):
		capture_movie_player.stop()
		capture_movie_player.hide()
	if result_ui:
		result_ui.show_game_over()

func _on_player_survive() -> void:
	print("success")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _is_first_floor():
		_play_ending_transition()
		return
	if result_ui:
			result_ui.show_game_clear()

func _is_first_floor() -> bool:
	return GameManager.check_retry_count() >= building_floors_number - 1


func _play_ending_transition() -> void:
	if _ending_transition_playing:
		return
	_ending_transition_playing = true
	player.process_mode = Node.PROCESS_MODE_DISABLED
	monster.process_mode = Node.PROCESS_MODE_DISABLED
	bgm_player.stop()
	announcement_1_player.stop()
	announcement_2_player.stop()
	ending_fade.color.a = 0.0
	ending_fade.show()
	var tween := create_tween()
	tween.tween_property(ending_fade, "color:a", 1.0, ENDING_FADE_DURATION)
	await tween.finished
	GameManager.reset_retry_count()
	get_tree().change_scene_to_file(ENDING_MOVIE_SCENE)
