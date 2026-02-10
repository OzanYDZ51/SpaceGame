shader_type canvas_item;

// Full-screen UI post-processing — scanlines + vignette
// Applied on a ColorRect as last child of UIScreenManager

render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float scanline_alpha : hint_range(0.0, 0.1) = 0.015;
uniform float scanline_density : hint_range(100.0, 600.0) = 300.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.2;
uniform float vignette_radius : hint_range(0.0, 2.0) = 0.8;

void fragment() {
	vec4 col = texture(screen_tex, SCREEN_UV);

	// Scanlines
	float scan = pow(abs(sin(SCREEN_UV.y * scanline_density * 3.14159)), 8.0);
	col.rgb -= vec3(scan * scanline_alpha);

	// Vignette
	vec2 vc = SCREEN_UV - 0.5;
	float vd = dot(vc, vc);
	float vig = smoothstep(vignette_radius, vignette_radius * 0.4, vd);
	col.rgb *= mix(1.0 - vignette_strength, 1.0, vig);

	COLOR = col;
}
