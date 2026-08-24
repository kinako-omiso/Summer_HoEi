extends CharacterBody3D

@export var speed: float = 4.0
@export var accel: float = 10.0
@export var player: CharacterBody3D

# 敵の視界
@export var view_distance: float = 30.0
@export var view_angle: float = 90.0

# Playerの少し先を予測して追跡する時間
@export var prediction_time: float = 0.25

# NavigationPathを更新する間隔
@export var path_update_interval: float = 0.15

# 最後に見た場所で探索する時間
# この時間で360度回転する
@export var search_time: float = 6.0

# 探索中の回転量
var search_rotation := 0.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var target_point := Vector3.ZERO
var has_target_point := false

# Playerを最後に見た位置
var last_seen_position := Vector3.ZERO
var has_last_seen_position := false

# 探索中かどうか
var is_searching := false

# 探索用タイマー
var search_timer := 0.0

var current_path: PackedVector3Array = []
var path_update_timer := 0.0


func _physics_process(delta: float) -> void:

	# --------------------------------
	# 重力
	# --------------------------------
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	if not player:
		return

	# --------------------------------
	# Playerが見えている場合
	# --------------------------------
	if can_see_player():

		# print("プレイヤーを発見！")

		# 探索状態を解除
		is_searching = false
		search_timer = 0.0
		search_rotation = 0.0

		# 最後に見たPlayerの位置を更新
		last_seen_position = player.global_position
		has_last_seen_position = true

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
	# Playerが見えていない場合
	# --------------------------------
	else:

		# --------------------------------
		# 最後に見た場所へ移動中
		# --------------------------------
		if has_last_seen_position and not is_searching:

			# NavigationPath更新タイマー
			path_update_timer -= delta

			if path_update_timer <= 0.0:

				path_update_timer = path_update_interval

				var map_rid: RID = get_world_3d().get_navigation_map()

				current_path = NavigationServer3D.map_get_path(
					map_rid,
					global_position,
					last_seen_position,
					true
				)

				# Pathがある
				if current_path.size() > 1:

					target_point = current_path[1]
					has_target_point = true

				else:

					has_target_point = false

		# --------------------------------
		# 探索中
		# --------------------------------
		elif is_searching:

			# 探索時間を減らす
			search_timer -= delta

			# 360度をsearch_time秒で回転
			var rotation_amount := TAU / search_time * delta

			rotation.y += rotation_amount
			search_rotation += rotation_amount

			# print(
			# 	"探索中  回転量:",
			# 	rad_to_deg(search_rotation)
			# )

			# 探索中にPlayerを発見
			if can_see_player():

				is_searching = false
				has_last_seen_position = false
				has_target_point = false

				search_rotation = 0.0

				# print("探索中にプレイヤーを発見！")

			# 360度回転完了
			elif search_rotation / 3 >= TAU:

				is_searching = false
				has_last_seen_position = false
				has_target_point = false

				search_rotation = 0.0

				# print("探索終了")

	# --------------------------------
	# Pathに沿って移動
	# --------------------------------
	if has_target_point:

		var diff := Vector3(
			target_point.x - global_position.x,
			0.0,
			target_point.z - global_position.z
		)

		# --------------------------------
		# 現在の目標地点に到達
		# --------------------------------
		if diff.length() < 0.4:

			var closest_index := 1
			var closest_distance := INF

			# 現在地から一番近いPathのポイントを探す
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

			# --------------------------------
			# 次のポイントがある場合
			# --------------------------------
			if closest_index + 1 < current_path.size():

				target_point = current_path[closest_index + 1]

				diff = Vector3(
					target_point.x - global_position.x,
					0.0,
					target_point.z - global_position.z
				)

			# --------------------------------
			# 最後のPathポイントに到着
			# --------------------------------
			else:

				target_point = current_path[current_path.size() - 1]

				has_target_point = false

				# 最後に見た場所へ向かっていた場合
				if has_last_seen_position and not can_see_player():

					is_searching = true
					search_timer = search_time
					search_rotation = 0.0

					# print("最後に見た場所に到着")
					# print("探索開始")

		# --------------------------------
		# 目標地点へ移動
		# --------------------------------
		if diff.length() > 0.05 and has_target_point:

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

			# 敵の向きを進行方向へ変更
			var target_angle := atan2(-dir.x, -dir.z)

			rotation.y = lerp_angle(
				rotation.y,
				target_angle,
				5.0 * delta
			)

	# --------------------------------
	# 目標地点がない場合
	# --------------------------------
	else:

		# --------------------------------
		# 探索中ではない場合は停止
		# --------------------------------
		if not is_searching:

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

		# --------------------------------
		# 探索中も移動は停止
		# --------------------------------
		else:

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

	# --------------------------------
	# 実際に移動
	# --------------------------------
	move_and_slide()


func can_see_player() -> bool:

	if not player:
		return false

	# --------------------------------
	# ① 距離判定
	# --------------------------------
	var to_player := player.global_position - global_position

	var distance := to_player.length()

	if distance > view_distance:
		return false

	# --------------------------------
	# ② 視野角判定
	# --------------------------------
	var forward := -global_transform.basis.z

	var direction_to_player := to_player.normalized()

	var angle := rad_to_deg(
		acos(forward.dot(direction_to_player))
	)

	if angle > view_angle / 2.0:
		return false

	# --------------------------------
	# ③ 壁判定
	# --------------------------------
	var space_state := get_world_3d().direct_space_state

	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 1.0,
		player.global_position + Vector3.UP * 1.0
	)

	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	if result:

		if result.collider != player:
			return false

	return true