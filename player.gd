extends CharacterBody3D
# テンプレートを使用している、新たに付け足した部分は別途コメントを残しているはず

# mainへの敵につかまった判定のシグナル
signal hit

@export var SPEED = 5.0
const JUMP_VELOCITY = 4.5

# カメラ操作（Y軸回転はプレイヤーの回転としてカメラは追従させる）
func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * 0.005)
		$PlayerCamera.rotate_x(-event.relative.y * 0.005)

# Playerの操作
func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# ジャンプって必要？
	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# wasd と方向キーで動く
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

# シグナル発信とプレイヤーの破棄
func die():
	hit.emit()
	queue_free()

# 敵とのあたり判定
func _on_area_3d_body_entered(body: Node3D) -> void:
	die()
