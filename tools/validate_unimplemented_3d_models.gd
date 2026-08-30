extends SceneTree


const SCENES := [
	"res://assets/3DModel/pc.tscn",
	"res://assets/3DModel/elevator.tscn",
	"res://assets/3DModel/breaker.tscn",
	"res://assets/3DModel/locker.tscn",
	"res://assets/3DModel/locker_door.tscn",
	"res://assets/3DModel/floor_long.tscn",
	"res://assets/3DModel/pillar_thin.tscn",
	"res://assets/3DModel/pillar_large.tscn",
	"res://assets/3DModel/pillar_medium.tscn",
	"res://assets/3DModel/ceiling_long_with_light.tscn",
	"res://assets/3DModel/ceiling_long_without_light.tscn",
	"res://assets/3DModel/wall_short.tscn",
	"res://assets/3DModel/wall_long.tscn",
	"res://assets/3DModel/corridor_floor.tscn",
	"res://assets/3DModel/corridor_ceiling.tscn",
	"res://assets/3DModel/corridor_ceiling_without_light.tscn",
	"res://assets/3DModel/corridor_wall.tscn",
]

const LIGHT_SCENES := [
	"res://assets/3DModel/ceiling_long_with_light.tscn",
	"res://assets/3DModel/corridor_ceiling.tscn",
]


func _initialize() -> void:
	var failures: Array[String] = []

	for scene_path: String in SCENES:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			failures.append("%s: could not load PackedScene" % scene_path)
			continue

		var instance := packed.instantiate()
		if not instance is StaticBody3D:
			failures.append("%s: root is not StaticBody3D" % scene_path)
		elif instance.collision_layer != 4 or instance.collision_mask != 0:
			failures.append("%s: world collision layer/mask is incorrect" % scene_path)
		if instance.get_script() == null:
			failures.append("%s: world_surface.gd is missing" % scene_path)
		if instance.get_node_or_null("Model") == null:
			failures.append("%s: Model node is missing" % scene_path)

		var collision := instance.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			failures.append("%s: collision shape is missing" % scene_path)
		else:
			var collision_size := (collision.shape as BoxShape3D).size
			if collision_size.x <= 0.0 or collision_size.y <= 0.0 or collision_size.z <= 0.0:
				failures.append("%s: collision shape has an invalid size" % scene_path)

		var expected_lights := 4 if scene_path in LIGHT_SCENES else 0
		var lights := instance.find_children("*", "AreaLight3D", true, false)
		if lights.size() != expected_lights:
			failures.append(
				"%s: expected %d AreaLight3D nodes, found %d"
				% [scene_path, expected_lights, lights.size()]
			)

		instance.free()

	_validate_elevator_door(failures)
	_validate_elevator_enclosure(failures)

	if failures.is_empty():
		print("Validated %d generated 3D model scenes." % SCENES.size())
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _validate_elevator_door(failures: Array[String]) -> void:
	var packed := load("res://assets/3DModel/elevator_door.tscn") as PackedScene
	if packed == null:
		failures.append("elevator door: could not load PackedScene")
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		failures.append("elevator door: root is not Node3D")
		return
	if not instance.is_in_group(&"elevator_doors"):
		failures.append("elevator door: power notification group is missing")
	if not instance.has_method(&"on_power_outage"):
		failures.append("elevator door: outage handler is missing")
	var panel := instance.get_node_or_null("DoorPanel") as AnimatableBody3D
	if panel == null:
		failures.append("elevator door: movable panel is missing")
	elif panel.collision_layer != 4 or panel.collision_mask != 0:
		failures.append("elevator door: world collision layer/mask is incorrect")
	elif panel.get_node_or_null("Model") == null:
		failures.append("elevator door: model is missing")
	elif panel.get_node_or_null("CollisionShape3D") == null:
		failures.append("elevator door: collision shape is missing")
	elif not (panel.get_node("CollisionShape3D") as CollisionShape3D).position.is_zero_approx():
		failures.append("elevator door: collision is offset from the panel origin")
	var proximity_area := instance.get_node_or_null("ProximityArea") as Area3D
	if proximity_area == null or proximity_area.collision_mask != 1:
		failures.append("elevator door: player proximity area is missing or misconfigured")
	get_root().add_child(instance)
	if instance.get("is_open") or (panel != null and not panel.position.is_equal_approx(Vector3.ZERO)):
		failures.append("elevator door: default state is not closed")
	if panel != null:
		var visual_bounds := AABB()
		for mesh: MeshInstance3D in panel.find_children("*", "MeshInstance3D", true, false):
			var mesh_to_panel := panel.global_transform.affine_inverse() * mesh.global_transform
			var mesh_bounds: AABB = mesh_to_panel * mesh.get_aabb()
			visual_bounds = mesh_bounds if visual_bounds.size == Vector3.ZERO else visual_bounds.merge(mesh_bounds)
		if visual_bounds.size == Vector3.ZERO or not visual_bounds.get_center().is_zero_approx():
			failures.append("elevator door: visual mesh is offset from its closed position")
	var player := CharacterBody3D.new()
	get_root().add_child(player)
	player.add_to_group(&"player")
	instance.call(&"_on_proximity_body_entered", player)
	if instance.get("is_open"):
		failures.append("elevator door: opened before the power outage")
	instance.call(&"on_power_outage")
	if not instance.get("is_open"):
		failures.append("elevator door: did not open for a nearby player during the outage")
	instance.call(&"_on_proximity_body_exited", player)
	if instance.get("is_open"):
		failures.append("elevator door: did not close after the player left")
	player.free()
	instance.free()


func _validate_elevator_enclosure(failures: Array[String]) -> void:
	var packed := load("res://assets/3DModel/elevator.tscn") as PackedScene
	if packed == null:
		failures.append("elevator: could not load PackedScene")
		return
	var instance := packed.instantiate() as StaticBody3D
	if instance == null:
		failures.append("elevator: root is not StaticBody3D")
		return
	get_root().add_child(instance)
	var model := instance.get_node_or_null("Model") as Node3D
	if model == null or not model.transform.basis.z.is_equal_approx(Vector3.FORWARD):
		failures.append("elevator: model entrance is not facing the room")
	var enclosure := instance.get_node_or_null("Model/立方体") as MeshInstance3D
	if enclosure == null:
		failures.append("elevator: enclosure mesh is missing")
	elif enclosure.material_override == null:
		failures.append("elevator: doorway-facing wall is still visible")
	var collision_shapes := instance.find_children("CollisionShape*", "CollisionShape3D", false, false)
	if collision_shapes.size() != 5:
		failures.append("elevator: enclosure collision is not split into five surfaces")
	for collision_shape: CollisionShape3D in collision_shapes:
		var box := collision_shape.shape as BoxShape3D
		if box == null:
			failures.append("elevator: enclosure contains a non-box collision shape")
			continue
		var half_size := box.size * 0.5
		var entrance_point := collision_shape.transform.affine_inverse() * Vector3(0.0, 0.0, -4.2)
		if (
			absf(entrance_point.x) <= half_size.x
			and absf(entrance_point.y) <= half_size.y
			and absf(entrance_point.z) <= half_size.z
		):
			failures.append("elevator: entrance is blocked by enclosure collision")
			break
	var left_wall := instance.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var floor := instance.get_node_or_null("CollisionShapeFloor") as CollisionShape3D
	var left_box: BoxShape3D = left_wall.shape as BoxShape3D if left_wall != null else null
	var floor_box: BoxShape3D = floor.shape as BoxShape3D if floor != null else null
	if (
		left_box == null
		or floor_box == null
		or left_box.size.z > 3.2
		or floor_box.size.z > 3.2
	):
		failures.append("elevator: collision extends behind the visible back wall")
	instance.free()
