extends Node3D


const SOURCE_LENGTH := 28.0
const BAKE_SEAM_OVERLAP := 0.2
const SOURCE_WALL_HEIGHT := 6.0
const ELEVATOR_HEADER_HEIGHT := 1.380096
const ELEVATOR_HEADER_CENTER_Y := 5.459953


func configure(
	module_length: float,
	ceiling_scene: PackedScene,
	ceiling_source_runs_along_x: bool,
	elevator_side: String = "",
	elevator_opening_width: float = 0.0,
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
	if not elevator_side.is_empty():
		_create_elevator_opening(
			elevator_side,
			module_length,
			elevator_opening_width,
		)
	set_meta("corridor_module_length", module_length)


func _create_elevator_opening(
	elevator_side: String,
	module_length: float,
	opening_width: float,
) -> void:
	if opening_width <= 0.0 or module_length + 0.001 < opening_width:
		push_error("Corridor is too short for its elevator opening.")
		return
	var target_wall := (
		$WallLeft as Node3D
		if elevator_side == "left"
		else $WallRight as Node3D
	)
	var wall_name := target_wall.name
	var second_segment := target_wall.duplicate() as Node3D
	var header_segment := target_wall.duplicate() as Node3D
	var segment_length := (module_length - opening_width) * 0.5
	var segment_offset := opening_width * 0.5 + segment_length * 0.5
	target_wall.name = "%sA" % wall_name
	second_segment.name = "%sB" % wall_name
	header_segment.name = "%sHeader" % wall_name
	add_child(second_segment)
	add_child(header_segment)
	target_wall.scale.x = segment_length / SOURCE_LENGTH
	second_segment.scale.x = segment_length / SOURCE_LENGTH
	header_segment.scale = Vector3(
		opening_width / SOURCE_LENGTH,
		ELEVATOR_HEADER_HEIGHT / SOURCE_WALL_HEIGHT,
		1.0,
	)
	target_wall.position.z = -segment_offset
	second_segment.position.z = segment_offset
	header_segment.position = Vector3(
		target_wall.position.x,
		ELEVATOR_HEADER_CENTER_Y,
		0.0,
	)
	set_meta("elevator_opening_side", elevator_side)
	set_meta("elevator_opening_width", opening_width)
