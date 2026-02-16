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
uniform float rim_power_soft : hint_range(0.5, 4.0) = 1.5;
uniform float rim_intensity_soft : hint_range(0.0, 1.0) = 0.25;
uniform float hemisphere_bias : hint_range(0.0, 0.1) = 0.03;
uniform float ambient_boost : hint_range(0.0, 0.15) = 0.04;

void fragment() {
	float fresnel = 1.0 - abs(dot(NORMAL, VIEW));
	float rim_sharp = pow(fresnel, rim_power) * rim_intensity;
	float rim_soft = pow(fresnel, rim_power_soft) * rim_intensity_soft;

	// Hemisphere bias: top of ship slightly brighter (nebula reflection)
	float hemi = max(NORMAL.y * 0.5 + 0.5, 0.0) * hemisphere_bias;

	// Combine sharp edge rim + soft halo + ambient + hemisphere
	ALBEDO = rim_color.rgb * (rim_sharp + rim_soft) + vec3(ambient_boost + hemi);
	ALPHA = rim_sharp + rim_soft + (ambient_boost + hemi) * 3.0;
}
