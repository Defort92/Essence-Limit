shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;

uniform vec3 outline_color : source_color = vec3(0.055, 0.035, 0.075);
uniform float thickness : hint_range(1.0, 4.0, 0.25) = 1.0;
uniform float outline_strength : hint_range(0.0, 1.0, 0.05) = 0.50;
uniform float depth_threshold : hint_range(0.001, 0.2, 0.001) = 0.025;
uniform float normal_threshold : hint_range(0.01, 1.0, 0.01) = 0.28;

uniform bool exclude_marked_surfaces = true;
uniform float excluded_roughness_marker : hint_range(0.01, 0.99, 0.001) = 0.123;
uniform float exclusion_tolerance : hint_range(0.001, 0.05, 0.001) = 0.008;

uniform bool dark_edges_enabled = true;
uniform vec3 dark_edge_color : source_color = vec3(0.58, 0.52, 0.68);
uniform float dark_surface_threshold : hint_range(0.01, 0.3, 0.01) = 0.02;
uniform float dark_edge_strength : hint_range(0.0, 1.0, 0.05) = 0.05;


void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


float linear_depth(vec2 uv, mat4 inverse_projection) {
	float raw_depth = texture(depth_texture, uv).x;
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
	vec4 view = inverse_projection * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}


bool is_excluded_surface(float roughness) {
	return exclude_marked_surfaces
		&& abs(roughness - excluded_roughness_marker) <= exclusion_tolerance;
}


void fragment() {
	vec2 texel = vec2(thickness) / VIEWPORT_SIZE;
	vec2 offsets[4] = {
		vec2(texel.x, 0.0),
		vec2(-texel.x, 0.0),
		vec2(0.0, texel.y),
		vec2(0.0, -texel.y)
	};

	float center_depth = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec4 center_normal_roughness = texture(normal_texture, SCREEN_UV);
	vec3 center_normal = center_normal_roughness.rgb * 2.0 - 1.0;
	bool center_excluded = is_excluded_surface(center_normal_roughness.a);
	float depth_edge = 0.0;
	float normal_edge = 0.0;
	vec3 source = texture(screen_texture, SCREEN_UV).rgb;
	vec3 surface_color = source;
	float surface_depth = center_depth;

	for (int index = 0; index < 4; index++) {
		vec2 sample_uv = clamp(SCREEN_UV + offsets[index], vec2(0.0), vec2(1.0));
		float neighbor_depth = linear_depth(sample_uv, INV_PROJECTION_MATRIX);
		vec4 neighbor_normal_roughness = texture(normal_texture, sample_uv);
		vec3 neighbor_normal = neighbor_normal_roughness.rgb * 2.0 - 1.0;
		bool neighbor_excluded = is_excluded_surface(neighbor_normal_roughness.a);
		if (center_excluded || neighbor_excluded) {
			continue;
		}
		// At the outer half of a silhouette SCREEN_UV belongs to the background.
		// Use the closest visible surface so a red object gets a dark-red edge
		// instead of being classified from the nearly black background pixel.
		if (neighbor_depth < surface_depth) {
			surface_depth = neighbor_depth;
			surface_color = texture(screen_texture, sample_uv).rgb;
		}
		float relative_depth = abs(neighbor_depth - center_depth) / max(center_depth, 0.25);
		depth_edge = max(depth_edge, relative_depth);
		normal_edge = max(normal_edge, 1.0 - max(dot(center_normal, neighbor_normal), 0.0));
	}

	depth_edge = smoothstep(depth_threshold, depth_threshold * 2.0, depth_edge);
	normal_edge = smoothstep(normal_threshold, min(normal_threshold * 2.0, 1.0), normal_edge);
	float luminance = dot(surface_color, vec3(0.2126, 0.7152, 0.0722));
	float dark_factor = 0.0;
	if (dark_edges_enabled) {
		dark_factor = 1.0 - smoothstep(
			dark_surface_threshold * 0.6,
			dark_surface_threshold,
			luminance
		);
	}
	// Regular objects keep their hue in a darker contour. Only surfaces below
	// the strict darkness threshold transition to the light edge color.
	vec3 regular_edge_color = mix(surface_color * 0.28, outline_color, 0.12);
	vec3 adaptive_color = mix(regular_edge_color, dark_edge_color, dark_factor);
	float adaptive_strength = mix(outline_strength, dark_edge_strength, dark_factor);
	float edge = clamp(max(depth_edge, normal_edge) * adaptive_strength, 0.0, 1.0);
	ALBEDO = mix(source, adaptive_color, edge);
}
