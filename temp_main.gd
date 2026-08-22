extends Node
# テンプレートを使用している

@onready var world_environment = $WorldEnvironment
# 初期カメラ設定
var camera_change = 1


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# プレイヤーカメラでスタート
	$Player/PlayerCamera.make_current()
	# マウスカーソルをキャプチャーモードにする
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if world_environment and world_environment.environment:
		# ゲーム開始時に背景エネルギーを 0.0 にして真っ暗にする
		world_environment.environment.background_energy_multiplier = 1.0

# 作業がしやすいように三人称視点との切り替えを Cキー で行えるようにする
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if camera_change == -1 and Input.is_action_just_pressed("debug_camera_change"):
		$Player/PlayerCamera.make_current()
		camera_change = 1

	elif camera_change == 1 and Input.is_action_just_pressed("debug_camera_change"):
		$MainCamera.make_current()
		camera_change = -1

# 仮死亡表示
func _on_player_hit() -> void:
	print("you die")

# 消灯システム
func _on_breaker_lights_out() -> void:
	get_tree().set_group("lights", "light_energy", 0.0)
	get_tree().set_group("player_lights", "light_energy", 1.0)
	get_tree().set_group("robot_lights", "light_energy", 6.0)
