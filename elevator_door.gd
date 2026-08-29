extends Node3D


@export_range(0.5, 3.0, 0.05) var slide_distance := 1.4
@export_range(0.05, 5.0, 0.05) var animation_duration := 0.6
@export_flags_3d_render var render_layers: int = 4
@export var opens_without_power := false

@onready var left_door_panel: AnimatableBody3D = $DoorPanelLeft
@onready var right_door_panel: AnimatableBody3D = $DoorPanelRight
@onready var proximity_area: Area3D = $ProximityArea

var is_power_out := false
var is_open := false
var _left_closed_position := Vector3.ZERO
var _right_closed_position := Vector3.ZERO
var _movement_tween: Tween
var _nearby_players: Dictionary = {}


func _ready() -> void:
	is_power_out = false
	is_open = false
	_left_closed_position = left_door_panel.position
	_right_closed_position = right_door_panel.position
	_apply_render_layers(left_door_panel)
	_apply_render_layers(right_door_panel)
	proximity_area.body_entered.connect(_on_proximity_body_entered)
	proximity_area.body_exited.connect(_on_proximity_body_exited)
	_update_door_state()


func on_power_outage() -> void:
	is_power_out = true
	_update_door_state()


func _on_proximity_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		_nearby_players[body.get_instance_id()] = true
		_update_door_state()


func _on_proximity_body_exited(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		_nearby_players.erase(body.get_instance_id())
		_update_door_state()


func _update_door_state() -> void:
	var should_open := opens_without_power or (is_power_out and _player_is_nearby())
	if should_open == is_open:
		return
	is_open = should_open
	_move_doors(
		_left_closed_position + Vector3.LEFT * slide_distance if is_open else _left_closed_position,
		_right_closed_position + Vector3.RIGHT * slide_distance if is_open else _right_closed_position,
	)


func _player_is_nearby() -> bool:
	return not _nearby_players.is_empty()


func _move_doors(left_target: Vector3, right_target: Vector3) -> void:
	if _movement_tween != null and _movement_tween.is_valid():
		_movement_tween.kill()
	_movement_tween = create_tween()
	_movement_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_movement_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_movement_tween.set_parallel(true)
	_movement_tween.tween_property(
		left_door_panel, "position", left_target, animation_duration
	)
	_movement_tween.tween_property(
		right_door_panel, "position", right_target, animation_duration
	)


func _apply_render_layers(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).layers = render_layers
	for child: Node in node.get_children():
		_apply_render_layers(child)
