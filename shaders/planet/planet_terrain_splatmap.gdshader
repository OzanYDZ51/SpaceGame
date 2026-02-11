shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// =============================================================================
// Planet Terrain Splatmap — Tri-planar textured terrain
// Blends textures by altitude + slope. Supports 4 layers.
// =============================================================================

group_uniforms colors;
uniform vec4 color_low : source_color = vec4(0.15, 0.12, 0.08, 1.0);
uniform vec4 color_mid : source_color = vec4(0.35, 0.30, 0.22, 1.0);
uniform vec4 color_high : source_color = vec4(0.55, 0.50, 0.45, 1.0);
uniform vec4 color_peak : source_color = vec4(0.85, 0.82, 0.78, 1.0);
uniform vec4 color_cliff : source_color = vec4(0.25, 0.22, 0.18, 1.0);
uniform vec4 color_ocean : source_color = vec4(0.08, 0.20, 0.45, 1.0);

group_uniforms thresholds;
uniform float height_mid : hint_range(0.0, 1.0) = 0.3;
uniform float height_high : hint_range(0.0, 1.0) = 0.6;
uniform float height_peak : hint_range(0.0, 1.0) = 0.85;
uniform float ocean_level : hint_range(0.0, 0.5) = 0.0;
uniform float cliff_threshold : hint_range(0.0, 1.0) = 0.5;

group_uniforms material;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;
uniform float planet_radius = 50000.0;
uniform float triplanar_scale : hint_range(0.00001, 0.01) = 0.001;

group_uniforms detail;
uniform sampler2D detail_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_strength : hint_range(0.0, 0.5) = 0.15;

varying float v_height;
varying float v_slope;
varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	float dist = length(VERTEX);
	v_height = clamp((dist / planet_radius - 1.0) * 50.0, 0.0, 1.0);

	vec3 radial = normalize(VERTEX);
	v_slope = 1.0 - abs(dot(NORMAL, radial));

	v_world_pos = VERTEX;
	v_world_normal = abs(normalize(NORMAL));
}

// Tri-planar sampling
vec3 triplanar_sample(sampler2D tex, vec3 pos, vec3 normal) {
	vec3 blend = normal;
	blend = blend * blend * blend; // Sharpen blend
	blend /= (blend.x + blend.y + blend.z);

	vec3 x_proj = texture(tex, pos.yz * triplanar_scale).rgb;
	vec3 y_proj = texture(tex, pos.xz * triplanar_scale).rgb;
	vec3 z_proj = texture(tex, pos.xy * triplanar_scale).rgb;

	return x_proj * blend.x + y_proj * blend.y + z_proj * blend.z;
}

void fragment() {
	// Base altitude color
	vec3 col;
	if (v_height < ocean_level && ocean_level > 0.001) {
		col = color_ocean.rgb;
	} else if (v_height < height_mid) {
		float t = v_height / max(height_mid, 0.001);
		col = mix(color_low.rgb, color_mid.rgb, t);
	} else if (v_height < height_high) {
		float t = (v_height - height_mid) / max(height_high - height_mid, 0.001);
		col = mix(color_mid.rgb, color_high.rgb, t);
	} else if (v_height < height_peak) {
		float t = (v_height - height_high) / max(height_peak - height_high, 0.001);
		col = mix(color_high.rgb, color_peak.rgb, t);
	} else {
		col = color_peak.rgb;
	}

	// Cliff blending
	if (v_slope > cliff_threshold) {
		float cliff_blend = clamp((v_slope - cliff_threshold) / (1.0 - cliff_threshold), 0.0, 1.0);
		col = mix(col, color_cliff.rgb, cliff_blend * 0.7);
	}

	// Detail noise (tri-planar) for surface texture variation
	vec3 detail = triplanar_sample(detail_noise, v_world_pos, v_world_normal);
	col = mix(col, col * detail * 2.0, detail_strength);

	ALBEDO = col;
	ROUGHNESS = roughness_val;
	METALLIC = metallic_val;

	// Ocean: smooth and slightly reflective
	if (v_height < ocean_level && ocean_level > 0.001) {
		ROUGHNESS = 0.15;
		METALLIC = 0.05;
	}
}
