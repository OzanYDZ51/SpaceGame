shader_type canvas_item;

// Frosted glass blur for screen backgrounds
// Place on a ColorRect child with PRESET_FULL_RECT

render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 8.0) = 3.0;
uniform vec4 tint_color : source_color = vec4(0.02, 0.012, 0.005, 0.75);
uniform float noise_intensity : hint_range(0.0, 0.1) = 0.02;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE * blur_amount;

	// 9-tap Gaussian approximation
	vec4 col = vec4(0.0);
	col += texture(screen_tex, SCREEN_UV + vec2(-ps.x, -ps.y)) * 0.0625;
	col += texture(screen_tex, SCREEN_UV + vec2(0.0, -ps.y))   * 0.125;
	col += texture(screen_tex, SCREEN_UV + vec2(ps.x, -ps.y))  * 0.0625;
	col += texture(screen_tex, SCREEN_UV + vec2(-ps.x, 0.0))   * 0.125;
	col += texture(screen_tex, SCREEN_UV)                       * 0.25;
	col += texture(screen_tex, SCREEN_UV + vec2(ps.x, 0.0))    * 0.125;
	col += texture(screen_tex, SCREEN_UV + vec2(-ps.x, ps.y))  * 0.0625;
	col += texture(screen_tex, SCREEN_UV + vec2(0.0, ps.y))    * 0.125;
	col += texture(screen_tex, SCREEN_UV + vec2(ps.x, ps.y))   * 0.0625;

	// Tint blend
	col.rgb = mix(col.rgb, tint_color.rgb, tint_color.a);

	// Subtle noise for frosted texture
	float n = hash(SCREEN_UV * 800.0 + TIME * 3.0) * noise_intensity;
	col.rgb += vec3(n);

	COLOR = vec4(col.rgb, 1.0);
}
