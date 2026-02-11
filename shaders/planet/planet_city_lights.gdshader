shader_type spatial;
render_mode blend_add, cull_back, unshaded, shadows_disabled;

// =============================================================================
// City Lights — Emissive patches on the night side of a planet.
// Applied to a sphere mesh slightly larger than the terrain.
// Noise-driven clusters produce a convincing city-light pattern.
// Bloom (HDR emission) makes them visible from orbit.
// =============================================================================

uniform vec3 sun_direction = vec3(0.0, 0.0, 1.0);
uniform int city_seed = 0;

// --- Hash-based value noise ---
float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 397.297, 491.187));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);  // smoothstep
	float a = hash31(i);
	float b = hash31(i + vec3(1, 0, 0));
	float c = hash31(i + vec3(0, 1, 0));
	float d = hash31(i + vec3(1, 1, 0));
	float e = hash31(i + vec3(0, 0, 1));
	float f2 = hash31(i + vec3(1, 0, 1));
	float g = hash31(i + vec3(0, 1, 1));
	float h = hash31(i + vec3(1, 1, 1));
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
			   mix(mix(e, f2, f.x), mix(g, h, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.17;
		amp *= 0.48;
	}
	return v;
}

void fragment() {
	// World-space normal (sphere surface direction)
	vec3 nws = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 sun = normalize(sun_direction);

	// Night mask: 1 on dark side, 0 on lit side
	float night = smoothstep(0.05, -0.2, dot(nws, sun));
	if (night < 0.005) {
		discard;
	}

	// City cluster noise (low freq clusters + high freq detail)
	vec3 sp = nws;  // sphere point approximation from normal
	float seed_f = float(city_seed) * 0.0137;
	float cluster = fbm(sp * 28.0 + seed_f);
	float city = smoothstep(0.52, 0.68, cluster);

	// Fine detail within clusters (individual light patches)
	float detail = vnoise(sp * 180.0 + seed_f * 3.0);
	city *= smoothstep(0.28, 0.55, detail);

	// Color: warm orange to white for brighter areas
	vec3 warm = vec3(1.0, 0.72, 0.32);
	vec3 white = vec3(1.0, 0.92, 0.75);
	vec3 col = mix(warm, white, detail * city);

	// Slight twinkle / variation
	float twinkle = vnoise(sp * 400.0 + seed_f * 7.0);
	city *= 0.7 + 0.3 * twinkle;

	float intensity = city * night;
	ALBEDO = vec3(0.0);
	EMISSION = col * intensity * 3.0;  // HDR for bloom
	ALPHA = intensity;
}
