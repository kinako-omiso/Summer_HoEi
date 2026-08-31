extends CanvasLayer

@onready var title_label: Label = $Control/VBoxContainer/TitleLabel
@onready var retry_button: Button = $Control/VBoxContainer/RetryButton
@onready var back_button: Button = $Control/VBoxContainer/BackButton
@onready var score_label: Label = $Control/VBoxContainer/ScoreLabel
@onready var settings_panel: GridContainer = $Control/VBoxContainer/SettingsPanel
@onready var mouse_sensitivity_slider: HSlider = $Control/VBoxContainer/SettingsPanel/MouseSensitivitySlider
@onready var mouse_sensitivity_value: Label = $Control/VBoxContainer/SettingsPanel/MouseSensitivityValue
@onready var bgm_volume_slider: HSlider = $Control/VBoxContainer/SettingsPanel/BgmVolumeSlider
@onready var bgm_volume_value: Label = $Control/VBoxContainer/SettingsPanel/BgmVolumeValue
@onready var announcement_volume_slider: HSlider = $Control/VBoxContainer/SettingsPanel/AnnouncementVolumeSlider
@onready var announcement_volume_value: Label = $Control/VBoxContainer/SettingsPanel/AnnouncementVolumeValue
@onready var sfx_volume_slider: HSlider = $Control/VBoxContainer/SettingsPanel/SfxVolumeSlider
@onready var sfx_volume_value: Label = $Control/VBoxContainer/SettingsPanel/SfxVolumeValue

var game_clear = false 

func _ready() -> void:
	settings_panel.hide()
	_sync_settings_controls()
	hide() # 初期状態は非表示

# ゲームオーバー時に呼ぶ関数
func show_game_over() -> void:
	game_clear = false
	title_label.text = "GAME OVER"
	title_label.add_theme_font_size_override("font_size", 180)
	settings_panel.hide()
	score_label.hide()
	retry_button.text = "再挑戦"
	_popup()

# ゲームクリア時に呼ぶ関数
func show_game_clear() -> void:
	title_label.text = "GAME CLEAR!"
	title_label.add_theme_font_size_override("font_size", 180)
	settings_panel.hide()
	var calculated_floors: int = GameManager.floors_number - GameManager.check_retry_count() - 1
	var remaining_floors: int = max(0, calculated_floors)
	score_label.text = "次は" + str(remaining_floors) + "階"
	score_label.show()
	retry_button.text = "次の階へ降りる"
	game_clear = true
	_popup()

# ポーズメニュー時に呼ぶ関数
func show_pause_menu() -> void:
	game_clear = false
	title_label.text = "P A U S E"
	title_label.add_theme_font_size_override("font_size", 96)
	retry_button.text = "やり直す"
	_popup()
	score_label.hide()
	_sync_settings_controls()
	settings_panel.show()
	back_button.show()
	back_button.grab_focus()

# 共通の表示・一時停止処理
func _popup() -> void:
	show()
	back_button.hide()
	get_tree().paused = true

# リトライボタン押下時
func _on_retry_button_pressed() -> void:
	if game_clear:
		GameManager.add_retry_count()
	else:
		GameManager.reset_retry_count()
	
	get_tree().paused = false
	get_tree().reload_current_scene()

# タイトルボタン押下時
func _on_title_button_pressed() -> void:
	GameManager.reset_retry_count()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://title.tscn")

# バックボタン押下時
func _on_back_button_pressed() -> void:
	get_tree().paused = false
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _sync_settings_controls() -> void:
	mouse_sensitivity_slider.set_value_no_signal(GameSettings.mouse_sensitivity_multiplier)
	bgm_volume_slider.set_value_no_signal(GameSettings.bgm_volume)
	announcement_volume_slider.set_value_no_signal(GameSettings.announcement_volume)
	sfx_volume_slider.set_value_no_signal(GameSettings.sfx_volume)
	_update_setting_value_labels()


func _update_setting_value_labels() -> void:
	mouse_sensitivity_value.text = _as_percent(mouse_sensitivity_slider.value)
	bgm_volume_value.text = _as_percent(bgm_volume_slider.value)
	announcement_volume_value.text = _as_percent(announcement_volume_slider.value)
	sfx_volume_value.text = _as_percent(sfx_volume_slider.value)


func _as_percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


func _on_mouse_sensitivity_slider_value_changed(value: float) -> void:
	GameSettings.set_mouse_sensitivity_multiplier(value)
	mouse_sensitivity_value.text = _as_percent(value)


func _on_bgm_volume_slider_value_changed(value: float) -> void:
	GameSettings.set_bgm_volume(value)
	bgm_volume_value.text = _as_percent(value)


func _on_announcement_volume_slider_value_changed(value: float) -> void:
	GameSettings.set_announcement_volume(value)
	announcement_volume_value.text = _as_percent(value)


func _on_sfx_volume_slider_value_changed(value: float) -> void:
	GameSettings.set_sfx_volume(value)
	sfx_volume_value.text = _as_percent(value)
