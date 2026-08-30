extends Control


@onready var background: ColorRect = $Background
@onready var black_background: ColorRect = $BlackBackground
@onready var logo: TextureRect = $TextureRect


const WAIT_BEFORE_BLACK := 3.0
const WAIT_AFTER_BLACK := 2.0
const FADE_TIME := 3.0


func _ready() -> void:
	# 最初の状態
	background.visible = true
	black_background.visible = false
	logo.modulate.a = 1.0
	
	# 白背景＋ロゴを数秒表示
	await get_tree().create_timer(WAIT_BEFORE_BLACK).timeout
	
	# 白背景 → 黒背景
	background.visible = false
	black_background.visible = true
	
	# 黒背景＋ロゴを数秒表示
	await get_tree().create_timer(WAIT_AFTER_BLACK).timeout
	
	# ロゴをフェードアウト
	var tween := create_tween()
	tween.tween_property(logo, "modulate:a", 0.0, FADE_TIME)
	
	await tween.finished
	
	# タイトル画面へ
	get_tree().change_scene_to_file("res://title.tscn")
