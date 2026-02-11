shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// =============================================================================
// Planet Terrain Splatmap — Biome-based procedural terrain coloring
// Determines biome from latitude + altitude + noise, then colors per-biome.
// Tri-planar detail noise for surface texture. PBR lit by sun.
// =============================================================================

// --- Biome color palettes (12 biomes x 3 colors: base, accent, detail) ---
group_uniforms biome_colors;
uniform vec4 biome_ocean_base : source_color = vec4(0.04, 0.12, 0.35, 1.0);
uniform vec4 biome_beach_base : source_color = vec4(0.76, 0.70, 0.50, 1.0);
uniform vec4 biome_desert_base : source_color = vec4(0.80, 0.68, 0.40, 1.0);
uniform vec4 biome_desert_accent : source_color = vec4(0.72, 0.55, 0.30, 1.0);
uniform vec4 biome_savanna_base : source_color = vec4(0.55, 0.50, 0.22, 1.0);
uniform vec4 biome_savanna_accent : source_color = vec4(0.65, 0.58, 0.28, 1.0);
uniform vec4 biome_grass_base : source_color = vec4(0.22, 0.42, 0.10, 1.0);
uniform vec4 biome_grass_accent : source_color = vec4(0.30, 0.52, 0.15, 1.0);
uniform vec4 biome_forest_base : source_color = vec4(0.08, 0.28, 0.06, 1.0);
uniform vec4 biome_forest_accent : source_color = vec4(0.12, 0.35, 0.08, 1.0);
uniform vec4 biome_rainforest_base : source_color = vec4(0.05, 0.22, 0.04, 1.0);
uniform vec4 biome_taiga_base : source_color = vec4(0.12, 0.22, 0.12, 1.0);
uniform vec4 biome_tundra_base : source_color = vec4(0.42, 0.48, 0.40, 1.0);
uniform vec4 biome_snow_base : source_color = vec4(0.88, 0.90, 0.94, 1.0);
uniform vec4 biome_snow_accent : source_color = vec4(0.80, 0.85, 0.90, 1.0);
uniform vec4 biome_volcanic_base : source_color = vec4(0.18, 0.10, 0.06, 1.0);
uniform vec4 biome_volcanic_accent : source_color = vec4(0.75, 0.22, 0.04, 1.0);
uniform vec4 biome_mountain_base : source_color = vec4(0.42, 0.40, 0.36, 1.0);
uniform vec4 biome_cliff_color : source_color = vec4(0.30, 0.28, 0.24, 1.0);

group_uniforms terrain;
uniform float planet_radius = 50000.0;
uniform float ocean_level : hint_range(0.0, 0.5) = 0.0;
uniform float cliff_threshold : hint_range(0.0, 1.0) = 0.55;
uniform int planet_type_id : hint_range(0, 4) = 0; // 0=ROCKY,1=LAVA,2=OCEAN,3=GAS,4=ICE
uniform float terrain_amplitude : hint_range(0.01, 0.2) = 0.06;

group_uniforms noise_seeds;
uniform float moisture_seed = 5000.0;
uniform float temperature_seed = 7000.0;

group_uniforms detail;
uniform float triplanar_scale : hint_range(0.00001, 0.01) = 0.0008;

varying float v_height;
varying float v_slope;
varying vec3 v_sphere_normal; // Normalized direction from planet center (sphere pos)
varying vec3 v_world_pos;
varying vec3 v_world_normal;

// =============================================================================
// Noise (simplified for GPU — matches CPU BiomeGenerator patterns)
// =============================================================================

vec3 _hash33(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}

float _value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = dot(_hash33(i), f);
	float n100 = dot(_hash33(i + vec3(1,0,0)), f - vec3(1,0,0));
	float n010 = dot(_hash33(i + vec3(0,1,0)), f - vec3(0,1,0));
	float n110 = dot(_hash33(i + vec3(1,1,0)), f - vec3(1,1,0));
	float n001 = dot(_hash33(i + vec3(0,0,1)), f - vec3(0,0,1));
	float n101 = dot(_hash33(i + vec3(1,0,1)), f - vec3(1,0,1));
	float n011 = dot(_hash33(i + vec3(0,1,1)), f - vec3(0,1,1));
	float n111 = dot(_hash33(i + vec3(1,1,1)), f - vec3(1,1,1));
	float x0 = mix(n000, n100, f.x);
	float x1 = mix(n010, n110, f.x);
	float x2 = mix(n001, n101, f.x);
	float x3 = mix(n011, n111, f.x);
	float y0 = mix(x0, x1, f.y);
	float y1 = mix(x2, x3, f.y);
	return mix(y0, y1, f.z) * 0.5 + 0.5;
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * _value_noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

// =============================================================================
// Biome classification (GPU-side, mirrors BiomeGenerator logic)
// =============================================================================

// Returns: x=temperature, y=moisture (both 0-1)
vec2 get_climate(vec3 sphere_n, float height) {
	float latitude = abs(sphere_n.y);

	// Moisture noise
	vec3 mpos = sphere_n * 1000.0 + vec3(moisture_seed, 0.0, 0.0);
	float moisture = fbm3(mpos * 0.0005);

	// Temperature: hot equator, cold poles, colder at altitude
	float base_temp = 1.0 - latitude * 0.8;
	vec3 tpos = sphere_n * 1000.0 + vec3(temperature_seed, 0.0, 0.0);
	float temp_noise = fbm3(tpos * 0.00035) * 0.25;
	float temperature = clamp(base_temp + temp_noise - height * 3.0, 0.0, 1.0);

	return vec2(temperature, moisture);
}

// Get biome color from climate + height + slope
vec3 get_biome_color(vec2 climate, float height, float slope, vec3 sphere_n) {
	float temp = climate.x;
	float moist = climate.y;

	// Detail noise for variation within biome
	float detail = _value_noise(sphere_n * 500.0) * 0.3 + 0.7;

	vec3 col;

	// Lava planet override
	if (planet_type_id == 1) {
		if (height < 0.02) {
			col = mix(biome_volcanic_base.rgb, biome_volcanic_accent.rgb, detail);
			// Lava glow in cracks
			float crack = smoothstep(0.4, 0.5, _value_noise(sphere_n * 2000.0));
			col = mix(col, biome_volcanic_accent.rgb * 2.0, crack * 0.5);
		} else if (height > terrain_amplitude * 0.75) {
			col = biome_mountain_base.rgb * detail;
		} else {
			col = mix(biome_desert_base.rgb, biome_mountain_base.rgb, height / terrain_amplitude) * detail;
		}
		return col;
	}

	// Ice planet override
	if (planet_type_id == 4) {
		float lat = abs(sphere_n.y);
		if (height > terrain_amplitude * 0.5 || lat > 0.6) {
			col = mix(biome_snow_base.rgb, biome_snow_accent.rgb, detail);
		} else if (lat > 0.3) {
			col = biome_tundra_base.rgb * detail;
		} else {
			col = biome_taiga_base.rgb * detail;
		}
		return col;
	}

	// Ocean
	if (height < ocean_level && ocean_level > 0.001) {
		return biome_ocean_base.rgb;
	}

	// Beach (just above ocean)
	float above_ocean = height - ocean_level;
	if (ocean_level > 0.001 && above_ocean < terrain_amplitude * 0.05) {
		float beach_t = above_ocean / (terrain_amplitude * 0.05);
		return mix(biome_beach_base.rgb, biome_grass_base.rgb, beach_t) * detail;
	}

	// High altitude → mountain/snow
	if (height > terrain_amplitude * 0.8) {
		if (temp < 0.3) {
			col = mix(biome_snow_base.rgb, biome_snow_accent.rgb, detail);
		} else {
			col = biome_mountain_base.rgb * detail;
		}
		return col;
	}

	// Main biome classification
	if (temp > 0.7) {
		if (moist < 0.3) {
			col = mix(biome_desert_base.rgb, biome_desert_accent.rgb, detail);
		} else if (moist < 0.55) {
			col = mix(biome_savanna_base.rgb, biome_savanna_accent.rgb, detail);
		} else if (moist < 0.75) {
			col = mix(biome_grass_base.rgb, biome_grass_accent.rgb, detail);
		} else {
			col = biome_rainforest_base.rgb * detail;
		}
	} else if (temp > 0.4) {
		if (moist < 0.25) {
			col = mix(biome_savanna_base.rgb, biome_grass_base.rgb, detail);
		} else if (moist < 0.55) {
			col = mix(biome_grass_base.rgb, biome_grass_accent.rgb, detail);
		} else {
			col = mix(biome_forest_base.rgb, biome_forest_accent.rgb, detail);
		}
	} else if (temp > 0.2) {
		if (moist < 0.4) {
			col = biome_tundra_base.rgb * detail;
		} else {
			col = biome_taiga_base.rgb * detail;
		}
	} else {
		col = mix(biome_snow_base.rgb, biome_tundra_base.rgb, temp * 5.0) * detail;
	}

	return col;
}

// =============================================================================
// Vertex / Fragment
// =============================================================================

void vertex() {
	float dist = length(VERTEX);
	v_height = clamp(dist / planet_radius - 1.0, 0.0, terrain_amplitude * 2.0);
	v_sphere_normal = normalize(VERTEX);
	v_slope = 1.0 - abs(dot(NORMAL, v_sphere_normal));
	v_world_pos = VERTEX;
	v_world_normal = abs(normalize(NORMAL));
}

void fragment() {
	vec2 climate = get_climate(v_sphere_normal, v_height);
	vec3 col = get_biome_color(climate, v_height, v_slope, v_sphere_normal);

	// Cliff blending (steep slopes get rock color regardless of biome)
	if (v_slope > cliff_threshold) {
		float cliff_blend = clamp((v_slope - cliff_threshold) / (1.0 - cliff_threshold), 0.0, 1.0);
		col = mix(col, biome_cliff_color.rgb, cliff_blend * 0.75);
	}

	// Tri-planar detail noise for micro-variation (breaks up flat areas)
	vec3 blend = v_world_normal;
	blend = blend * blend * blend;
	blend /= (blend.x + blend.y + blend.z + 0.0001);
	float d1 = _value_noise(vec3(v_world_pos.yz * triplanar_scale * 1000.0, 0.0));
	float d2 = _value_noise(vec3(v_world_pos.xz * triplanar_scale * 1000.0, 0.0));
	float d3 = _value_noise(vec3(v_world_pos.xy * triplanar_scale * 1000.0, 0.0));
	float detail = d1 * blend.x + d2 * blend.y + d3 * blend.z;
	col *= 0.85 + detail * 0.3;

	// PBR output
	ALBEDO = col;

	// Roughness varies by biome region
	float base_rough = 0.82;
	if (v_height < ocean_level && ocean_level > 0.001) {
		base_rough = 0.08; // Water-like
	} else if (climate.x < 0.15) {
		base_rough = 0.45; // Snow/ice is somewhat reflective
	}
	ROUGHNESS = base_rough;
	METALLIC = 0.0;
}
