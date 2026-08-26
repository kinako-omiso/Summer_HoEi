extends Node3D


const SOURCE_LENGTH := 28.0
const BAKE_SEAM_OVERLAP := 0.2


func configure(module_length: float) -> void:
	# Slightly overlap adjacent collision boxes so Recast does not split a long
	# corridor at floating-point seams between scaled source modules.
	var length_scale := (module_length + BAKE_SEAM_OVERLAP) / SOURCE_LENGTH
	$Floor.scale = Vector3(1.0, 1.0, length_scale)
	# The no-light ceiling source is 28m along local X and is rotated so that
	# local X follows the corridor's Z axis.
	$Ceiling.scale = Vector3(length_scale, 1.0, 1.0)
	$WallLeft.scale = Vector3(length_scale, 1.0, 1.0)
	$WallRight.scale = Vector3(length_scale, 1.0, 1.0)
	set_meta("corridor_module_length", module_length)
