@tool
extends StaticBody3D


const OPEN_FRONT_MATERIAL := preload("res://assets/materials/elevator_open_front.tres")

@export_flags_3d_render var render_layers: int = 4:
	set(value):
		render_layers = value
		_apply_render_layers(self)


func _ready() -> void:
	_apply_render_layers(self)
	var enclosure := get_node_or_null("Model/立方体") as MeshInstance3D
	if enclosure == null:
		push_warning("Elevator enclosure mesh was not found; its entrance wall remains visible.")
		return
	enclosure.material_override = OPEN_FRONT_MATERIAL


func _apply_render_layers(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).layers = render_layers
	for child: Node in node.get_children():
		_apply_render_layers(child)
