@tool
extends StaticBody3D

@export_flags_3d_render var render_layers: int = 4:
	set(value):
		render_layers = value
		_apply_render_layers(self)


func _ready() -> void:
	_apply_render_layers(self)


func _apply_render_layers(node: Node) -> void:
	if node is MeshInstance3D:
		node.layers = render_layers

	for child in node.get_children():
		_apply_render_layers(child)
