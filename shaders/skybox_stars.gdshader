shader_type sky;

// =============================================================================
// Space Skybox — Star Citizen-quality visuals
// Domain-warped FBM nebulae (3 depth layers), HDR emission cores,
// god rays / solar scattering, 4 star layers with galactic concentration,
// star clusters, nebula edge glow, milky way band, dust lanes
// =============================================================================

// --- Stars ---
uniform float star_density : hint_range(0.0, 1.0) = 0.4;
uniform float star_brightness : hint_range(0.0, 6.0) = 3.5;
uniform float twinkle_speed : hint_range(0.0, 5.0) = 0.5;

// --- Nebula palette ---
uniform vec3 nebula_warm : source_color = vec3(0.25, 0.06, 0.10);
uniform vec3 nebula_cool : source_color = vec3(0.06, 0.10, 0.30);
uniform vec3 nebula_accent : source_color = vec3(0.15, 0.05, 0.35);
uniform float nebula_intensity : hint_range(0.0, 2.0) = 0.5;

// --- Milky Way ---
uniform float milky_way_intensity : hint_range(0.0, 2.0) = 0.5;
uniform float milky_way_width : hint_range(0.05, 0.5) = 0.16;
uniform vec3 milky_way_color : source_color = vec3(0.08, 0.07, 0.14);

// --- Dust lanes ---
uniform float dust_intensity : hint_range(0.0, 1.0) = 0.5;

// --- NEW uniforms ---
uniform vec3 sun_direction = vec3(0.0, 0.0, -1.0);
uniform float god_ray_intensity : hint_range(0.0, 2.0) = 0.5;
uniform float nebula_warp_strength : hint_range(0.0, 2.0) = 0.6;
uniform float nebula_emission_strength : hint_range(0.0, 5.0) = 0.4;
uniform float star_cluster_density : hint_range(0.0, 1.0) = 0.3;

// =============================================================================
// Hash functions (no sin, GPU-safe)
// =============================================================================

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

// =============================================================================
// 3D Gradient noise (Perlin-style)
// =============================================================================

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

// =============================================================================
// FBM (2 and 3 octave variants)
// =============================================================================

float fbm2(vec3 p) {
	return noise3d(p) * 0.65 + noise3d(p * 2.0) * 0.35;
}

float fbm3(vec3 p) {
	return noise3d(p) * 0.5 + noise3d(p * 2.0) * 0.33 + noise3d(p * 4.0) * 0.17;
}

// =============================================================================
// Domain-warped FBM — creates wispy, filamentary nebula structures
// warp_str controls how much the domain is displaced before final FBM
// =============================================================================

float warped_fbm(vec3 p, float warp_str, vec3 offset_a, vec3 offset_b, vec3 offset_c) {
	// First pass: compute warp displacement field
	float wx = fbm2(p + offset_a);
	float wy = fbm2(p + offset_b);
	float wz = fbm2(p + offset_c);
	vec3 warp_offset = vec3(wx, wy, wz);

	// Second pass: evaluate FBM at warped position (3-octave for detail)
	return fbm3(p + warp_offset * warp_str);
}

// =============================================================================
// Star color from temperature
// =============================================================================

vec3 star_color_temp(float t) {
	vec3 cool_c  = vec3(1.0, 0.5, 0.2);
	vec3 warm_c  = vec3(1.0, 0.8, 0.5);
	vec3 mid_c   = vec3(1.0, 0.97, 0.85);
	vec3 white_c = vec3(0.9, 0.93, 1.0);
	vec3 hot_c   = vec3(0.65, 0.75, 1.0);

	if (t < 0.25) {
		return mix(cool_c, warm_c, t * 4.0);
	} else if (t < 0.5) {
		return mix(warm_c, mid_c, (t - 0.25) * 4.0);
	} else if (t < 0.75) {
		return mix(mid_c, white_c, (t - 0.5) * 4.0);
	} else {
		return mix(white_c, hot_c, (t - 0.75) * 4.0);
	}
}

// =============================================================================
// Star point with glow halo
// =============================================================================

float star_point(vec3 dir, float scale, float threshold, float halo_strength, out float temperature) {
	vec3 cell = floor(dir * scale);
	vec3 local = fract(dir * scale) - 0.5;

	float h = _hash31(cell);
	temperature = _hash31(cell + vec3(42.0, 17.0, 91.0));

	if (h < threshold) {
		return 0.0;
	}

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

// =============================================================================
// Main sky function
// =============================================================================

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sun_dir = normalize(sun_direction);

	// === BASE (faint deep blue) ===
	vec3 sky_color = vec3(0.003, 0.003, 0.008);

	// === GALACTIC PLANE coordinate ===
	float tilt = 0.3;
	float galactic_y = dir.y * cos(tilt) - dir.z * sin(tilt);

	// =========================================================================
	// NEBULA — 3 depth layers with domain-warped FBM
	// =========================================================================

	// --- Background layer (scale ~2.5): large, soft, diffuse glow ---
	float bg_warp = warped_fbm(
		dir * 2.5,
		nebula_warp_strength * 0.8,
		vec3(0.0, 0.0, 0.0),
		vec3(5.2, 1.3, 2.8),
		vec3(1.7, 9.2, 4.1)
	);
	float bg_mask = pow(max(smoothstep(0.52, 0.78, bg_warp), 0.0), 2.0);
	// Mix cool and warm for color variation within the layer
	vec3 bg_color = mix(nebula_cool * 1.0, nebula_warm * 0.6, smoothstep(0.4, 0.7, bg_warp));
	vec3 nebula_bg = bg_color * bg_mask * 0.15;

	// --- Midground layer (scale ~5.0): main structural detail, filaments ---
	float mid_warp = warped_fbm(
		dir * 5.0,
		nebula_warp_strength,
		vec3(3.1, 7.4, 1.5),
		vec3(8.3, 2.9, 6.1),
		vec3(4.6, 0.8, 3.7)
	);
	float mid_mask = pow(max(smoothstep(0.55, 0.82, mid_warp), 0.0), 2.2);
	// Rich color from accent and warm, with cool accents blended in
	float mid_color_blend = smoothstep(0.35, 0.65, warped_fbm(dir * 4.0, nebula_warp_strength * 0.5, vec3(11.0, 2.0, 7.0), vec3(3.0, 8.0, 1.0), vec3(6.0, 4.0, 9.0)));
	vec3 mid_color = mix(nebula_warm, nebula_accent, smoothstep(0.35, 0.65, mid_warp));
	mid_color = mix(mid_color, nebula_cool * 0.7, mid_color_blend * 0.35);
	vec3 nebula_mid = mid_color * mid_mask * 0.25;

	// --- Foreground layer (scale ~8.0): fine wisps and tendrils ---
	float fg_warp = warped_fbm(
		dir * 8.0,
		nebula_warp_strength * 1.2,
		vec3(6.7, 3.2, 9.0),
		vec3(2.1, 8.5, 0.4),
		vec3(9.3, 1.1, 5.6)
	);
	float fg_mask = pow(max(smoothstep(0.58, 0.87, fg_warp), 0.0), 2.5);
	// Different mix: accent into cool for wispy foreground
	vec3 fg_color = mix(nebula_accent * 0.7, nebula_cool * 1.0, smoothstep(0.4, 0.7, fg_warp));
	vec3 nebula_fg = fg_color * fg_mask * 0.12;

	// Composite nebula layers (additive)
	vec3 nebula_total = (nebula_bg + nebula_mid + nebula_fg) * nebula_intensity;

	// Combined nebula density for downstream effects (edge glow, dust interaction)
	float nebula_density = max(max(bg_mask, mid_mask), fg_mask);

	// =========================================================================
	// HDR EMISSION CORES — trigger Godot bloom/glow naturally
	// =========================================================================

	// Emission from midground (strongest structural features) — very tight, rare highlights
	float emission_mid = pow(max(smoothstep(0.80, 0.97, mid_warp), 0.0), 3.5);
	// Emission from background (broader, softer glow) — very subtle
	float emission_bg = pow(max(smoothstep(0.85, 0.97, bg_warp), 0.0), 4.0) * 0.2;

	vec3 emission_color_mid = mix(nebula_warm * 1.2, nebula_accent * 1.0, smoothstep(0.5, 0.8, mid_warp));
	vec3 emission_color_bg = nebula_cool * 0.8 + nebula_warm * 0.3;

	vec3 emission_cores = (emission_color_mid * emission_mid + emission_color_bg * emission_bg) * nebula_emission_strength;

	// =========================================================================
	// GOD RAYS / SOLAR SCATTERING
	// =========================================================================

	float sun_scatter = max(dot(dir, sun_dir), 0.0);
	float god_ray = pow(max(sun_scatter, 0.0), 4.0) * god_ray_intensity;
	// Warm tinted scattering through nebula gas
	vec3 god_ray_color = nebula_total * god_ray * vec3(1.2, 1.0, 0.8);
	// Ambient forward-scatter even without nebula (faint haze near sun)
	vec3 sun_haze = vec3(0.04, 0.03, 0.02) * pow(max(sun_scatter, 0.0), 8.0) * god_ray_intensity;

	// =========================================================================
	// NEBULA EDGE GLOW (backlit gas rim lighting)
	// =========================================================================

	float edge_bg = smoothstep(0.25, 0.45, bg_mask) - smoothstep(0.45, 0.70, bg_mask);
	float edge_mid = smoothstep(0.30, 0.50, mid_mask) - smoothstep(0.50, 0.72, mid_mask);
	float edge = max(edge_bg, edge_mid);
	vec3 edge_glow = edge * sun_scatter * mix(nebula_warm, vec3(1.0, 0.8, 0.5), 0.4) * 0.6;

	// =========================================================================
	// Apply all nebula contributions
	// =========================================================================

	sky_color += nebula_total + emission_cores + god_ray_color + edge_glow + sun_haze;

	// =========================================================================
	// MILKY WAY (band + FBM structure)
	// =========================================================================

	float band = exp(-galactic_y * galactic_y / (milky_way_width * milky_way_width));
	float mw_structure = fbm2(dir * 6.0 + vec3(3.7, 0.0, 1.2));
	float mw = band * smoothstep(0.3, 0.7, mw_structure) * milky_way_intensity;
	sky_color += milky_way_color * mw;

	// =========================================================================
	// DUST LANES (absorption in galactic plane)
	// =========================================================================

	float d1 = fbm2(dir * 5.0 + vec3(2.0, 1.0, 3.0));
	float d2 = fbm2(dir * 9.0 + vec3(5.0, 3.0, 1.0));
	float dust = smoothstep(0.52, 0.72, d1) * smoothstep(0.38, 0.62, d2);
	float plane_boost = exp(-galactic_y * galactic_y / 0.15);
	dust *= (0.3 + plane_boost * 0.7) * dust_intensity;

	// Apply dust absorption (75% — stronger dark voids for contrast)
	sky_color *= (1.0 - dust * 0.75);

	// =========================================================================
	// STAR CLUSTERS — regions of increased star density
	// =========================================================================

	float cluster = smoothstep(0.6, 0.9, fbm2(dir * 2.0 + vec3(7.0, 3.0, 1.0))) * star_cluster_density;

	// =========================================================================
	// GALACTIC CONCENTRATION — more stars near galactic equator
	// =========================================================================

	float galactic_boost = exp(-galactic_y * galactic_y / 0.08) * 0.5 + 1.0;

	// =========================================================================
	// STARS — 4 layers with halos, clusters, and galactic concentration
	// =========================================================================

	float temp1, temp2, temp3, temp4;

	// Layer 1: Ultra-fine background dust of tiny stars (new)
	float ultra_thresh = 1.0 - star_density * 0.92 * galactic_boost + cluster * (-0.08);
	ultra_thresh = clamp(ultra_thresh, 0.0, 1.0);
	float stars_ultra = star_point(dir, 600.0, ultra_thresh, 0.0, temp4) * 0.15;

	// Layer 2: Dim background stars
	float dim_thresh = 1.0 - star_density * 0.85 * galactic_boost + cluster * (-0.10);
	dim_thresh = clamp(dim_thresh, 0.0, 1.0);
	float stars_dim = star_point(dir, 250.0, dim_thresh, 0.0, temp1) * 0.3;

	// Layer 3: Medium stars (subtle halo)
	float med_thresh = 1.0 - star_density * 0.35 * galactic_boost + cluster * (-0.06);
	med_thresh = clamp(med_thresh, 0.0, 1.0);
	float stars_med = star_point(dir, 100.0, med_thresh, 0.1, temp2) * 0.7;

	// Layer 4: Bright stars (visible halo)
	float bright_thresh = 1.0 - star_density * 0.1;
	float stars_bright = star_point(dir, 35.0, bright_thresh, 0.15, temp3) * 1.8;

	// Twinkle
	float twinkle_seed = _hash31(floor(dir * 100.0));
	float twinkle = sin(TIME * twinkle_speed + twinkle_seed * TAU) * 0.25 + 0.75;
	float twinkle2 = sin(TIME * twinkle_speed * 0.7 + twinkle_seed * 3.14) * 0.15 + 0.85;

	// Cluster brightness boost for visible stars
	float cluster_bright = 1.0 + cluster * 1.5;

	vec3 total_stars = star_color_temp(temp4) * stars_ultra * galactic_boost
	                 + star_color_temp(temp1) * stars_dim * galactic_boost * cluster_bright
	                 + star_color_temp(temp2) * stars_med * twinkle2 * cluster_bright
	                 + star_color_temp(temp3) * stars_bright * twinkle;

	// Dust dims stars
	total_stars *= (1.0 - dust * 0.4);

	// Nebula slightly occludes background stars (reduced — stars more visible through gas)
	total_stars *= (1.0 - nebula_density * 0.15);

	sky_color += total_stars * star_brightness;

	COLOR = sky_color;
}
