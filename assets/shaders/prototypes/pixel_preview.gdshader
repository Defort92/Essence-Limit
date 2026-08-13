shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform bool pixelation_enabled = true;
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;
uniform bool palette_enabled = false;
uniform float palette_levels : hint_range(2.0, 32.0, 1.0) = 19.0;


void fragment() {
	vec2 uv = SCREEN_UV;
	if (pixelation_enabled) {
		vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
		vec2 block_size = vec2(max(pixel_size, 1.0));
		uv = (floor(uv * screen_size / block_size) + 0.5) * block_size / screen_size;
	}

	vec4 source = texture(screen_texture, uv);
	if (palette_enabled) {
		float levels = max(palette_levels - 1.0, 1.0);
		source.rgb = floor(source.rgb * levels + 0.5) / levels;
	}
	COLOR = source;
}
