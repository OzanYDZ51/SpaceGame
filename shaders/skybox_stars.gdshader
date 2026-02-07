shader_type sky;

// =============================================================================
// Deep Space Skybox - Cinematic procedural starfield
// Milky Way band, multi-layer nebulae, dust lanes, star halos, color temperature
// =============================================================================

uniform float star_density : hint_range(0.0, 1.0) = 0.6;
uniform float star_brightness : hint_range(0.0, 5.0) = 2.2;
uniform float twinkle_speed : hint_range(0.0, 5.0) = 0.7;

// Nebula palette
uniform vec3 nebula_warm : source_color = vec3(0.12, 0.02, 0.04);   // deep crimson
uniform vec3 nebula_cool : source_color = vec3(0.02, 0.03, 0.10);   // dark blue
uniform vec3 nebula_accent : source_color = vec3(0.06, 0.01, 0.12); // purple
uniform float nebula_intensity : hint_range(0.0, 1.5) = 0.45;

// Milky Way
uniform float milky_way_intensity : hint_range(0.0, 2.0) = 0.7;
uniform float milky_way_width : hint_range(0.05, 0.5) = 0.18;
uniform vec3 milky_way_color : source_color = vec3(0.12, 0.10, 0.16);

// Dust lanes
uniform float dust_intensity : hint_range(0.0, 1.0) = 0.5;

// ─── Noise utilities (gradient noise, no sin()) ─────────────────────────────

// Polynomial hash — no sin(), works reliably on all GPUs
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

// 3D Gradient noise (Perlin-style) — inherently grid-artifact-free
// Uses random gradients at cell corners + dot product with offset vectors
float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);

	// Quintic Hermite interpolation (C2 continuous)
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

	// Gradient dot products at 8 corners
	float n000 = dot(_hash33(i + vec3(0, 0, 0)), f - vec3(0, 0, 0));
	float n100 = dot(_hash33(i + vec3(1, 0, 0)), f - vec3(1, 0, 0));
	float n010 = dot(_hash33(i + vec3(0, 1, 0)), f - vec3(0, 1, 0));
	float n110 = dot(_hash33(i + vec3(1, 1, 0)), f - vec3(1, 1, 0));
	float n001 = dot(_hash33(i + vec3(0, 0, 1)), f - vec3(0, 0, 1));
	float n101 = dot(_hash33(i + vec3(1, 0, 1)), f - vec3(1, 0, 1));
	float n011 = dot(_hash33(i + vec3(0, 1, 1)), f - vec3(0, 1, 1));
	float n111 = dot(_hash33(i + vec3(1, 1, 1)), f - vec3(1, 1, 1));

	// Trilinear interpolation
	float val = mix(
		mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
		u.z
	);

	return val * 0.5 + 0.5; // remap [-~0.7, ~0.7] to [0, 1]
}

// Fractal Brownian Motion
float fbm(vec3 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise3d(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.0;
	}
	return value;
}

// ─── Star color from temperature ────────────────────────────────────────────

vec3 star_color_temp(float t) {
	// t: 0=cool red/orange, 0.5=white/yellow, 1.0=hot blue
	vec3 cool  = vec3(1.0, 0.5, 0.2);   // M-class red-orange
	vec3 warm  = vec3(1.0, 0.8, 0.5);   // K-class orange
	vec3 mid   = vec3(1.0, 0.97, 0.85); // G-class yellow-white
	vec3 white = vec3(0.9, 0.93, 1.0);  // F-class white
	vec3 hot   = vec3(0.65, 0.75, 1.0); // B/O-class blue

	if (t < 0.25) return mix(cool, warm, t * 4.0);
	if (t < 0.5) return mix(warm, mid, (t - 0.25) * 4.0);
	if (t < 0.75) return mix(mid, white, (t - 0.5) * 4.0);
	return mix(white, hot, (t - 0.75) * 4.0);
}

// ─── Star layer with glow halos ─────────────────────────────────────────────

float star_point(vec3 dir, float scale, float threshold, out float temperature) {
	vec3 cell = floor(dir * scale);
	vec3 local = fract(dir * scale) - 0.5;

	float h = _hash31(cell);
	temperature = _hash31(cell + vec3(42.0, 17.0, 91.0));

	if (h < threshold) return 0.0;

	// Random star position within cell
	vec3 star_pos = vec3(
		_hash31(cell + vec3(127.1, 311.7, 74.7)) - 0.5,
		_hash31(cell + vec3(269.5, 183.3, 246.1)) - 0.5,
		_hash31(cell + vec3(113.5, 271.9, 124.6)) - 0.5
	) * 0.55;

	float dist = length(local - star_pos);
	float norm_brightness = (h - threshold) / (1.0 - threshold);
	float size = norm_brightness * 0.06 + 0.008;

	// Sharp core + soft glow halo
	float core = smoothstep(size, size * 0.05, dist);
	float halo = smoothstep(size * 5.0, size * 0.3, dist) * 0.15 * norm_brightness;

	return core + halo;
}

// ─── Milky Way galactic band ────────────────────────────────────────────────

float milky_way_band(vec3 dir) {
	float tilt = 0.3;
	float galactic_y = dir.y * cos(tilt) - dir.z * sin(tilt);

	// Band falloff from galactic plane
	float band = exp(-galactic_y * galactic_y / (milky_way_width * milky_way_width));

	// Domain-warped structure within the band
	float warp = noise3d(dir * 4.0 + vec3(9.1, 3.7, 6.4)) * 0.2;
	vec3 warped_dir = dir + vec3(warp, 0.0, warp * 0.7);

	float structure = fbm(warped_dir * 6.0 + vec3(3.7, 0.0, 1.2), 3);
	float detail = fbm(warped_dir * 15.0 + vec3(7.1, 2.3, 5.4), 2);

	float clouds = smoothstep(0.3, 0.7, structure) * 0.8 + detail * 0.2;

	return band * clouds;
}

// ─── Nebula system (domain-warped for organic shapes) ───────────────────────

vec3 nebula_field(vec3 dir) {
	// Cheap hash-based domain warp (no noise3d calls)
	vec3 warp = _hash33(floor(dir * 3.5 + 0.5)) * 0.35;
	vec3 warped = dir + warp;

	// Sample nebula layers on warped coordinates (reduced octaves)
	float n1 = fbm(warped * 4.5 + vec3(0.0, 0.5, 1.0), 3);
	float n2 = fbm(warped * 6.0 + vec3(4.7, 2.3, 0.0), 3);
	float n3 = fbm(warped * 3.0 + vec3(1.2, 3.4, 2.1), 3);

	// Emission nebula (warm, localized bright regions)
	float emission = smoothstep(0.35, 0.70, n1) * smoothstep(0.25, 0.55, n2);
	vec3 emission_col = mix(nebula_warm, nebula_accent, n3) * emission * 1.5;

	// Reflection nebula (cool, broader, dimmer)
	float reflection = smoothstep(0.28, 0.60, n2) * (1.0 - emission * 0.5);
	vec3 reflection_col = nebula_cool * reflection;

	// Background diffuse nebulosity
	float diffuse = smoothstep(0.15, 0.75, n3) * 0.2;
	vec3 diffuse_col = mix(nebula_cool, nebula_accent, n1) * diffuse;

	return (emission_col + reflection_col + diffuse_col) * nebula_intensity;
}

// ─── Dark dust lanes (domain-warped) ────────────────────────────────────────

float dust_field(vec3 dir) {
	// Light domain warp for dust
	float dw = noise3d(dir * 3.0 + vec3(5.5, 2.2, 7.7)) * 0.15;
	vec3 warped = dir + vec3(dw, dw * 0.5, -dw * 0.8);

	float d1 = fbm(warped * 5.0 + vec3(2.0, 1.0, 3.0), 5);
	float d2 = fbm(warped * 9.0 + vec3(5.0, 3.0, 1.0), 4);

	// Filamentary dust structures
	float dust = smoothstep(0.52, 0.72, d1) * smoothstep(0.38, 0.62, d2);

	// More dust near galactic plane
	float tilt = 0.3;
	float galactic_y = dir.y * cos(tilt) - dir.z * sin(tilt);
	float plane_boost = exp(-galactic_y * galactic_y / 0.15);

	return dust * (0.3 + plane_boost * 0.7) * dust_intensity;
}

// ─── Main sky function ──────────────────────────────────────────────────────

void sky() {
	vec3 dir = normalize(EYEDIR);

	// === NEBULA BACKGROUND ===
	vec3 nebula = nebula_field(dir);

	// === MILKY WAY ===
	float mw = milky_way_band(dir) * milky_way_intensity;
	vec3 mw_col = milky_way_color * mw;

	// Extra star density boost in Milky Way region
	float mw_star_boost = mw * 0.5;

	// === DARK DUST ===
	float dust = dust_field(dir);

	// === STAR LAYERS ===
	// Layer 1: Dim background stars (thousands of tiny dots)
	float dim_thresh = 1.0 - star_density * 0.85;
	float temp1;
	float stars_dim = star_point(dir, 250.0, dim_thresh, temp1) * 0.3;

	// Layer 2: Medium stars
	float med_thresh = 1.0 - star_density * 0.35;
	float temp2;
	float stars_med = star_point(dir, 100.0, med_thresh, temp2) * 0.7;

	// Layer 3: Bright prominent stars with color
	float bright_thresh = 1.0 - star_density * 0.1;
	float temp3;
	float stars_bright = star_point(dir, 35.0, bright_thresh, temp3) * 1.8;

	// Layer 4: Rare very bright stars (navigation stars)
	float rare_thresh = 1.0 - star_density * 0.02;
	float temp4;
	float stars_rare = star_point(dir, 15.0, rare_thresh, temp4) * 3.0;

	// Twinkle (affects medium/bright stars more)
	float twinkle_seed = _hash31(floor(dir * 100.0));
	float twinkle = sin(TIME * twinkle_speed + twinkle_seed * TAU) * 0.25 + 0.75;
	float twinkle2 = sin(TIME * twinkle_speed * 0.7 + twinkle_seed * 3.14) * 0.15 + 0.85;

	// Combine star layers with individual colors
	vec3 dim_col = star_color_temp(temp1) * stars_dim;
	vec3 med_col = star_color_temp(temp2) * stars_med * twinkle2;
	vec3 bright_col = star_color_temp(temp3) * stars_bright * twinkle;
	vec3 rare_col = star_color_temp(temp4) * stars_rare * twinkle;

	vec3 total_stars = (dim_col + med_col + bright_col + rare_col) * star_brightness;

	// Boost star count in Milky Way
	float mw_dim_thresh = dim_thresh - mw_star_boost * 0.3;
	float temp_mw;
	float mw_stars = star_point(dir, 180.0, max(mw_dim_thresh, 0.1), temp_mw) * 0.25;
	total_stars += star_color_temp(temp_mw) * mw_stars * star_brightness;

	// === COMPOSE ===
	vec3 sky_color = vec3(0.0);

	// Base deep space (very subtle gradient)
	sky_color += vec3(0.003, 0.003, 0.008);

	// Add nebulae
	sky_color += nebula;

	// Add Milky Way glow
	sky_color += mw_col;

	// Apply dust (absorbs light behind it)
	sky_color *= (1.0 - dust * 0.7);

	// Add stars on top (dust partially dims stars too)
	total_stars *= (1.0 - dust * 0.4);
	sky_color += total_stars;

	COLOR = sky_color;
}
