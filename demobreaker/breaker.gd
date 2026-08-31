extends Node3D

signal lights_out

var brearker_light = false

@onready var breaker_sound_player: AudioStreamPlayer = $BreakerSoundPlayer

func _ready() -> void:
	$Breaker/BreakerLightG.light_energy = 1.0



func _process(delta: float) -> void:
	if brearker_light:
		$Breaker/BreakerLightG.light_energy = 0.0
		$Breaker/BreakerLightR.light_energy = 1.0
		


func _on_interactive_breaker_breaker_off() -> void:
	brearker_light = true
	breaker_sound_player.play()
	lights_out.emit()
	get_tree().call_group(&"elevator_doors", &"on_power_outage")
