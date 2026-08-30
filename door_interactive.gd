extends AnimatableBody3D

@export var open_angle_degrees: float = -100.0
@export var animation_duration: float = 0.45
@export var enemy_wait_time: float = 2.0  # エネミーがドアの前に待機する時間（秒）

@onready var interaction_area: Area3D = $InteractionArea
# ドア本体の当たり判定ノード（名前が違う場合はご自身のシーン名に合わせて変更してください）
@onready var door_collision: CollisionShape3D = $CollisionShape3D

@export var navigation_link: NavigationLink3D

var is_open := false
var _is_moving := false
var _enemy_timer: SceneTreeTimer = null


func _ready() -> void:
	_set_render_layers(self)
	if navigation_link:
		navigation_link.enabled = false
	
	# 初期状態：閉まっているのでコリジョンは有効
	door_collision.disabled = false
	
	interaction_area.body_entered.connect(_on_interaction_area_body_entered)
	interaction_area.body_exited.connect(_on_interaction_area_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player_is_nearby():
		_toggle_door()


func _player_is_nearby() -> bool:
	for body in interaction_area.get_overlapping_bodies():
		if body is CharacterBody3D and not body.is_in_group("enemy"):
			return true
	return false


func _on_interaction_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("enemy") and not is_open:
		_start_enemy_door_timer()


func _on_interaction_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("enemy"):
		if not _has_other_enemies_in_area():
			_cancel_enemy_door_timer()


func _start_enemy_door_timer() -> void:
	if _enemy_timer != null or is_open:
		return
	
	_enemy_timer = get_tree().create_timer(enemy_wait_time)
	await _enemy_timer.timeout
	_enemy_timer = null

	if not is_open and _has_other_enemies_in_area():
		_toggle_door()


func _cancel_enemy_door_timer() -> void:
	_enemy_timer = null


func _has_other_enemies_in_area() -> bool:
	for body in interaction_area.get_overlapping_bodies():
		if body.is_in_group("enemy"):
			return true
	return false


func _toggle_door() -> void:
	if _is_moving:
		return

	_is_moving = true
	
	# 【開く場合】動き出すタイミングでコリジョンを速やかに無効化（すり抜け可能に）
	if not is_open:
		door_collision.disabled = true

	var target_angle := 0.0 if is_open else deg_to_rad(open_angle_degrees)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation:y", target_angle, animation_duration)
	await tween.finished
	
	is_open = not is_open
	
	# 【閉じる場合】ドアが完全に閉まりきってからコリジョンを有効化（再び壁にする）
	if not is_open:
		door_collision.disabled = false
	
	if navigation_link:
		navigation_link.enabled = is_open
	_is_moving = false


func _set_render_layers(node: Node) -> void:
	if node is MeshInstance3D:
		node.layers = 4
	for child in node.get_children():
		_set_render_layers(child)