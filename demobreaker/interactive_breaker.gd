extends Node3D

@export var open_angle_degrees: float = -120.0
@export var animation_duration: float = 0.45

@onready var interaction_area: Area3D = $InteractionArea

var is_used := false
var _is_moving := false


func _ready() -> void:
	_set_render_layers(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player_is_nearby():
		_toggle_lever()


func _player_is_nearby() -> bool:
	for body in interaction_area.get_overlapping_bodies():
		if body is CharacterBody3D:
			return true
	return false


func _toggle_lever() -> void:
	if _is_moving:
		return

	if is_used:
		return

	_is_moving = true
	is_used = not is_used
	var target_angle := rotation.x + deg_to_rad(open_angle_degrees)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation:x", target_angle, animation_duration)
	await tween.finished
	_is_moving = false


func _set_render_layers(node: Node) -> void:
	if node is MeshInstance3D:
		node.layers = 4
	for child in node.get_children():
		_set_render_layers(child)
