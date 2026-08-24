extends CharacterBody3D

@export var speed: float = 4.0
@export var accel: float = 10.0
@export var player: CharacterBody3D

@export var view_distance: float = 10.0
@export var view_angle: float = 90.0

# Playerの少し先を予測して追跡する時間
@export var prediction_time: float = 0.25

# NavigationPathを更新する間隔
@export var path_update_interval: float = 0.15

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var target_point := Vector3.ZERO
var has_target_point := false

var current_path: PackedVector3Array = []
var path_update_timer := 0.0


func _physics_process(delta: float) -> void:

	
	# 重力
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	if not player:
		return

	if can_see_player():
		print("プレイヤーを発見！")


	# --------------------------------
	# NavigationPathを一定間隔で更新
	# --------------------------------
	path_update_timer -= delta

	if path_update_timer <= 0.0:
		path_update_timer = path_update_interval

		var map_rid: RID = get_world_3d().get_navigation_map()

		# Playerの少し先を予測
		var predicted_position := (
			player.global_position
			+ player.velocity * prediction_time
		)

		current_path = NavigationServer3D.map_get_path(
			map_rid,
			global_position,
			predicted_position,
			true
		)

		# 新しいPathを取得したら目標地点を更新
		if current_path.size() > 1:
			target_point = current_path[1]
			has_target_point = true
		else:
			has_target_point = false

	# --------------------------------
	# Pathに沿って移動
	# --------------------------------
	if has_target_point:

		var diff := Vector3(
			target_point.x - global_position.x,
			0.0,
			target_point.z - global_position.z
		)

		# 現在の目標地点に到達した
		if diff.length() < 0.4:

			# 現在地から一番近いPathのポイントを探す
			var closest_index := 1
			var closest_distance := INF

			for i in range(1, current_path.size()):

				var point_diff := Vector3(
					current_path[i].x - global_position.x,
					0.0,
					current_path[i].z - global_position.z
				)

				var distance := point_diff.length()

				if distance < closest_distance:
					closest_distance = distance
					closest_index = i

			# 次のポイントへ
			if closest_index + 1 < current_path.size():
				target_point = current_path[closest_index + 1]
			else:
				target_point = current_path[current_path.size() - 1]

			diff = Vector3(
				target_point.x - global_position.x,
				0.0,
				target_point.z - global_position.z
			)

		# --------------------------------
		# 目標地点へ移動
		# --------------------------------
		if diff.length() > 0.05:

			var dir := diff.normalized()

			var target_velocity := dir * speed

			velocity.x = move_toward(
				velocity.x,
				target_velocity.x,
				accel * delta
			)

			velocity.z = move_toward(
				velocity.z,
				target_velocity.z,
				accel * delta
			)

			# 敵の向きを進行方向へ滑らかに変更
			var target_angle := atan2(-dir.x, -dir.z)

			rotation.y = lerp_angle(
				rotation.y,
				target_angle,
				5.0 * delta
			)

	else:
		# --------------------------------
		# 経路がない場合
		# --------------------------------
		velocity.x = move_toward(
			velocity.x,
			0.0,
			accel * delta
		)

		velocity.z = move_toward(
			velocity.z,
			0.0,
			accel * delta
		)

	# 実際に移動
	move_and_slide()


func can_see_player() -> bool:
	if not player:
		return false

	# ① 距離判定
	var to_player := player.global_position - global_position
	var distance := to_player.length()

	if distance > view_distance:
		return false

	# ② 視野角判定
	var forward := -global_transform.basis.z
	var direction_to_player := to_player.normalized()

	var angle := rad_to_deg(
		acos(forward.dot(direction_to_player))
	)

	if angle > view_angle / 2.0:
		return false

	# ③ 壁判定
	var space_state := get_world_3d().direct_space_state

	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		player.global_position
	)

	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	if result:
		if result.collider != player:
			return false

	return true