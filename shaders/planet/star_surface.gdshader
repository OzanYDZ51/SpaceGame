shader_type spatial;
render_mode unshaded, shadows_disabled;

// =============================================================================
// Star Surface — Animated procedural sun with granulation, sunspots, limb darkening
// HDR emission triggers existing bloom/glow pipeline.
// =============================================================================

uniform vec4 star_color : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float emission_energy : hint_range(1.0, 10.0) = 3.5;
uniform float granulation_scale : hint_range(1.0, 20.0) = 8.0;
uniform float granulation_speed : hint_range(0.0, 2.0) = 0.3;
uniform float sunspot_scale : hint_range(0.5, 5.0) = 2.0;
uniform float sunspot_strength : hint_range(0.0, 1.0) = 0.4;

varying vec3 local_normal;
varying vec3 local_pos;

// =============================================================================
// Noise (copied from skybox — Godot has no #include for spatial shaders)
// =============================================================================

vec3 _hash33(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return fract(p * fract(p * 0.3183099 + 0.1)) * 2.0 - 1.0;
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

	float n000 = dot(_hash33(i + vec3(0, 0, 0)), f - vec3(0, 0, 0));
	float n100 = dot(_hash33(i + vec3(1, 0, 0)), f - vec3(1, 0, 0));
	float n010 = dot(_hash33(i + vec3(0, 1, 0)), f - vec3(0, 1, 0));
	float n110 = dot(_hash33(i + vec3(1, 1, 0)), f - vec3(1, 1, 0));
	float n001 = dot(_hash33(i + vec3(0, 0, 1)), f - vec3(0, 0, 1));
	float n101 = dot(_hash33(i + vec3(1, 0, 1)), f - vec3(1, 0, 1));
	float n011 = dot(_hash33(i + vec3(0, 1, 1)), f - vec3(0, 1, 1));
	float n111 = dot(_hash33(i + vec3(1, 1, 1)), f - vec3(1, 1, 1));

	return mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z
	) * 0.5 + 0.5;
}

float fbm3(vec3 p) {
	return noise3d(p) * 0.5 + noise3d(p * 2.0) * 0.33 + noise3d(p * 4.0) * 0.17;
}

// Voronoi-like cellular noise for granulation (convection cells)
float cellular(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float min_dist = 1.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 neighbor = vec3(float(x), float(y), float(z));
				vec3 cell_pos = _hash33(i + neighbor) * 0.5 + 0.5;
				float d = length(neighbor + cell_pos - f);
				min_dist = min(min_dist, d);
			}
		}
	}
	return min_dist;
}

// =============================================================================

void vertex() {
	local_normal = NORMAL;
	local_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(local_normal);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(local_pos, 1.0)).xyz);
	vec3 world_n = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);

	// --- Limb darkening ---
	float ndotv = max(dot(world_n, view_dir), 0.0);
	float limb = pow(ndotv, 0.4);

	// --- Color gradient: white-hot center, star_color at edges ---
	vec3 hot_center = vec3(1.0, 0.98, 0.9);
	vec3 base_color = mix(star_color.rgb, hot_center, pow(ndotv, 1.5));

	// --- Animated granulation (convection cells) ---
	float t = TIME * granulation_speed;
	vec3 sample_pos = n * granulation_scale + vec3(t * 0.1, t * 0.07, t * -0.05);
	float cells = cellular(sample_pos);
	// Bright cell centers, darker edges
	float granulation = smoothstep(0.0, 0.5, cells) * 0.3 + 0.7;

	// --- Sunspots (low frequency dark patches) ---
	vec3 spot_pos = n * sunspot_scale + vec3(t * 0.02, t * -0.01, t * 0.015);
	float spots = fbm3(spot_pos);
	// Only make dark spots where noise is very high
	float spot_mask = smoothstep(0.65, 0.8, spots) * sunspot_strength;

	// --- Combine ---
	vec3 final_color = base_color * granulation * limb;
	// Darken for sunspots
	final_color *= 1.0 - spot_mask * 0.7;

	// --- Small-scale surface turbulence ---
	float turb = noise3d(n * granulation_scale * 3.0 + vec3(t * 0.15, t * 0.1, t * -0.12));
	final_color += (turb - 0.5) * 0.08 * star_color.rgb;

	ALBEDO = final_color * emission_energy;
	EMISSION = final_color * emission_energy;
}
