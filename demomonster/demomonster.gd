extends CharacterBody3D


@export var speed: float = 4.0
@export var accel: float = 10.0
@export var player: CharacterBody3D

# 敵の視界
@export var view_distance: float = 30.0
@export var view_angle: float = 180.0

# Playerの少し先を予測して追跡する時間
@export var prediction_time: float = 0.25

# NavigationPathを更新する間隔
@export var path_update_interval: float = 0.15

# 最後に見た場所で探索する時間
# この時間で360度回転する
@export var search_time: float = 6.0

# Playerがインタラクションした場所を検知する距離
# Inspectorから変更可能
@export var interaction_detection_distance: float = 30.0
@export var interaction_detection_boost: float = 1.5

# Playerを最後に視認・インタラクション検知してから
# 強制的にPlayerの位置を取得するまでの時間
# Inspectorから変更可能
@export var forced_detection_time: float = 30.0


# ============================================================
# 敵の状態
# ============================================================

enum State {
	IDLE,                 # 何もしていない
	CHASE,                # Playerを追跡
	MOVE_TO_LAST_SEEN,    # Playerを最後に見た場所へ移動
	MOVE_TO_INTERACTION,  # Playerがインタラクションした場所へ移動
	SEARCH                # 最後に見た場所などで探索
}

var state := State.IDLE


func is_chasing_player() -> bool:
	return state == State.CHASE


# ============================================================
# 共通変数
# ============================================================

var gravity: float = ProjectSettings.get_setting(
	"physics/3d/default_gravity"
)

# 現在向かっているPathのポイント
var target_point := Vector3.ZERO
var has_target_point := false

# Playerを最後に見た位置
var last_seen_position := Vector3.ZERO
var has_last_seen_position := false

# Playerがインタラクションした位置
var interaction_position := Vector3.ZERO
var has_interaction_position := false

# NavigationPath
var current_path: PackedVector3Array = []
var path_update_timer := 0.0

# 探索用
var search_timer := 0.0
var search_rotation := 0.0

# インタラクション地点へのPath計算中か
# NavigationLinkをONにしている最中の重複処理を防ぐ
var interaction_path_update_pending := false

# Playerを最後に視認・インタラクション検知してからの時間
var forced_detection_timer := 0.0

func _ready():
	forced_detection_timer = forced_detection_time - 3



# ============================================================
# メイン処理
# ============================================================

func _physics_process(delta: float) -> void:

	# --------------------------------------------------------
	# 重力
	# --------------------------------------------------------

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

	if not player:
		return


	# ========================================================
	# Playerの視認判定
	# ========================================================

	var player_is_visible := can_see_player()


	# ========================================================
	# 強制検知タイマー
	# ========================================================

	if player_is_visible:

		# Playerを見ているのでタイマーをリセット
		forced_detection_timer = 0.0

	else:

		# Playerを見ていないので時間を進める
		forced_detection_timer += delta


		# ----------------------------------------------------
		# 一定時間Playerを見ていなかった場合
		# ----------------------------------------------------

		if forced_detection_timer >= forced_detection_time:

			# Playerの現在位置を強制的に取得
			interaction_position = player.global_position
			has_interaction_position = true

			# 強制検知したのでタイマーをリセット
			forced_detection_timer = 0.0

			# CHASE中でなければPlayerの位置へ向かう
			if state != State.CHASE:

				state = State.MOVE_TO_INTERACTION

				# 現在のPathをリセット
				has_target_point = false
				path_update_timer = 0.0

			else:

				# CHASE中なら通常の追跡を継続
				last_seen_position = player.global_position
				has_last_seen_position = true


	# ========================================================
	# Playerを発見した場合
	# ========================================================

	if player_is_visible:

		# ----------------------------------------------------
		# Playerを発見したらCHASEへ
		# ----------------------------------------------------

		if state != State.CHASE:
			state = State.CHASE

			# 探索関連をリセット
			search_timer = 0.0
			search_rotation = 0.0

			# インタラクション移動を解除
			has_interaction_position = false

		# 最後に見たPlayerの位置を更新
		last_seen_position = player.global_position
		has_last_seen_position = true


	# ========================================================
	# Playerが見えていない場合
	# ========================================================

	else:

		# ----------------------------------------------------
		# CHASE中にPlayerを見失った
		# ----------------------------------------------------

		if state == State.CHASE:

			if has_last_seen_position:
				state = State.MOVE_TO_LAST_SEEN

			else:
				state = State.IDLE


	# ========================================================
	# Stateごとの処理
	# ========================================================

	match state:

		# ====================================================
		# IDLE
		# ====================================================

		State.IDLE:

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


		# ====================================================
		# CHASE
		# ====================================================

		State.CHASE:

			# NavigationPath更新タイマー
			path_update_timer -= delta

			if path_update_timer <= 0.0:

				path_update_timer = path_update_interval

				var map_rid: RID = get_world_3d().get_navigation_map()

				# Playerの少し先を予測
				var predicted_position: Vector3 = (
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


		# ====================================================
		# MOVE_TO_LAST_SEEN
		# ====================================================

		State.MOVE_TO_LAST_SEEN:

			# Playerが再び見えたらCHASEへ
			if player_is_visible:

				state = State.CHASE

				last_seen_position = player.global_position
				has_last_seen_position = true

				search_timer = 0.0
				search_rotation = 0.0

			else:

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


		# ====================================================
		# MOVE_TO_INTERACTION
		# ====================================================

		State.MOVE_TO_INTERACTION:

			# Playerが再び見えたらCHASEへ
			if player_is_visible:

				state = State.CHASE

				last_seen_position = player.global_position
				has_last_seen_position = true

				has_interaction_position = false

				search_timer = 0.0
				search_rotation = 0.0

			else:

				# NavigationPath更新タイマー
				path_update_timer -= delta

				if path_update_timer <= 0.0:

					# すでにインタラクション地点への
					# Path計算を開始している場合は重複させない
					if not interaction_path_update_pending:

						path_update_timer = path_update_interval

						interaction_path_update_pending = true

						_update_interaction_path()


		# ====================================================
		# SEARCH
		# ====================================================

		State.SEARCH:

			# Playerを発見したらCHASEへ
			if player_is_visible:

				state = State.CHASE

				last_seen_position = player.global_position
				has_last_seen_position = true

				search_timer = 0.0
				search_rotation = 0.0

				has_target_point = false

				has_interaction_position = false

			else:

				# 探索時間を減らす
				search_timer -= delta

				# 360度をsearch_time秒で回転
				var rotation_amount: float = (
					TAU / search_time * delta
				)

				rotation.y += rotation_amount
				search_rotation += rotation_amount

				# 探索終了
				if search_timer <= 0.0:

					state = State.IDLE

					has_last_seen_position = false
					has_interaction_position = false
					has_target_point = false

					search_rotation = 0.0


	# ========================================================
	# Pathに沿って移動
	# ========================================================

	if has_target_point:

		var diff := Vector3(
			target_point.x - global_position.x,
			0.0,
			target_point.z - global_position.z
		)


		# ----------------------------------------------------
		# 現在の目標地点に到達
		# ----------------------------------------------------

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


			# ------------------------------------------------
			# 次のポイントがある場合
			# ------------------------------------------------

			if closest_index + 1 < current_path.size():

				target_point = current_path[closest_index + 1]

				diff = Vector3(
					target_point.x - global_position.x,
					0.0,
					target_point.z - global_position.z
				)


			# ------------------------------------------------
			# 最後のPathポイントに到着
			# ------------------------------------------------

			else:

				target_point = current_path[
					current_path.size() - 1
				]

				has_target_point = false


				# --------------------------------------------
				# 最後に見た場所へ到着した
				# --------------------------------------------

				if state == State.MOVE_TO_LAST_SEEN:

					# Playerがまだ見えていなければ探索開始
					if not player_is_visible:

						state = State.SEARCH

						search_timer = search_time
						search_rotation = 0.0

					else:

						state = State.CHASE


				# --------------------------------------------
				# インタラクションした場所へ到着
				# --------------------------------------------

				elif state == State.MOVE_TO_INTERACTION:

					# 到着したら探索開始
					if not player_is_visible:

						state = State.SEARCH

						search_timer = search_time
						search_rotation = 0.0

						has_interaction_position = false

					else:

						state = State.CHASE

						has_interaction_position = false


		# ----------------------------------------------------
		# 目標地点へ移動
		# ----------------------------------------------------

		if diff.length() > 0.05 and has_target_point:

			var dir := diff.normalized()

			var target_velocity := dir * speed

			if state != State.CHASE:
				target_velocity *= interaction_detection_boost

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
			var target_angle := atan2(
				-dir.x,
				-dir.z
			)

			rotation.y = lerp_angle(
				rotation.y,
				target_angle,
				5.0 * delta
			)


	# ========================================================
	# 目標地点がない場合
	# ========================================================

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


	# ========================================================
	# 実際に移動
	# ========================================================

	move_and_slide()


# ============================================================
# Playerからインタラクション地点を受け取る
# ============================================================

func receive_interaction_position(position: Vector3) -> void:

	# インタラクションを検知したので
	# 強制検知タイマーをリセット
	forced_detection_timer = 0.0

	# Playerから送られてきた位置とEnemyの距離を計算
	var distance := global_position.distance_to(position)

	# 探知距離より遠ければ無視
	if distance > interaction_detection_distance:
		return

	# インタラクションした場所を保存
	interaction_position = position
	has_interaction_position = true

	# 現在Playerを追跡中ならCHASEを優先
	if state == State.CHASE:
		return

	# それ以外ならインタラクション地点へ向かう
	state = State.MOVE_TO_INTERACTION

	# 現在のPathをリセット
	has_target_point = false
	path_update_timer = 0.0


# ============================================================
# インタラクション地点へのPathを更新
# ============================================================

func _update_interaction_path() -> void:

	if not has_interaction_position:
		interaction_path_update_pending = false
		return

	var door_links: Array[NavigationLink3D] = []
	var original_enabled_states: Array[bool] = []

	var doors := get_tree().get_nodes_in_group("doors")


	# ========================================================
	# ドアのNavigationLinkを取得して一時的にON
	# ========================================================

	for door in doors:

		if door is NavigationLink3D:

			var link: NavigationLink3D = door

			# 元の状態を保存
			door_links.append(link)
			original_enabled_states.append(link.enabled)

			# Path計算中だけON
			link.enabled = true


	# ========================================================
	# NavigationServerの更新を待つ
	# ========================================================

	await get_tree().physics_frame
	await get_tree().physics_frame


	# ========================================================
	# NavigationMapを取得
	# ========================================================

	var map_rid: RID = get_world_3d().get_navigation_map()


	# ========================================================
	# ドアをONにした状態でPathを計算
	# ========================================================

	var new_path: PackedVector3Array = NavigationServer3D.map_get_path(
		map_rid,
		global_position,
		interaction_position,
		true
	)


	# ========================================================
	# ドアを元の状態に戻す
	# ========================================================

	for i in range(door_links.size()):

		door_links[i].enabled = original_enabled_states[i]


	# ========================================================
	# PathをEnemyに設定
	# ========================================================

	if state == State.MOVE_TO_INTERACTION \
	and has_interaction_position:

		current_path = new_path

		if current_path.size() > 1:

			target_point = current_path[1]
			has_target_point = true

		else:

			has_target_point = false


	interaction_path_update_pending = false


# ============================================================
# Playerが見えているか判定
# ============================================================

func can_see_player() -> bool:

	if not player:
		return false


	# --------------------------------------------------------
	# ① 距離判定
	# --------------------------------------------------------

	var to_player := player.global_position - global_position

	var distance := to_player.length()

	if distance > view_distance:
		return false


	# --------------------------------------------------------
	# ② 視野角判定
	# --------------------------------------------------------

	var forward := -global_transform.basis.z

	var direction_to_player := to_player.normalized()

	var angle := rad_to_deg(
		acos(forward.dot(direction_to_player))
	)

	if angle > view_angle / 2.0:
		return false


	# --------------------------------------------------------
	# ③ 壁判定
	# --------------------------------------------------------

	var space_state := get_world_3d().direct_space_state

	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 1.0,
		player.global_position + Vector3.UP * 1.0
	)

	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	if result:

		# Player以外にRayが当たったら見えていない
		if result.collider != player:
			return false

	return true
