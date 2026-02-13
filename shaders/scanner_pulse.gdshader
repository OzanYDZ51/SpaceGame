shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// 3D expanding bubble shell — thin ring on a sphere surface
uniform float pulse_radius : hint_range(0.0, 6000.0) = 0.0;
uniform float max_radius : hint_range(100.0, 10000.0) = 5000.0;
uniform vec4 pulse_color : source_color = vec4(0.0, 0.85, 0.95, 1.0);
uniform float time_val : hint_range(0.0, 100.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

varying float vert_dist;  // distance from center in world units

void vertex() {
	// Sphere is always scaled to max_radius. Each vertex sits at normalized
	// distance ~1.0 from center → real distance = length(VERTEX) * max_radius
	vert_dist = length(VERTEX) * max_radius;
}

void fragment() {
	float dist = vert_dist;

	// === Leading edge shell (bright, 100m thick) ===
	float shell_width = 100.0;
	float shell = smoothstep(shell_width, 0.0, abs(dist - pulse_radius));

	// === Echo shell at ~80% ===
	float echo1 = smoothstep(60.0, 0.0, abs(dist - pulse_radius * 0.80)) * 0.18;

	// === Faint echo at ~60% ===
	float echo2 = smoothstep(40.0, 0.0, abs(dist - pulse_radius * 0.58)) * 0.07;

	// === Animated ripple on leading shell ===
	float ripple = sin(dist * 0.05 - time_val * 10.0) * 0.5 + 0.5;
	shell *= 0.75 + ripple * 0.25;

	// === Fresnel: bright at edges (silhouette), visible from inside too ===
	float nv = abs(dot(NORMAL, VIEW));
	float fresnel = pow(1.0 - nv, 1.8);
	// Minimum visibility so the front-facing parts still show
	fresnel = max(fresnel, 0.25);
	shell *= fresnel;

	// === Combine ===
	float alpha = shell + echo1 + echo2;

	// Range fade as pulse nears max
	float range_fade = 1.0 - smoothstep(max_radius * 0.65, max_radius * 0.95, pulse_radius);
	alpha *= range_fade * opacity;

	// HDR bloom
	float brightness = 1.8 + shell * 2.5;
	ALBEDO = pulse_color.rgb * brightness;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
