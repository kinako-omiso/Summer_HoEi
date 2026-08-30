shader_type spatial;
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);

varying vec3 mesh_position;


void vertex() {
	mesh_position = VERTEX;
}


void fragment() {
	// The enclosure has smoothed/beveled normals, so selecting by normal can
	// leave parts of the front wall visible. Remove the polygons at the local
	// +Z end by position instead. The remaining faces form the cabin interior.
	if (mesh_position.z > 0.9) {
		discard;
	}
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.5;
}
