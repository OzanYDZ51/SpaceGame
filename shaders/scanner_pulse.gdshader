shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4  pulse_color : source_color = vec4(0.2, 0.82, 1.0, 1.0);
uniform float brightness  : hint_range(0.0, 10.0) = 1.2;
uniform float rim_power   : hint_range(1.0, 10.0) = 4.0;
uniform float fade        : hint_range(0.0,  1.0) = 1.0;
uniform float shell_band  : hint_range(0.01, 1.0) = 0.08;
uniform float scan_progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float ndv = abs(dot(NORMAL, VIEW));

	// Wide shell band — gradient from edge inward
	float band_edge = smoothstep(shell_band, 0.0, ndv);
	float band_inner = smoothstep(0.0, shell_band * 0.6, ndv);
	float band = band_edge * (0.3 + 0.7 * band_inner);

	// Rim glow — wider than before
	float rim = pow(1.0 - ndv, rim_power);

	// Concentric ring pattern — moves outward through the band
	float ring_freq = 12.0;
	float ring_speed = 3.0;
	float rings = 0.5 + 0.5 * sin(ndv * ring_freq - TIME * ring_speed);
	rings = rings * rings; // sharpen

	// Scanline grid — world-space horizontal + vertical lines
	vec3 wp = VERTEX;
	float grid_scale = 0.08;
	float line_x = abs(sin(wp.x * grid_scale));
	float line_y = abs(sin(wp.y * grid_scale));
	float line_z = abs(sin(wp.z * grid_scale));
	float grid = max(max(
		smoothstep(0.92, 1.0, line_x),
		smoothstep(0.92, 1.0, line_y)),
		smoothstep(0.92, 1.0, line_z));
	grid *= 0.15; // barely visible scanline texture

	// Combine: band + rings + grid
	float pattern = band * (0.85 + 0.15 * rings) + grid * band_edge;

	ALBEDO = pulse_color.rgb * brightness * fade;
	ALPHA = clamp((pattern * rim + grid * 0.1) * fade, 0.0, 1.0);
}
