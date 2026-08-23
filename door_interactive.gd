extends AnimatableBody3D

@export var open_angle_degrees: float = -100.0
@export var animation_duration: float = 0.45

@onready var interaction_area: Area3D = $InteractionArea
# 追加部分
@export var navigation_link: NavigationLink3D
var is_open := false
var _is_moving := false


func _ready() -> void:
	_set_render_layers(self)
	# 追加部分
	navigation_link.enabled = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player_is_nearby():
		_toggle_door()


func _player_is_nearby() -> bool:
	for body in interaction_area.get_overlapping_bodies():
		if body is CharacterBody3D:
			return true
	return false


func _toggle_door() -> void:
	if _is_moving:
		return

	_is_moving = true
	var target_angle := 0.0 if is_open else deg_to_rad(open_angle_degrees)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation:y", target_angle, animation_duration)
	await tween.finished
	is_open = not is_open
	# 追加部分
	navigation_link.enabled = is_open
	_is_moving = false


func _set_render_layers(node: Node) -> void:
	if node is MeshInstance3D:
		node.layers = 4
	for child in node.get_children():
		_set_render_layers(child)
