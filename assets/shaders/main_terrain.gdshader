shader_type spatial;
render_mode diffuse_burley;

#include "res://assets/shaders/dylearn/clouds.gdshaderinc"
#include "res://assets/shaders/main_terrain_constants.gdshaderinc"

uniform sampler2D soil_texture_01 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D soil_texture_02 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_texture_01 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_texture_02 : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_patch_noise_02 : repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_patch_noise_03 : repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_coverage_mask : repeat_disable, filter_linear_mipmap;

uniform vec2 terrain_origin = vec2(-30.0, -30.0);
uniform vec2 terrain_size = vec2(60.0, 60.0);
uniform float soil_texture_world_size : hint_range(0.5, 8.0, 0.1) = 2.0;
uniform float grass_texture_world_size : hint_range(0.5, 8.0, 0.1) = 2.0;
uniform vec4 soil_tint : source_color = vec4(1.0);
uniform vec4 grass_tint : source_color = vec4(1.0, 1.08, 0.9, 1.0);
uniform vec4 terrain_filter_color : source_color = vec4(1.0);
uniform float terrain_filter_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float cloud_shadow_strength : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform vec4 grass_patch_02_tint : source_color = vec4(1.15, 1.08, 0.92, 1.0);
uniform vec4 grass_patch_03_tint : source_color = vec4(0.76, 0.94, 0.72, 1.0);
uniform float grass_patch_02_scale : hint_range(0.001, 0.5, 0.001) = 0.11;
uniform float grass_patch_03_scale : hint_range(0.001, 0.5, 0.001) = 0.1;
uniform float grass_patch_02_threshold : hint_range(0.0, 1.0, 0.001) = 0.537;
uniform float grass_patch_03_threshold : hint_range(0.0, 1.0, 0.001) = 0.471;
uniform float grass_patch_softness : hint_range(0.001, 0.25, 0.001) = 0.055;
uniform float terrain_roughness : hint_range(0.0, 1.0, 0.01) = 0.96;
uniform float terrain_specular : hint_range(0.0, 1.0, 0.01) = 0.12;

varying vec3 world_position;


float hash_2d(vec2 point) {
	return fract(sin(dot(point, TERRAIN_HASH_VECTOR)) * TERRAIN_HASH_SCALE);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);

	float bottom_left = hash_2d(cell);
	float bottom_right = hash_2d(cell + vec2(1.0, 0.0));
	float top_left = hash_2d(cell + vec2(0.0, 1.0));
	float top_right = hash_2d(cell + vec2(1.0, 1.0));
	return mix(
		mix(bottom_left, bottom_right, fraction.x),
		mix(top_left, top_right, fraction.x),
		fraction.y
	);
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 world_xz = world_position.xz;
	vec2 terrain_uv = clamp((world_xz - terrain_origin) / terrain_size, vec2(0.0), vec2(1.0));
	vec2 soil_uv = world_xz / soil_texture_world_size;
	vec2 grass_uv = world_xz / grass_texture_world_size;

	float soil_mix_noise = value_noise(world_xz * SOIL_MIX_NOISE_SCALE);
	vec3 soil_01 = texture(soil_texture_01, soil_uv).rgb;
	vec3 soil_02 = texture(soil_texture_02, soil_uv + SOIL_SECOND_TEXTURE_OFFSET).rgb;
	vec3 soil = mix(
		soil_01,
		soil_02,
		smoothstep(SOIL_BLEND_START, SOIL_BLEND_END, soil_mix_noise)
	);
	soil *= soil_tint.rgb;

	vec3 grass_01 = texture(grass_texture_01, grass_uv).rgb;
	vec3 grass_02 = texture(
		grass_texture_02,
		grass_uv * GRASS_SECOND_TEXTURE_SCALE + GRASS_SECOND_TEXTURE_OFFSET
	).rgb;
	float grass_mix_noise = value_noise(
		world_xz * GRASS_MIX_NOISE_SCALE + GRASS_MIX_NOISE_OFFSET
	);
	vec3 grass = mix(
		grass_01,
		grass_02,
		smoothstep(GRASS_BLEND_START, GRASS_BLEND_END, grass_mix_noise)
	);
	grass *= grass_tint.rgb;
	float patch_02_noise = texture(grass_patch_noise_02, world_xz * grass_patch_02_scale).r;
	float patch_03_noise = texture(grass_patch_noise_03, world_xz * grass_patch_03_scale).r;
	float patch_02 = smoothstep(
		grass_patch_02_threshold - grass_patch_softness,
		grass_patch_02_threshold + grass_patch_softness,
		patch_02_noise
	);
	float patch_03 = smoothstep(
		grass_patch_03_threshold - grass_patch_softness,
		grass_patch_03_threshold + grass_patch_softness,
		patch_03_noise
	);
	grass *= mix(
		vec3(1.0),
		grass_patch_02_tint.rgb,
		patch_02 * GRASS_PATCH_02_BLEND_STRENGTH
	);
	grass = mix(
		grass,
		grass * grass_patch_03_tint.rgb,
		patch_03 * GRASS_PATCH_03_BLEND_STRENGTH
	);

	float grass_coverage = texture(grass_coverage_mask, terrain_uv).a;
	grass_coverage = smoothstep(
		GRASS_COVERAGE_BLEND_START,
		GRASS_COVERAGE_BLEND_END,
		grass_coverage
	);
	ALBEDO = mix(soil, grass, grass_coverage);
	ALBEDO = mix(ALBEDO, ALBEDO * terrain_filter_color.rgb, terrain_filter_strength);
	float cloud_light = get_cloud_noise(world_position);
	ALBEDO *= mix(1.0, cloud_light, cloud_shadow_strength);
	ROUGHNESS = terrain_roughness;
	SPECULAR = terrain_specular;
}
