shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Scanner pulse — expanding sphere shell.
// The mesh is dynamically scaled to pulse_radius each frame.
// This shader renders the sphere surface with simple alpha + ripple animation.

uniform float pulse_radius : hint_range(0.0, 6000.0) = 0.0;
uniform float max_radius : hint_range(100.0, 10000.0) = 5000.0;
uniform vec4 pulse_color : source_color = vec4(0.0, 0.85, 0.95, 1.0);
uniform float time_val : hint_range(0.0, 100.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Range fade — fade out as the pulse approaches max range
	float range_fade = 1.0 - smoothstep(max_radius * 0.65, max_radius * 0.95, pulse_radius);

	// Animated ripple
	float ripple = sin(pulse_radius * 0.05 - time_val * 10.0) * 0.5 + 0.5;

	// Bright HDR color for bloom
	ALBEDO = pulse_color.rgb * (2.0 + ripple * 1.5);
	ALPHA = clamp(opacity * range_fade * (0.5 + ripple * 0.3), 0.0, 1.0);
}
