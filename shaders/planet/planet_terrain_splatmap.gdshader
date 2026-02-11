shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// =============================================================================
// Planet Terrain Splatmap v2 — Realistic biome-based procedural terrain coloring
//
// Key improvements:
// - Proper noise frequencies (6-8 cycles on unit sphere, not 0.5!)
// - Domain warping for organic continent-like biome shapes
// - Smooth weight-based biome blending (no hard edges)
// - Multi-scale detail: continental → regional → local → micro
// - Normal perturbation for surface texture
// - PBR roughness per biome
// =============================================================================

// --- Biome color palettes ---
group_uniforms biome_colors;
uniform vec4 biome_ocean_base : source_color = vec4(0.04, 0.12, 0.35, 1.0);
uniform vec4 biome_beach_base : source_color = vec4(0.76, 0.70, 0.50, 1.0);
uniform vec4 biome_desert_base : source_color = vec4(0.82, 0.72, 0.45, 1.0);
uniform vec4 biome_desert_accent : source_color = vec4(0.70, 0.55, 0.32, 1.0);
uniform vec4 biome_savanna_base : source_color = vec4(0.62, 0.58, 0.28, 1.0);
uniform vec4 biome_savanna_accent : source_color = vec4(0.55, 0.50, 0.22, 1.0);
uniform vec4 biome_grass_base : source_color = vec4(0.25, 0.45, 0.12, 1.0);
uniform vec4 biome_grass_accent : source_color = vec4(0.32, 0.55, 0.18, 1.0);
uniform vec4 biome_forest_base : source_color = vec4(0.10, 0.30, 0.08, 1.0);
uniform vec4 biome_forest_accent : source_color = vec4(0.14, 0.38, 0.10, 1.0);
uniform vec4 biome_rainforest_base : source_color = vec4(0.06, 0.24, 0.05, 1.0);
uniform vec4 biome_taiga_base : source_color = vec4(0.14, 0.25, 0.14, 1.0);
uniform vec4 biome_tundra_base : source_color = vec4(0.45, 0.50, 0.42, 1.0);
uniform vec4 biome_snow_base : source_color = vec4(0.90, 0.92, 0.95, 1.0);
uniform vec4 biome_snow_accent : source_color = vec4(0.82, 0.87, 0.92, 1.0);
uniform vec4 biome_volcanic_base : source_color = vec4(0.20, 0.12, 0.08, 1.0);
uniform vec4 biome_volcanic_accent : source_color = vec4(0.80, 0.25, 0.05, 1.0);
uniform vec4 biome_mountain_base : source_color = vec4(0.45, 0.42, 0.38, 1.0);
uniform vec4 biome_cliff_color : source_color = vec4(0.32, 0.30, 0.26, 1.0);

group_uniforms terrain;
uniform float planet_radius = 50000.0;
uniform float ocean_level : hint_range(0.0, 0.5) = 0.0;
uniform float cliff_threshold : hint_range(0.0, 1.0) = 0.55;
uniform int planet_type_id : hint_range(0, 4) = 0; // 0=ROCKY,1=LAVA,2=OCEAN,3=GAS,4=ICE
uniform float terrain_amplitude : hint_range(0.01, 0.2) = 0.06;

group_uniforms noise_seeds;
uniform float moisture_seed = 5000.0;
uniform float temperature_seed = 7000.0;

// Geo-morph: 0 = coarse (parent LOD appearance), 1 = full detail
instance uniform float morph_factor : hint_range(0.0, 1.0) = 1.0;

varying float v_height;
varying float v_slope;
varying vec3 v_sphere_normal;
varying vec3 v_world_pos;
varying vec3 v_world_normal;

// =============================================================================
// Noise — gradient noise (Perlin-style) with proper 3D hashing
// =============================================================================

vec3 _hash33(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}

float gnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = dot(_hash33(i), f);
	float n100 = dot(_hash33(i + vec3(1,0,0)), f - vec3(1,0,0));
	float n010 = dot(_hash33(i + vec3(0,1,0)), f - vec3(0,1,0));
	float n110 = dot(_hash33(i + vec3(1,1,0)), f - vec3(1,1,0));
	float n001 = dot(_hash33(i + vec3(0,0,1)), f - vec3(0,0,1));
	float n101 = dot(_hash33(i + vec3(1,0,1)), f - vec3(1,0,1));
	float n011 = dot(_hash33(i + vec3(0,1,1)), f - vec3(0,1,1));
	float n111 = dot(_hash33(i + vec3(1,1,1)), f - vec3(1,1,1));
	float x0 = mix(n000, n100, u.x);
	float x1 = mix(n010, n110, u.x);
	float x2 = mix(n001, n101, u.x);
	float x3 = mix(n011, n111, u.x);
	return mix(mix(x0, x1, u.y), mix(x2, x3, u.y), u.z) * 0.5 + 0.5;
}

// FBM with variable octaves
float fbm(vec3 p, int octaves) {
	float v = 0.0, a = 0.5, total = 0.0;
	for (int i = 0; i < octaves; i++) {
		v += a * gnoise(p);
		total += a;
		p *= 2.1;
		a *= 0.5;
	}
	return v / total;
}

// Domain-warped FBM — creates organic continent-like shapes
float warped_fbm(vec3 p, int octaves) {
	vec3 warp = vec3(
		fbm(p + vec3(0.0, 0.0, 0.0), 3),
		fbm(p + vec3(5.2, 1.3, 2.8), 3),
		fbm(p + vec3(1.7, 9.2, 6.1), 3)
	);
	return fbm(p + warp * 1.2, octaves);
}

// =============================================================================
// Climate — proper frequencies on unit sphere!
// sphere_n is unit vector: components in [-1, 1]
// freq 6.0 → ~12 biome regions across the planet (like real continents)
// =============================================================================

vec2 get_climate(vec3 sn, float height) {
	float latitude = abs(sn.y);

	// --- Moisture: domain-warped FBM for organic continent shapes ---
	vec3 mpos = sn * 6.0 + vec3(moisture_seed * 0.0137, 0.0, 0.0);
	float moisture = warped_fbm(mpos, 5);
	// Add finer detail
	moisture += gnoise(sn * 18.0 + vec3(moisture_seed * 0.023, 0.0, 0.0)) * 0.12;
	moisture = clamp(moisture, 0.0, 1.0);

	// --- Temperature: latitude gradient + continental noise ---
	float base_temp = 1.0 - pow(latitude, 1.3) * 0.9;
	vec3 tpos = sn * 5.0 + vec3(0.0, temperature_seed * 0.0137, 0.0);
	float temp_noise = warped_fbm(tpos, 4) * 0.35 - 0.175;
	float alt_cool = height / max(terrain_amplitude, 0.001) * 0.35;
	float temperature = clamp(base_temp + temp_noise - alt_cool, 0.0, 1.0);

	return vec2(temperature, moisture);
}

// =============================================================================
// Biome blending — smooth weight function, no hard edges
// Returns 0-1 weight based on distance from ideal (temp, moisture) center
// =============================================================================

float biome_weight(float temp, float moist, float ct, float cm, float rt, float rm) {
	float dt = abs(temp - ct) / rt;
	float dm = abs(moist - cm) / rm;
	float d = max(dt, dm);
	return clamp(1.0 - d, 0.0, 1.0);
}

// =============================================================================
// Biome coloring — all planet types with smooth blending
// =============================================================================

vec3 get_biome_color(vec2 climate, float height, vec3 sn) {
	float temp = climate.x;
	float moist = climate.y;
	float norm_h = height / max(terrain_amplitude, 0.001);

	// Within-biome variation noise (visible at medium distance)
	float var1 = gnoise(sn * 40.0) * 0.25 + 0.875;
	float var2 = gnoise(sn * 120.0) * 0.12 + 0.94;
	float detail = var1 * var2;

	// ===== LAVA PLANET =====
	if (planet_type_id == 1) {
		float crack1 = gnoise(sn * 25.0);
		float crack2 = gnoise(sn * 80.0);
		float crack = smoothstep(0.42, 0.58, crack1 * 0.65 + crack2 * 0.35);
		vec3 rock = mix(biome_volcanic_base.rgb, biome_mountain_base.rgb, norm_h * 0.7) * detail;
		// Lava glows brighter in lowlands, animated pulse
		float glow = 1.5 + gnoise(sn * 50.0) * 0.5;
		vec3 lava = biome_volcanic_accent.rgb * glow;
		float lava_mask = clamp((1.0 - norm_h * 1.5) * crack, 0.0, 1.0);
		return mix(rock, lava, lava_mask);
	}

	// ===== ICE PLANET =====
	if (planet_type_id == 4) {
		float lat = abs(sn.y);
		float ice_noise = gnoise(sn * 12.0) * 0.2;
		float ice = smoothstep(0.15, 0.55, lat + ice_noise) + smoothstep(0.25, 0.7, norm_h);
		ice = clamp(ice, 0.0, 1.0);
		vec3 taiga_col = biome_taiga_base.rgb * detail;
		vec3 tundra_col = biome_tundra_base.rgb * detail;
		vec3 snow_col = mix(biome_snow_base.rgb, biome_snow_accent.rgb, gnoise(sn * 45.0));
		// Crevasse detail in ice
		float crev = smoothstep(0.45, 0.55, gnoise(sn * 60.0));
		snow_col = mix(snow_col, vec3(0.65, 0.72, 0.82), crev * 0.25);
		vec3 base_col = mix(taiga_col, tundra_col, smoothstep(0.25, 0.5, lat + ice_noise));
		return mix(base_col, snow_col, ice);
	}

	// ===== STANDARD PLANETS (ROCKY / OCEAN) — smooth biome blending =====

	// Below ocean level
	if (height < ocean_level && ocean_level > 0.001) {
		return biome_ocean_base.rgb;
	}

	// Compute weights for each biome (soft Voronoi-like classification)
	float w_desert     = biome_weight(temp, moist, 0.85, 0.15, 0.22, 0.22);
	float w_savanna    = biome_weight(temp, moist, 0.72, 0.38, 0.22, 0.22);
	float w_grass      = biome_weight(temp, moist, 0.58, 0.55, 0.25, 0.22);
	float w_forest     = biome_weight(temp, moist, 0.50, 0.72, 0.22, 0.20);
	float w_rainforest = biome_weight(temp, moist, 0.82, 0.88, 0.18, 0.15);
	float w_taiga      = biome_weight(temp, moist, 0.25, 0.58, 0.22, 0.28);
	float w_tundra     = biome_weight(temp, moist, 0.15, 0.30, 0.18, 0.28);
	float w_snow       = biome_weight(temp, moist, 0.06, 0.50, 0.12, 0.50);

	// Square weights for sharper (but still smooth) transitions
	w_desert *= w_desert;
	w_savanna *= w_savanna;
	w_grass *= w_grass;
	w_forest *= w_forest;
	w_rainforest *= w_rainforest;
	w_taiga *= w_taiga;
	w_tundra *= w_tundra;
	w_snow *= w_snow;

	// Normalize
	float total_w = w_desert + w_savanna + w_grass + w_forest
		+ w_rainforest + w_taiga + w_tundra + w_snow + 0.0001;

	// Per-biome colors with internal variation
	vec3 c_desert   = mix(biome_desert_base.rgb, biome_desert_accent.rgb, gnoise(sn * 22.0));
	vec3 c_savanna  = mix(biome_savanna_base.rgb, biome_savanna_accent.rgb, gnoise(sn * 28.0));
	vec3 c_grass    = mix(biome_grass_base.rgb, biome_grass_accent.rgb, gnoise(sn * 32.0));
	vec3 c_forest   = mix(biome_forest_base.rgb, biome_forest_accent.rgb, gnoise(sn * 38.0));
	vec3 c_rain     = biome_rainforest_base.rgb;
	vec3 c_taiga    = biome_taiga_base.rgb;
	vec3 c_tundra   = biome_tundra_base.rgb;
	vec3 c_snow     = mix(biome_snow_base.rgb, biome_snow_accent.rgb, gnoise(sn * 18.0));

	// Weighted blend
	vec3 col = (c_desert * w_desert + c_savanna * w_savanna + c_grass * w_grass
		+ c_forest * w_forest + c_rain * w_rainforest + c_taiga * w_taiga
		+ c_tundra * w_tundra + c_snow * w_snow) / total_w;

	// Apply within-biome detail
	col *= detail;

	// Beach strip (just above ocean)
	float above_ocean = max(height - ocean_level, 0.0);
	if (ocean_level > 0.001) {
		float beach_blend = 1.0 - smoothstep(0.0, terrain_amplitude * 0.06, above_ocean);
		col = mix(col, biome_beach_base.rgb * detail, beach_blend);
	}

	// Mountain/snow cap overlay at high altitude
	float mountain_blend = smoothstep(0.60, 0.82, norm_h);
	float snow_cap = smoothstep(0.72, 0.92, norm_h) * smoothstep(0.1, 0.35, 1.0 - temp);
	vec3 mountain_col = biome_mountain_base.rgb * detail;
	col = mix(col, mountain_col, mountain_blend * (1.0 - snow_cap));
	col = mix(col, c_snow, snow_cap);

	return col;
}

// =============================================================================
// Vertex / Fragment
// =============================================================================

void vertex() {
	// Geo-morph: blend vertex between coarse (parent LOD) and fine (current LOD) position
	// CUSTOM0.xyz = position morph delta (fine_pos - coarse_pos)
	// CUSTOM1.xyz = normal morph delta (fine_normal - coarse_normal)
	// morph_factor=0 → coarse (parent LOD), morph_factor=1 → full detail
	float inv_morph = 1.0 - morph_factor;
	VERTEX -= CUSTOM0.xyz * inv_morph;
	NORMAL = normalize(NORMAL - CUSTOM1.xyz * inv_morph);

	float dist = length(VERTEX);
	v_height = clamp(dist / planet_radius - 1.0, 0.0, terrain_amplitude * 2.0);
	v_sphere_normal = normalize(VERTEX);
	v_slope = 1.0 - abs(dot(NORMAL, v_sphere_normal));
	v_world_pos = VERTEX;
	v_world_normal = NORMAL;
}

void fragment() {
	vec3 sn = normalize(v_sphere_normal);
	vec2 climate = get_climate(sn, v_height);
	vec3 col = get_biome_color(climate, v_height, sn);

	// Cliff blending (steep slopes → exposed rock)
	float cliff_blend = smoothstep(cliff_threshold, cliff_threshold + 0.15, v_slope);
	vec3 cliff_col = biome_cliff_color.rgb * (gnoise(sn * 60.0) * 0.2 + 0.9);
	col = mix(col, cliff_col, cliff_blend * 0.8);

	// Tri-planar micro-detail (visible at close range — breaks up flat areas)
	vec3 abs_n = abs(normalize(v_world_normal));
	vec3 blend = abs_n * abs_n * abs_n;
	blend /= (blend.x + blend.y + blend.z + 0.0001);
	float scale = 0.001;
	float d1 = gnoise(vec3(v_world_pos.yz * scale, 0.0));
	float d2 = gnoise(vec3(v_world_pos.xz * scale, 0.0));
	float d3 = gnoise(vec3(v_world_pos.xy * scale, 0.0));
	float micro = d1 * blend.x + d2 * blend.y + d3 * blend.z;
	col *= 0.88 + micro * 0.24;

	// --- Normal perturbation (fake bump from noise gradient) ---
	// Compute noise gradient for tangent-space bump
	float bump_freq = 80.0;
	vec3 bp = sn * bump_freq;
	float eps = 0.002;
	float h_c = gnoise(bp);
	float h_x = gnoise(bp + vec3(eps, 0.0, 0.0));
	float h_z = gnoise(bp + vec3(0.0, 0.0, eps));
	// Tangent-space perturbation projected onto the existing normal
	vec3 grad = vec3((h_x - h_c) / eps, 0.0, (h_z - h_c) / eps);
	vec3 perturbed = normalize(NORMAL - grad * 0.15);
	NORMAL = perturbed;

	ALBEDO = col;

	// PBR roughness per biome region
	float roughness = 0.85;
	float temp = climate.x;
	float moist = climate.y;
	if (v_height < ocean_level && ocean_level > 0.001) {
		roughness = 0.05;
	} else if (temp < 0.15) {
		roughness = 0.35; // Ice/snow
	} else if (moist > 0.7 && temp > 0.5) {
		roughness = 0.92; // Wet forest
	} else if (moist < 0.2 && temp > 0.6) {
		roughness = 0.78; // Dry desert
	}
	// Cliffs are rough
	roughness = mix(roughness, 0.95, cliff_blend);
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
