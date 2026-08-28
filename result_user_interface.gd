extends CanvasLayer

@onready var title_label: Label = $Control/VBoxContainer/TitleLabel
@onready var retry_button: Button = $Control/VBoxContainer/RetryButton

func _ready() -> void:
	hide() # 初期状態は非表示

# ゲームオーバー時に呼ぶ関数
func show_game_over() -> void:
	title_label.text = "GAME OVER"
	retry_button.text = "再挑戦"
	_popup()

# ゲームクリア時に呼ぶ関数
func show_game_clear() -> void:
	title_label.text = "GAME CLEAR!"
	retry_button.text = "もう一度遊ぶ"
	_popup()

# 共通の表示・一時停止処理
func _popup() -> void:
	show()
	get_tree().paused = true

# リトライボタン押下時
func _on_retry_button_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

# タイトルボタン押下時
func _on_title_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://title.tscn")
