shader_type spatial;
render_mode shadows_disabled;

// =============================================================================
// Planet Impostor Surface — Procedural per-type planet visuals
// Samples 3D noise via object-space NORMAL (no UV seams on sphere).
// Types: 0=ROCKY, 1=LAVA, 2=OCEAN, 3=GAS_GIANT, 4=ICE
// Domain warping for organic shapes, sun-aware terminator.
// =============================================================================

uniform int planet_type : hint_range(0, 4) = 0;
uniform vec4 planet_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float planet_seed : hint_range(0.0, 1000.0) = 0.0;
uniform vec3 sun_direction = vec3(0.0, 0.3, -1.0);

varying vec3 local_normal;
varying vec3 local_pos;

// =============================================================================
// Noise functions
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

float fbm2(vec3 p) {
	return noise3d(p) * 0.65 + noise3d(p * 2.03) * 0.35;
}

float fbm3(vec3 p) {
	return noise3d(p) * 0.5 + noise3d(p * 2.03) * 0.3 + noise3d(p * 4.07) * 0.2;
}

float fbm4(vec3 p) {
	return noise3d(p) * 0.42 + noise3d(p * 2.03) * 0.28
		 + noise3d(p * 4.07) * 0.18 + noise3d(p * 8.15) * 0.12;
}

// Domain-warped FBM for organic continent shapes
float warped_fbm(vec3 p, float warp, vec3 off_a, vec3 off_b) {
	float wx = fbm2(p + off_a);
	float wy = fbm2(p + off_b);
	float wz = fbm2(p + off_a + off_b);
	return fbm3(p + vec3(wx, wy, wz) * warp);
}

// =============================================================================
// Per-type surface functions
// =============================================================================

// ROCKY: domain-warped continents, oceans, deserts, mountains, polar caps, clouds
vec3 rocky_surface(vec3 n, vec3 seed_off, vec3 base_col, out float spec_mask) {
	spec_mask = 0.0;
	// Domain-warped continent shapes
	float continent = warped_fbm(n * 2.5 + seed_off, 0.6, seed_off * 0.3, seed_off * 0.7);
	float detail = fbm4(n * 10.0 + seed_off * 2.0);
	float mountain = fbm3(n * 7.0 + seed_off * 1.5);

	// Land vs ocean threshold
	float land_mask = smoothstep(0.43, 0.50, continent);

	// Land: elevation-based coloring
	vec3 lowland = base_col * 0.55 + vec3(0.04, 0.07, 0.01); // Greenish lowlands
	vec3 highland = base_col * 0.7 + vec3(0.08, 0.05, 0.02); // Brown highlands
	vec3 mountain_col = base_col * 0.4 + vec3(0.12, 0.10, 0.08); // Grey mountains
	vec3 desert = base_col * 0.6 + vec3(0.12, 0.08, 0.02); // Sandy desert

	// Elevation layers
	float elev = continent * 0.6 + mountain * 0.4;
	vec3 land = mix(lowland, highland, smoothstep(0.5, 0.62, elev));
	land = mix(land, mountain_col, smoothstep(0.65, 0.78, elev));
	// Desert near equator
	float equator = 1.0 - abs(n.y);
	float desert_mask = smoothstep(0.5, 0.55, continent) * (1.0 - smoothstep(0.6, 0.7, continent));
	desert_mask *= smoothstep(0.5, 0.8, equator);
	land = mix(land, desert, desert_mask * 0.5);

	// Surface detail roughness
	land += (detail - 0.5) * 0.06;

	// Ocean: depth-based color
	vec3 deep_ocean = vec3(0.01, 0.03, 0.10);
	vec3 mid_ocean = vec3(0.02, 0.06, 0.16);
	vec3 shallow = vec3(0.04, 0.11, 0.18);
	float ocean_depth = smoothstep(0.30, 0.43, continent);
	vec3 ocean = mix(deep_ocean, mid_ocean, ocean_depth);
	ocean = mix(ocean, shallow, smoothstep(0.40, 0.44, continent));

	vec3 surface = mix(ocean, land, land_mask);
	spec_mask = (1.0 - land_mask) * 0.8; // Ocean is specular

	// Polar caps with irregular edges
	float latitude = abs(n.y);
	float cap_noise = fbm2(n * 5.0 + seed_off * 3.0) * 0.12;
	float polar = smoothstep(0.62 + cap_noise, 0.78 + cap_noise, latitude);
	surface = mix(surface, vec3(0.88, 0.91, 0.96), polar);
	spec_mask = mix(spec_mask, 0.3, polar); // Ice is slightly specular

	// Wispy clouds
	float cloud_base = warped_fbm(n * 4.0 + seed_off * 1.2, 0.4, seed_off * 0.5, seed_off * 0.9);
	float clouds = smoothstep(0.52, 0.68, cloud_base) * 0.22;
	surface = mix(surface, vec3(0.92, 0.93, 0.95), clouds);

	return surface;
}

// OCEAN: mostly water, scattered islands, thick cloud cover
vec3 ocean_surface(vec3 n, vec3 seed_off, vec3 base_col, out float spec_mask) {
	float terrain = warped_fbm(n * 3.5 + seed_off, 0.5, seed_off * 0.4, seed_off * 0.8);
	float detail = fbm4(n * 14.0 + seed_off * 2.0);

	// Mostly ocean, rare islands
	float island_mask = smoothstep(0.65, 0.72, terrain);

	vec3 deep = vec3(0.01, 0.03, 0.14);
	vec3 mid = vec3(0.02, 0.08, 0.22);
	vec3 shallow = vec3(0.04, 0.14, 0.26);
	vec3 island_low = vec3(0.08, 0.10, 0.04);
	vec3 island_high = vec3(0.14, 0.11, 0.06);

	float depth = smoothstep(0.35, 0.60, terrain);
	vec3 ocean = mix(deep, mid, depth);
	ocean = mix(ocean, shallow, smoothstep(0.58, 0.65, terrain));
	vec3 island = mix(island_low, island_high, smoothstep(0.70, 0.80, terrain));
	island += (detail - 0.5) * 0.04;

	vec3 surface = mix(ocean, island, island_mask);
	spec_mask = (1.0 - island_mask) * 0.9;

	// Large polar caps
	float latitude = abs(n.y);
	float cap_noise = fbm2(n * 4.0 + seed_off * 3.0) * 0.1;
	float polar = smoothstep(0.50 + cap_noise, 0.68 + cap_noise, latitude);
	surface = mix(surface, vec3(0.82, 0.87, 0.96), polar);

	// Dense cloud systems (weather patterns)
	float cloud1 = warped_fbm(n * 3.5 + seed_off * 1.3, 0.5, seed_off * 0.6, seed_off * 1.1);
	float cloud2 = fbm3(n * 6.0 + seed_off * 2.2);
	float clouds = smoothstep(0.40, 0.58, cloud1) * 0.35;
	clouds += smoothstep(0.55, 0.70, cloud2) * 0.15;
	// Cyclone swirl
	float swirl_lat = abs(n.y - 0.3);
	float cyclone = smoothstep(0.15, 0.0, swirl_lat) * smoothstep(0.5, 0.65, cloud1) * 0.2;
	clouds += cyclone;
	surface = mix(surface, vec3(0.94, 0.95, 0.97), clamp(clouds, 0.0, 0.5));
	spec_mask *= (1.0 - clamp(clouds * 1.5, 0.0, 0.8)); // Clouds reduce specular

	return surface;
}

// GAS_GIANT: turbulent banded atmosphere
vec3 gas_giant_surface(vec3 n, vec3 seed_off, vec3 base_col) {
	float lat = n.y;

	// Latitude-based banding with varying widths
	float band1 = sin(lat * 20.0 + seed_off.x * 2.0) * 0.5 + 0.5;
	float band2 = sin(lat * 35.0 + seed_off.y * 3.0 + 1.5) * 0.5 + 0.5;
	float band3 = sin(lat * 12.0 + seed_off.z * 1.5) * 0.5 + 0.5;
	float band_pattern = band1 * 0.45 + band2 * 0.35 + band3 * 0.20;

	// Turbulent distortion at band edges (shear)
	float shear = fbm3(n * vec3(8.0, 2.0, 8.0) + seed_off);
	float turb_fine = fbm4(n * vec3(16.0, 3.0, 16.0) + seed_off * 1.7);
	float edge_warp = (shear - 0.5) * 0.18 + (turb_fine - 0.5) * 0.06;

	// Color per band: warm darks and cool lights
	vec3 band_light = base_col * 1.3 + vec3(0.06, 0.04, 0.01);
	vec3 band_mid = base_col * 0.9;
	vec3 band_dark = base_col * 0.5 + vec3(0.03, 0.01, -0.01);

	float bp = clamp(band_pattern + edge_warp, 0.0, 1.0);
	vec3 surface = mix(band_dark, band_mid, smoothstep(0.25, 0.45, bp));
	surface = mix(surface, band_light, smoothstep(0.55, 0.75, bp));

	// Fine turbulence streaks
	surface += (shear - 0.5) * 0.08 * base_col;

	// Great Red Spot (or equivalent storm)
	vec3 storm_center = normalize(vec3(
		sin(seed_off.x * 2.3) * 0.55,
		-0.25 + sin(seed_off.y * 1.1) * 0.15,
		cos(seed_off.z * 2.3) * 0.55
	));
	float storm_dist = acos(clamp(dot(n, storm_center), -1.0, 1.0));
	float storm_size = 0.18 + fract(seed_off.x * 0.13) * 0.1;
	float storm = smoothstep(storm_size, storm_size * 0.2, storm_dist);
	// Internal swirl detail
	float swirl_angle = atan(
		dot(n - storm_center * dot(n, storm_center), normalize(cross(storm_center, vec3(0, 1, 0)))),
		dot(n - storm_center * dot(n, storm_center), normalize(cross(cross(storm_center, vec3(0, 1, 0)), storm_center)))
	);
	float swirl = fbm3(n * 20.0 + seed_off * 3.0 + vec3(swirl_angle * 2.0, storm_dist * 8.0, 0.0));
	vec3 storm_col = base_col * 1.1 + vec3(0.15, 0.04, -0.02);
	surface = mix(surface, storm_col + (swirl - 0.5) * 0.08, storm * 0.8);

	// Secondary smaller storms
	vec3 storm2_center = normalize(vec3(
		cos(seed_off.x * 3.1) * 0.7,
		0.4 + sin(seed_off.z * 2.0) * 0.1,
		sin(seed_off.y * 3.1) * 0.7
	));
	float storm2_dist = acos(clamp(dot(n, storm2_center), -1.0, 1.0));
	float storm2 = smoothstep(0.1, 0.03, storm2_dist);
	vec3 storm2_col = base_col * 0.85;
	surface = mix(surface, storm2_col, storm2 * 0.5);

	return surface;
}

// LAVA: dark crust with glowing lava veins
vec3 lava_surface(vec3 n, vec3 seed_off, out vec3 emission) {
	// Domain-warped cracks for more organic patterns
	float crust = warped_fbm(n * 4.0 + seed_off, 0.5, seed_off * 0.3, seed_off * 0.6);
	float cracks = warped_fbm(n * 8.0 + seed_off * 2.0, 0.4, seed_off * 0.8, seed_off * 1.2);
	float flow = fbm2(n * 2.5 + seed_off * 0.5);
	float detail = fbm4(n * 16.0 + seed_off * 3.0);

	// Dark volcanic crust with subtle variation
	vec3 dark_rock = vec3(0.04, 0.035, 0.03);
	vec3 warm_rock = vec3(0.08, 0.04, 0.025);
	vec3 surface = mix(dark_rock, warm_rock, crust * 0.6);
	surface += (detail - 0.5) * 0.02;

	// Lava rivers: where cracks meet flow channels
	float vein_raw = cracks * 0.6 + flow * 0.4;
	float vein_mask = smoothstep(0.45, 0.58, vein_raw);

	// Temperature gradient: yelllow-white core, orange edges, red cool
	vec3 lava_hot = vec3(1.8, 1.0, 0.3);   // Near-white hot
	vec3 lava_mid = vec3(1.4, 0.35, 0.04);  // Orange
	vec3 lava_cool = vec3(0.6, 0.08, 0.01); // Dark red

	float heat = pow(abs(vein_mask), 0.7);
	vec3 lava_col = mix(lava_cool, lava_mid, smoothstep(0.0, 0.5, heat));
	lava_col = mix(lava_col, lava_hot, smoothstep(0.6, 1.0, heat));

	surface = mix(surface, lava_col * 0.15, vein_mask * 0.5);

	// Emission for HDR bloom
	emission = lava_col * heat * 0.9;

	// Bright hotspot calderas
	float hotspot = smoothstep(0.70, 0.85, cracks * flow);
	emission += vec3(2.0, 0.8, 0.2) * hotspot * 0.6;

	return surface;
}

// ICE: glacial surface with crevasses and exposed rock
vec3 ice_surface(vec3 n, vec3 seed_off, vec3 base_col, out float spec_mask) {
	float terrain = warped_fbm(n * 3.5 + seed_off, 0.4, seed_off * 0.3, seed_off * 0.7);
	float detail = fbm4(n * 14.0 + seed_off * 2.0);
	float crevasse = fbm3(n * 22.0 + seed_off * 3.0);
	float large = fbm2(n * 1.5 + seed_off * 0.5);

	// Ice color variation
	vec3 ice_bright = vec3(0.88, 0.92, 0.98);
	vec3 ice_blue = vec3(0.50, 0.65, 0.88);
	vec3 ice_deep = vec3(0.30, 0.45, 0.72);

	vec3 surface = mix(ice_blue, ice_bright, terrain * 0.8 + 0.1);
	surface = mix(surface, ice_deep, smoothstep(0.35, 0.45, large) * 0.3);

	// Exposed rocky terrain
	float rock_mask = smoothstep(0.30, 0.38, terrain) * (1.0 - smoothstep(0.46, 0.54, terrain));
	vec3 rock = vec3(0.20, 0.18, 0.14);
	vec3 rock_dark = vec3(0.12, 0.10, 0.08);
	vec3 rock_col = mix(rock_dark, rock, detail);
	surface = mix(surface, rock_col, rock_mask * 0.7);

	// Deep crevasses (dark blue-black lines)
	float crack = smoothstep(0.47, 0.50, crevasse);
	surface = mix(surface, ice_deep * 0.4, crack * 0.5);

	// Surface frost shimmer
	surface += (detail - 0.5) * 0.05;

	spec_mask = mix(0.6, 0.1, rock_mask); // Ice is specular, rock is not

	return surface;
}

// =============================================================================
// Main
// =============================================================================

void vertex() {
	local_normal = NORMAL;
	local_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(local_normal);
	vec3 seed_offset = vec3(planet_seed, planet_seed * 0.7 + 13.37, planet_seed * 1.3 + 7.42);

	vec3 surface_color = vec3(0.5);
	vec3 emission = vec3(0.0);
	float metallic = 0.0;
	float roughness = 0.75;
	float spec_mask = 0.0;

	if (planet_type == 0) {
		// ROCKY
		surface_color = rocky_surface(n, seed_offset, planet_color.rgb, spec_mask);
		roughness = mix(0.85, 0.15, spec_mask); // Smooth ocean, rough land
	} else if (planet_type == 1) {
		// LAVA
		surface_color = lava_surface(n, seed_offset, emission);
		roughness = 0.9;
	} else if (planet_type == 2) {
		// OCEAN
		surface_color = ocean_surface(n, seed_offset, planet_color.rgb, spec_mask);
		roughness = mix(0.8, 0.08, spec_mask); // Very smooth ocean for sun glints
	} else if (planet_type == 3) {
		// GAS_GIANT
		surface_color = gas_giant_surface(n, seed_offset, planet_color.rgb);
		roughness = 0.7;
	} else {
		// ICE
		surface_color = ice_surface(n, seed_offset, planet_color.rgb, spec_mask);
		roughness = mix(0.85, 0.2, spec_mask); // Icy areas are specular
	}

	// --- Sun-aware ambient for dark side ---
	vec3 world_n = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	vec3 sun_dir = normalize(sun_direction);
	float ndotl = dot(world_n, sun_dir);

	// Soft terminator: slight ambient glow on dark side (scattered light through atmo)
	float ambient = 0.025;
	float terminator_glow = smoothstep(-0.05, 0.15, ndotl) * 0.02; // Soft light bleed at edge
	vec3 dark_emission = surface_color * (ambient + terminator_glow) * smoothstep(0.1, -0.3, ndotl);

	ALBEDO = surface_color;
	EMISSION = emission + dark_emission;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = mix(0.3, 0.7, spec_mask); // Higher specular on water/ice
}
