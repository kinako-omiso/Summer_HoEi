extends CharacterBody3D

@export var speed: float = 4.0
@export var accel: float = 10.0
@export var player: Node3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	if not player:
		return

	# ワールドのナビゲーションマップを取得
	var map_rid: RID = get_world_3d().get_navigation_map()

	# プレイヤーへの迂回経路（ポイントの配列）を計算
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		map_rid,
		global_position,
		player.global_position,
		true
	)

	# 経路が存在する場合（path[0]は現在地、path[1]が最初の中継角ポイント）
	if path.size() > 1:
		var next_point: Vector3 = path[1]
		var current_pos: Vector3 = global_position
		
		# 水平方向の差分のみ計算
		var diff: Vector3 = Vector3(next_point.x - current_pos.x, 0.0, next_point.z - current_pos.z)
		
		# 中継ポイントに近すぎる場合は次のポイントへ視点を切り替えるため、少し離れている時だけ移動
		if diff.length() > 0.2:
			var dir: Vector3 = diff.normalized()
			
			velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
			velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
			
			# スムーズな回転
			var target_angle: float = atan2(-dir.x, -dir.z)
			rotation.y = lerp_angle(rotation.y, target_angle, 0.15)
		else:
			# 中継地点の角に到達したら一時減速してスムーズに曲がる
			velocity.x = move_toward(velocity.x, 0.0, accel * delta)
			velocity.z = move_toward(velocity.z, 0.0, accel * delta)

	move_and_slide()