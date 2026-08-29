extends Control


const GAME_SCENE := "res://temp_main.tscn"

@onready var background: ColorRect = $Background
@onready var start_button: Button = $MarginContainer/Menu/StartButton


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	start_button.grab_focus()
	_start_background_animation()


func _start_background_animation() -> void:
	background.color = Color.WHITE
	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(background, "color", Color.BLACK, 7.0)
	tween.tween_property(background, "color", Color.WHITE, 7.0)


func _on_start_button_pressed() -> void:
	var error := get_tree().change_scene_to_file(GAME_SCENE)
	if error != OK:
		push_error("Failed to start the game: %s" % error_string(error))


func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _on_license_and_credits_button_pressed() -> void:
		get_tree().change_scene_to_file("res://license_and_credits.tscn")