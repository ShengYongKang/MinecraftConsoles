shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

uniform sampler2D atlas_texture : source_color, filter_nearest, repeat_disable;
uniform float atlas_size = 16.0;
uniform float tile_resolution = 16.0;
uniform bool use_vertex_lighting = false;

void fragment() {
	vec2 tile_index = UV2;
	vec2 repeat_uv = fract(UV);
	float inset = 0.5 / max(tile_resolution, 1.0);
	vec2 tile_uv = mix(vec2(inset), vec2(1.0 - inset), repeat_uv);
	vec2 atlas_uv = (tile_index + tile_uv) / atlas_size;
	vec4 albedo = texture(atlas_texture, atlas_uv);
	vec3 lighting = vec3(1.0);

	if (use_vertex_lighting) {
		lighting = COLOR.rgb;
	}

	ALBEDO = albedo.rgb * lighting;
	ROUGHNESS = 1.0;
}
