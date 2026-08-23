extends CharacterBody3D

@export var speed: float = 4.0
@export var accel: float = 10.0
@export var player: Node3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var target_point := Vector3.ZERO
var has_target_point := false

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	if not player:
		return

	var map_rid: RID = get_world_3d().get_navigation_map()

	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		map_rid,
		global_position,
		player.global_position,
		true
	)

	if path.size() > 1:

		# まだ目標地点を持っていない場合
		if not has_target_point:
			target_point = path[1]
			has_target_point = true

		var diff := Vector3(
			target_point.x - global_position.x,
			0.0,
			target_point.z - global_position.z
		)

		# 現在の目標地点に到達した
		if diff.length() < 0.4:

			# 現在の目標地点がpathのどの辺か探す
			var closest_index := 1
			var closest_distance := INF

			for i in range(1, path.size()):
				var point_diff := Vector3(
					path[i].x - global_position.x,
					0.0,
					path[i].z - global_position.z
				)

				var distance := point_diff.length()

				if distance < closest_distance:
					closest_distance = distance
					closest_index = i

			# 次のポイントへ進む
			if closest_index + 1 < path.size():
				target_point = path[closest_index + 1]
			else:
				target_point = path[path.size() - 1]

			diff = Vector3(
				target_point.x - global_position.x,
				0.0,
				target_point.z - global_position.z
			)

		# 目標地点へ移動
		if diff.length() > 0.05:
			var dir := diff.normalized()

			velocity.x = move_toward(
				velocity.x,
				dir.x * speed,
				accel * delta
			)

			velocity.z = move_toward(
				velocity.z,
				dir.z * speed,
				accel * delta
			)

			var target_angle := atan2(-dir.x, -dir.z)
			rotation.y = lerp_angle(
				rotation.y,
				target_angle,
				0.15
			)

	else:
		# 経路がない
		has_target_point = false

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

	move_and_slide()