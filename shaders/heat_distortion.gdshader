shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// =============================================================================
// Heat Distortion - Screen-space distortion behind engine exhausts
// Spatial shader on a quad mesh parented to ShipModel (no billboard needed).
// Uses hint_screen_texture to sample and distort the scene behind it.
// =============================================================================

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float distortion_scale : hint_range(0.0, 0.1) = 0.02;
uniform float scroll_speed : hint_range(0.0, 5.0) = 1.5;

void fragment() {
	// Animated distortion using layered sine waves
	float t = TIME * scroll_speed;
	vec2 uv_offset = vec2(
		sin(SCREEN_UV.y * 40.0 + t * 3.7) * cos(SCREEN_UV.x * 25.0 + t * 2.1),
		cos(SCREEN_UV.y * 35.0 + t * 2.9) * sin(SCREEN_UV.x * 30.0 + t * 1.8)
	) * distortion_scale * intensity;

	// Soft falloff at quad edges (no hard borders)
	float edge_fade = smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x)
	               * smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.7, UV.y);

	vec2 distorted_uv = SCREEN_UV + uv_offset * edge_fade;
	vec3 col = texture(screen_texture, distorted_uv).rgb;

	// Full opacity where distortion is active — we're replacing the background
	// with its distorted version, not blending on top of it
	ALBEDO = col;
	ALPHA = edge_fade * step(0.01, intensity);
}
