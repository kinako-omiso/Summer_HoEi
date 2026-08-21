extends Node3D

signal lights_out

func _ready() -> void:
	pass



func _process(delta: float) -> void:
	pass


func _on_interactive_breaker_breaker_off() -> void:
	lights_out.emit()
