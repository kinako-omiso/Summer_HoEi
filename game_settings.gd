extends Node


const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "controls_and_audio"
const MIN_AUDIBLE_LINEAR_VOLUME := 0.0001

const BGM_BUS := &"BGM"
const ANNOUNCEMENT_BUS := &"Announcement"
const SFX_BUS := &"SFX"

var mouse_sensitivity_multiplier := 1.0
var bgm_volume := 1.0
var announcement_volume := 1.0
var sfx_volume := 1.0


func _ready() -> void:
	_load_settings()
	apply_audio_settings()


func set_mouse_sensitivity_multiplier(value: float) -> void:
	mouse_sensitivity_multiplier = clampf(value, 0.1, 2.0)
	_save_settings()


func set_bgm_volume(value: float) -> void:
	bgm_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(BGM_BUS, bgm_volume)
	_save_settings()


func set_announcement_volume(value: float) -> void:
	announcement_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(ANNOUNCEMENT_BUS, announcement_volume)
	_save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume(SFX_BUS, sfx_volume)
	_save_settings()


func apply_audio_settings() -> void:
	_apply_bus_volume(BGM_BUS, bgm_volume)
	_apply_bus_volume(ANNOUNCEMENT_BUS, announcement_volume)
	_apply_bus_volume(SFX_BUS, sfx_volume)


func _apply_bus_volume(bus_name: StringName, linear_volume: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		push_warning("Audio bus not found: %s" % bus_name)
		return
	var muted := linear_volume <= 0.0
	AudioServer.set_bus_mute(bus_index, muted)
	AudioServer.set_bus_volume_db(
		bus_index,
		linear_to_db(maxf(linear_volume, MIN_AUDIBLE_LINEAR_VOLUME))
	)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	mouse_sensitivity_multiplier = clampf(
		float(config.get_value(SETTINGS_SECTION, "mouse_sensitivity", 1.0)),
		0.1,
		2.0
	)
	bgm_volume = clampf(float(config.get_value(SETTINGS_SECTION, "bgm_volume", 1.0)), 0.0, 1.0)
	announcement_volume = clampf(
		float(config.get_value(SETTINGS_SECTION, "announcement_volume", 1.0)),
		0.0,
		1.0
	)
	sfx_volume = clampf(float(config.get_value(SETTINGS_SECTION, "sfx_volume", 1.0)), 0.0, 1.0)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, "mouse_sensitivity", mouse_sensitivity_multiplier)
	config.set_value(SETTINGS_SECTION, "bgm_volume", bgm_volume)
	config.set_value(SETTINGS_SECTION, "announcement_volume", announcement_volume)
	config.set_value(SETTINGS_SECTION, "sfx_volume", sfx_volume)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save settings: %s" % error_string(error))
