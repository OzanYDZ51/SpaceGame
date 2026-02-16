shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

// =============================================================================
// Ship Hull Rim Light Shader
// Adds a fresnel-based edge glow + subtle ambient boost to all ship meshes.
// Applied as material_overlay (additive) on top of the base PBR material.
// This simulates the ambient/reflected light catching ship edges that real-time
// PBR misses in dark space environments.
// =============================================================================

uniform vec4 rim_color : source_color = vec4(0.35, 0.5, 0.7, 1.0);
uniform float rim_power : hint_range(1.0, 8.0) = 3.0;
uniform float rim_intensity : hint_range(0.0, 3.0) = 0.8;
uniform float ambient_boost : hint_range(0.0, 0.1) = 0.025;

void fragment() {
	float fresnel = 1.0 - abs(dot(NORMAL, VIEW));
	float rim = pow(fresnel, rim_power) * rim_intensity;

	// Combine rim glow + tiny flat ambient lift
	ALBEDO = rim_color.rgb * rim + vec3(ambient_boost);
	ALPHA = rim + ambient_boost * 3.0;
}
