shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform float pulse_radius : hint_range(0.0, 6000.0) = 0.0;
uniform float max_radius : hint_range(100.0, 10000.0) = 5000.0;
uniform float ring_width : hint_range(10.0, 200.0) = 80.0;
uniform vec4 pulse_color : source_color = vec4(0.0, 0.85, 0.95, 1.0);
uniform float time_val : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	// Distance from center in world units (sphere mesh scaled to pulse_radius)
	float dist_from_center = length(VERTEX) * pulse_radius;

	// Main ring at the expanding edge
	float ring_dist = abs(dist_from_center - pulse_radius);
	float ring_alpha = smoothstep(ring_width, 0.0, ring_dist);

	// Echo ring (trailing ring at 80% of pulse radius)
	float echo_radius = pulse_radius * 0.8;
	float echo_dist = abs(dist_from_center - echo_radius);
	float echo_alpha = smoothstep(ring_width * 0.5, 0.0, echo_dist) * 0.3;

	// Ripple pattern within the ring
	float ripple = sin(dist_from_center * 0.05 - time_val * 8.0) * 0.5 + 0.5;
	ring_alpha *= 0.7 + ripple * 0.3;

	// Fresnel edge glow
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);

	// Combine
	float total_alpha = (ring_alpha + echo_alpha) * fresnel;

	// Fade as pulse approaches max range
	float range_fade = 1.0 - smoothstep(max_radius * 0.7, max_radius, pulse_radius);
	total_alpha *= range_fade;

	ALBEDO = pulse_color.rgb * (1.0 + ring_alpha * 0.5);
	ALPHA = clamp(total_alpha, 0.0, 1.0);
}
