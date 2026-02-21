shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4  pulse_color : source_color = vec4(0.2, 0.82, 1.0, 1.0);
uniform float brightness  : hint_range(0.0, 10.0) = 5.0;
uniform float rim_power   : hint_range(1.0, 10.0) = 5.0;
uniform float fade        : hint_range(0.0,  1.0) = 1.0;
uniform float shell_band  : hint_range(0.01, 1.0) = 0.15;

void fragment() {
	float ndv    = abs(dot(NORMAL, VIEW));
	float rim    = pow(1.0 - ndv, rim_power);
	// Shell band: only render a thin ring at the edge of the sphere
	// ndv ~ 0 at the silhouette edge, ~ 1 at center facing camera
	// We want a band where ndv is small (near the edge)
	float band   = smoothstep(shell_band, 0.0, ndv);
	float ripple = 0.88 + sin(TIME * 10.0) * 0.12;
	ALBEDO = pulse_color.rgb * brightness * ripple * fade;
	ALPHA  = clamp(band * rim * fade, 0.0, 1.0);
}
