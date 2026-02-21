shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Scanner Pulse — expanding sonar bubble.
// Fresnel rim effect: bright at edges (shell silhouette), near-transparent at center.
// abs(dot) works from both inside AND outside the sphere — no need for two spheres.

uniform vec4 pulse_color : source_color = vec4(0.35, 0.75, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 5.0) = 1.8;
uniform float brightness : hint_range(0.0, 12.0) = 6.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Fresnel: 1.0 at silhouette edges, 0.0 face-on. abs() works from inside + outside.
	float view_cos = abs(dot(NORMAL, VIEW));
	float rim = pow(1.0 - view_cos, rim_power);

	// Subtle inner fill so the bubble feels volumetric, not just a wire rim
	float inner = (1.0 - rim) * 0.06;

	// Animated ripple driven by engine time
	float ripple = 0.82 + sin(TIME * 11.0) * 0.18;

	ALBEDO = pulse_color.rgb * brightness * ripple * fade;
	ALPHA = clamp((rim + inner) * fade * ripple, 0.0, 1.0);
}
