extends Control


@onready var license_text: RichTextLabel = $ColorRect/MarginContainer/VBoxContainer/LicenseText
@onready var back_button: Button = $ColorRect/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	var text := ""

	# ========================================
	# Godot Engine 
	# ========================================

	text += "[font_size=28][b]Godot Engine[/b][/font_size]\n\n"

	text += "This game uses Godot Engine, available under the following license.\n\n"

	# Godot本体のMIT LicenseをGodotから直接取得
	text += Engine.get_license_text()

	text += "\n\n\n"


	# ========================================
	# Third-party Components
	# ========================================

	text += "[font_size=28][b]Third-party Components[/b][/font_size]\n\n"

	text += "Godot Engine includes software developed by third parties.\n"
	text += "Detailed copyright and license information is included in:\n"
	text += "GODOT_COPYRIGHT.txt\n\n\n"


	# ========================================
	# Zen Kaku Gothic New
	# ========================================

	text += "[font_size=28][b]Zen Kaku Gothic New[/b][/font_size]\n\n"

	text += "Copyright 2022 The Zen Kaku Gothic Project Authors.\n"
	text += "Licensed under the SIL Open Font License, Version 1.1.\n"
	text += "Detailed license information is included in:\n"
	text += "OFL.txt\n"


	# ========================================
	# LicenseTextへ表示
	# ========================================

	license_text.text = text


	# ========================================
	# 戻るボタン
	# ========================================

	if not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://title.tscn")