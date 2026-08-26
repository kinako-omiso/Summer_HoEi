extends SceneTree


const SCENES := [
	"res://assets/3DModel/pc.tscn",
	"res://assets/3DModel/elevator.tscn",
	"res://assets/3DModel/elevator_door.tscn",
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

	if failures.is_empty():
		print("Validated %d generated 3D model scenes." % SCENES.size())
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)
