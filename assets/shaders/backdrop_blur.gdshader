// Мягкое размытие экрана под модальным окном (аналог CSS backdrop-filter: blur).
// Вешается на полноэкранный ColorRect в CanvasLayer поверх игры: сэмплит уже
// отрисованный кадр (игра + HUD) и выводит его размытым 3x3-гауссом.
shader_type canvas_item;

uniform float blur_radius : hint_range(0.0, 6.0) = 2.5;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE * blur_radius;
	vec4 sum = vec4(0.0);
	sum += texture(screen_tex, SCREEN_UV + vec2(-ps.x, -ps.y)) * 1.0;
	sum += texture(screen_tex, SCREEN_UV + vec2( 0.0,  -ps.y)) * 2.0;
	sum += texture(screen_tex, SCREEN_UV + vec2( ps.x, -ps.y)) * 1.0;
	sum += texture(screen_tex, SCREEN_UV + vec2(-ps.x,  0.0 )) * 2.0;
	sum += texture(screen_tex, SCREEN_UV + vec2( 0.0,   0.0 )) * 4.0;
	sum += texture(screen_tex, SCREEN_UV + vec2( ps.x,  0.0 )) * 2.0;
	sum += texture(screen_tex, SCREEN_UV + vec2(-ps.x,  ps.y)) * 1.0;
	sum += texture(screen_tex, SCREEN_UV + vec2( 0.0,   ps.y)) * 2.0;
	sum += texture(screen_tex, SCREEN_UV + vec2( ps.x,  ps.y)) * 1.0;
	COLOR = sum / 16.0;
}
