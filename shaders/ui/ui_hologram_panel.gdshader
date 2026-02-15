shader_type canvas_item;

// Holographic panel shader — scanlines, grain, flicker, edge glow
// Applied as material on UIComponent Controls
// All effects are scaled by source alpha to avoid artifacts on transparent areas.

uniform vec4 glow_color : source_color = vec4(0.0, 0.85, 1.0, 0.6);
uniform float scanline_density : hint_range(50.0, 400.0) = 200.0;
uniform float scanline_alpha : hint_range(0.0, 0.15) = 0.03;
uniform float grain_intensity : hint_range(0.0, 0.2) = 0.04;
uniform float flicker_intensity : hint_range(0.0, 0.1) = 0.02;
uniform float edge_glow_width : hint_range(0.0, 0.15) = 0.04;
uniform float edge_glow_alpha : hint_range(0.0, 1.0) = 0.3;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float a = tex.a;

	// Only apply effects on opaque areas — prevents artifacts on transparent pixels
	if (a > 0.01) {
		// Scanlines (horizontal, sin^8 for thin lines)
		float scan = pow(abs(sin(UV.y * scanline_density * 3.14159)), 8.0);
		tex.rgb += vec3(scan * scanline_alpha) * a;

		// Film grain noise
		float noise = hash(UV * 1000.0 + TIME * 7.3) * 2.0 - 1.0;
		tex.rgb += vec3(noise * grain_intensity) * a;

		// Subtle flicker (compound sine)
		float flick = sin(TIME * 30.0) * sin(TIME * 17.3) * sin(TIME * 43.7);
		tex.rgb += vec3(flick * flicker_intensity) * a;

		// Edge glow (distance from UV borders)
		float dx = min(UV.x, 1.0 - UV.x);
		float dy = min(UV.y, 1.0 - UV.y);
		float d = min(dx, dy);
		float edge = smoothstep(0.0, edge_glow_width, d);
		float glow = (1.0 - edge) * edge_glow_alpha;
		tex.rgb += glow_color.rgb * glow * a;
	}

	COLOR = tex;
}
