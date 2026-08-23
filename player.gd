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
	# 敵とのあたり判定
	for body in $Area3D.get_overlapping_bodies():
		if body.is_in_group("enemy"):
			if _can_see_enemy(body):
				die()
				return
				
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


# 敵との間に壁はあるか？
func _can_see_enemy(enemy: Node3D) -> bool:

	var space_state := get_world_3d().direct_space_state

	var from := global_position + Vector3.UP * 0.5
	var to := enemy.global_position + Vector3.UP * 0.5

	var query := PhysicsRayQueryParameters3D.create(
		from,
		to
	)

	# 敵のLayer と壁を見る
	query.collision_mask = 2 | 4

	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		return false

	var collider = result["collider"]

	if collider == enemy:
		return true

	return false