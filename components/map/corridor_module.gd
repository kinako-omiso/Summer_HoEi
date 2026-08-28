extends Node3D


const SOURCE_LENGTH := 28.0
const BAKE_SEAM_OVERLAP := 0.2


func configure(
	module_length: float,
	ceiling_scene: PackedScene,
	ceiling_source_runs_along_x: bool,
) -> void:
	# Slightly overlap adjacent collision boxes so Recast does not split a long
	# corridor at floating-point seams between scaled source modules.
	var length_scale := (module_length + BAKE_SEAM_OVERLAP) / SOURCE_LENGTH
	$Floor.scale = Vector3(1.0, 1.0, length_scale)
	var ceiling_surface := ceiling_scene.instantiate() as Node3D
	ceiling_surface.name = "CeilingSurface"
	$Ceiling.add_child(ceiling_surface)
	if ceiling_source_runs_along_x:
		# The no-light source is 28m along local X. Rotate it so that its long
		# side follows the corridor's local Z axis.
		ceiling_surface.rotation.y = PI * 0.5
		ceiling_surface.scale = Vector3(length_scale, 1.0, 1.0)
	else:
		# The lighted source is already 28m along local Z.
		ceiling_surface.scale = Vector3(1.0, 1.0, length_scale)
	$WallLeft.scale = Vector3(length_scale, 1.0, 1.0)
	$WallRight.scale = Vector3(length_scale, 1.0, 1.0)
	set_meta("corridor_module_length", module_length)
