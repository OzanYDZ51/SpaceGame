shader_type sky;

// =============================================================================
// Space Skybox — Realistic but optimized
// Gradient noise + 2-octave FBM (no domain warping) — ~45% less GPU than v1
// Halos on bright stars, dust lanes, detailed nebulae
// =============================================================================

uniform float star_density : hint_range(0.0, 1.0) = 0.4;
uniform float star_brightness : hint_range(0.0, 6.0) = 3.5;
uniform float twinkle_speed : hint_range(0.0, 5.0) = 0.5;

// Nebula palette
uniform vec3 nebula_warm : source_color = vec3(0.12, 0.03, 0.05);
uniform vec3 nebula_cool : source_color = vec3(0.03, 0.04, 0.10);
uniform vec3 nebula_accent : source_color = vec3(0.06, 0.02, 0.12);
uniform float nebula_intensity : hint_range(0.0, 2.0) = 0.35;

// Milky Way band
uniform float milky_way_intensity : hint_range(0.0, 2.0) = 0.5;
uniform float milky_way_width : hint_range(0.05, 0.5) = 0.16;
uniform vec3 milky_way_color : source_color = vec3(0.08, 0.07, 0.14);

// Dust lanes
uniform float dust_intensity : hint_range(0.0, 1.0) = 0.5;

// ─── Hash functions (no sin, GPU-safe) ──────────────────────────────────────

vec3 _hash33(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return fract(p * fract(p * 0.3183099 + 0.1)) * 2.0 - 1.0;
}

float _hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

// ─── 3D Gradient noise (Perlin-style, realistic detail) ─────────────────────

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

// 2-octave FBM (good detail, way cheaper than 3-4 octaves)
float fbm2(vec3 p) {
	return noise3d(p) * 0.65 + noise3d(p * 2.0) * 0.35;
}

// ─── Star color from temperature ────────────────────────────────────────────

vec3 star_color_temp(float t) {
	vec3 cool_c  = vec3(1.0, 0.5, 0.2);
	vec3 warm_c  = vec3(1.0, 0.8, 0.5);
	vec3 mid_c   = vec3(1.0, 0.97, 0.85);
	vec3 white_c = vec3(0.9, 0.93, 1.0);
	vec3 hot_c   = vec3(0.65, 0.75, 1.0);

	if (t < 0.25) return mix(cool_c, warm_c, t * 4.0);
	if (t < 0.5) return mix(warm_c, mid_c, (t - 0.25) * 4.0);
	if (t < 0.75) return mix(mid_c, white_c, (t - 0.5) * 4.0);
	return mix(white_c, hot_c, (t - 0.75) * 4.0);
}

// ─── Star point with glow halo ──────────────────────────────────────────────

float star_point(vec3 dir, float scale, float threshold, float halo_strength, out float temperature) {
	vec3 cell = floor(dir * scale);
	vec3 local = fract(dir * scale) - 0.5;

	float h = _hash31(cell);
	temperature = _hash31(cell + vec3(42.0, 17.0, 91.0));

	if (h < threshold) return 0.0;

	vec3 star_pos = vec3(
		_hash31(cell + vec3(127.1, 311.7, 74.7)) - 0.5,
		_hash31(cell + vec3(269.5, 183.3, 246.1)) - 0.5,
		_hash31(cell + vec3(113.5, 271.9, 124.6)) - 0.5
	) * 0.55;

	float dist = length(local - star_pos);
	float norm = (h - threshold) / (1.0 - threshold);
	float size = norm * 0.06 + 0.008;

	// Sharp core + soft glow halo
	float core = smoothstep(size, size * 0.05, dist);
	float halo = smoothstep(size * 5.0, size * 0.3, dist) * halo_strength * norm;

	return core + halo;
}

// ─── Main sky function ──────────────────────────────────────────────────────

void sky() {
	vec3 dir = normalize(EYEDIR);

	// === BASE (very faint deep blue, not pure black) ===
	vec3 sky_color = vec3(0.003, 0.003, 0.008);

	// === NEBULA (3x fbm2, no domain warp — realistic detail) ===
	float n1 = fbm2(dir * 4.5 + vec3(0.0, 0.5, 1.0));
	float n2 = fbm2(dir * 6.0 + vec3(4.7, 2.3, 0.0));
	float n3 = fbm2(dir * 3.0 + vec3(1.2, 3.4, 2.1));

	float emission = smoothstep(0.35, 0.70, n1) * smoothstep(0.25, 0.55, n2);
	vec3 emission_col = mix(nebula_warm, nebula_accent, n3) * emission * 1.5;

	float reflection = smoothstep(0.28, 0.60, n2) * (1.0 - emission * 0.5);
	vec3 reflection_col = nebula_cool * reflection;

	float diffuse = smoothstep(0.15, 0.75, n3) * 0.25;
	vec3 diffuse_col = mix(nebula_cool, nebula_accent, n1) * diffuse;

	sky_color += (emission_col + reflection_col + diffuse_col) * nebula_intensity;

	// === MILKY WAY (band + fbm2 structure) ===
	float tilt = 0.3;
	float galactic_y = dir.y * cos(tilt) - dir.z * sin(tilt);
	float band = exp(-galactic_y * galactic_y / (milky_way_width * milky_way_width));
	float mw_structure = fbm2(dir * 6.0 + vec3(3.7, 0.0, 1.2));
	float mw = band * smoothstep(0.3, 0.7, mw_structure) * milky_way_intensity;
	sky_color += milky_way_color * mw;

	// === DUST LANES (fbm2, lighter absorption than before) ===
	float d1 = fbm2(dir * 5.0 + vec3(2.0, 1.0, 3.0));
	float d2 = fbm2(dir * 9.0 + vec3(5.0, 3.0, 1.0));
	float dust = smoothstep(0.52, 0.72, d1) * smoothstep(0.38, 0.62, d2);
	float plane_boost = exp(-galactic_y * galactic_y / 0.15);
	dust *= (0.3 + plane_boost * 0.7) * dust_intensity;

	// Apply dust (60% absorption — less harsh than before)
	sky_color *= (1.0 - dust * 0.6);

	// === STARS (3 layers with halos on bright ones) ===
	float temp1, temp2, temp3;

	// Layer 1: Dim background stars (no halo)
	float dim_thresh = 1.0 - star_density * 0.85;
	float stars_dim = star_point(dir, 250.0, dim_thresh, 0.0, temp1) * 0.3;

	// Layer 2: Medium stars (subtle halo)
	float med_thresh = 1.0 - star_density * 0.35;
	float stars_med = star_point(dir, 100.0, med_thresh, 0.1, temp2) * 0.7;

	// Layer 3: Bright stars (visible halo)
	float bright_thresh = 1.0 - star_density * 0.1;
	float stars_bright = star_point(dir, 35.0, bright_thresh, 0.15, temp3) * 1.8;

	// Twinkle
	float twinkle_seed = _hash31(floor(dir * 100.0));
	float twinkle = sin(TIME * twinkle_speed + twinkle_seed * TAU) * 0.25 + 0.75;
	float twinkle2 = sin(TIME * twinkle_speed * 0.7 + twinkle_seed * 3.14) * 0.15 + 0.85;

	vec3 total_stars = star_color_temp(temp1) * stars_dim
	                 + star_color_temp(temp2) * stars_med * twinkle2
	                 + star_color_temp(temp3) * stars_bright * twinkle;

	// Dust dims stars too
	total_stars *= (1.0 - dust * 0.4);
	sky_color += total_stars * star_brightness;

	COLOR = sky_color;
}
