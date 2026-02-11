shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// =============================================================================
// Planet Terrain — Basic height-colored terrain
// Phase B: Simple altitude + slope coloring. Phase E upgrades to splatmap.
// =============================================================================

uniform vec4 color_low : source_color = vec4(0.15, 0.12, 0.08, 1.0);    // Valley/lowlands
uniform vec4 color_mid : source_color = vec4(0.35, 0.30, 0.22, 1.0);    // Mid-altitude
uniform vec4 color_high : source_color = vec4(0.55, 0.50, 0.45, 1.0);   // Mountains
uniform vec4 color_peak : source_color = vec4(0.85, 0.82, 0.78, 1.0);   // Snow/peak
uniform vec4 color_cliff : source_color = vec4(0.25, 0.22, 0.18, 1.0);  // Steep slopes

uniform float height_mid : hint_range(0.0, 1.0) = 0.3;
uniform float height_high : hint_range(0.0, 1.0) = 0.6;
uniform float height_peak : hint_range(0.0, 1.0) = 0.85;
uniform float cliff_threshold : hint_range(0.0, 1.0) = 0.5; // Normal.y below this = cliff
uniform float roughness_val : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;
uniform float planet_radius = 50000.0;

varying float v_height;
varying float v_slope;

void vertex() {
	// Height = distance from origin / planet_radius - 1.0
	float dist = length(VERTEX);
	v_height = clamp((dist / planet_radius - 1.0) * 50.0, 0.0, 1.0); // Amplify for visibility

	// Slope from normal vs radial direction
	vec3 radial = normalize(VERTEX);
	v_slope = 1.0 - abs(dot(NORMAL, radial));
}

void fragment() {
	// Altitude-based color
	vec3 col;
	if (v_height < height_mid) {
		float t = v_height / height_mid;
		col = mix(color_low.rgb, color_mid.rgb, t);
	} else if (v_height < height_high) {
		float t = (v_height - height_mid) / (height_high - height_mid);
		col = mix(color_mid.rgb, color_high.rgb, t);
	} else if (v_height < height_peak) {
		float t = (v_height - height_high) / (height_peak - height_high);
		col = mix(color_high.rgb, color_peak.rgb, t);
	} else {
		col = color_peak.rgb;
	}

	// Cliff blending (steep slopes get cliff color)
	if (v_slope > cliff_threshold) {
		float cliff_blend = clamp((v_slope - cliff_threshold) / (1.0 - cliff_threshold), 0.0, 1.0);
		col = mix(col, color_cliff.rgb, cliff_blend * 0.7);
	}

	ALBEDO = col;
	ROUGHNESS = roughness_val;
	METALLIC = metallic_val;
}
