shader_type spatial;
render_mode cull_disabled, blend_mix, shadows_disabled, depth_draw_opaque;

// =============================================================================
// Planet Clouds — Animated procedural cloud layer
// FBM noise for cloud coverage, sun-lit with soft shadows on dark side.
// Visible from space (white patches) and from below (shadow on terrain).
// =============================================================================

uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shadow_color : source_color = vec4(0.15, 0.18, 0.25, 1.0);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_speed : hint_range(0.0, 0.1) = 0.008;
uniform float cloud_density : hint_range(0.1, 2.0) = 1.0;
uniform vec3 sun_direction = vec3(0.0, 0.3, -1.0);

varying vec3 local_normal;

// =============================================================================
// Noise (simplex-like hash noise for GPU)
// =============================================================================

vec3 _mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 _mod289v4(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 _permute(vec4 x) { return _mod289v4(((x * 34.0) + 1.0) * x); }
vec4 _taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
	const vec2 C = vec2(1.0/6.0, 1.0/3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);

	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);

	vec3 x1 = x0 - i1 + C.xxx;
	vec3 x2 = x0 - i2 + C.yyy;
	vec3 x3 = x0 - D.yyy;

	i = _mod289(i);
	vec4 p = _permute(_permute(_permute(
		i.z + vec4(0.0, i1.z, i2.z, 1.0))
		+ i.y + vec4(0.0, i1.y, i2.y, 1.0))
		+ i.x + vec4(0.0, i1.x, i2.x, 1.0));

	float n_ = 0.142857142857;
	vec3 ns = n_ * D.wyz - D.xzx;

	vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
	vec4 x_ = floor(j * ns.z);
	vec4 y_ = floor(j - 7.0 * x_);

	vec4 x = x_ * ns.x + ns.yyyy;
	vec4 y = y_ * ns.x + ns.yyyy;
	vec4 h = 1.0 - abs(x) - abs(y);

	vec4 b0 = vec4(x.xy, y.xy);
	vec4 b1 = vec4(x.zw, y.zw);

	vec4 s0 = floor(b0) * 2.0 + 1.0;
	vec4 s1 = floor(b1) * 2.0 + 1.0;
	vec4 sh = -step(h, vec4(0.0));

	vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
	vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

	vec3 p0 = vec3(a0.xy, h.x);
	vec3 p1 = vec3(a0.zw, h.y);
	vec3 p2 = vec3(a1.xy, h.z);
	vec3 p3 = vec3(a1.zw, h.w);

	vec4 norm = _taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
	p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;

	vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
	m = m * m;
	return 42.0 * dot(m * m, vec4(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 5; i++) {
		value += amplitude * snoise(p * frequency);
		amplitude *= 0.5;
		frequency *= 2.1;
	}
	return value;
}

// =============================================================================
// Main
// =============================================================================

void vertex() {
	local_normal = NORMAL;
}

void fragment() {
	vec3 n = normalize(local_normal);

	// Animated cloud noise — sample at sphere surface position
	float t = TIME * cloud_speed;
	vec3 sample_pos = n * 3.5 + vec3(t * 0.7, t * 0.3, -t * 0.5);
	float cloud = fbm(sample_pos);

	// Domain warp for more organic shapes
	vec3 warp = vec3(
		snoise(sample_pos + vec3(5.2, 1.3, 2.8)),
		snoise(sample_pos + vec3(1.7, 9.2, 3.4)),
		snoise(sample_pos + vec3(8.3, 2.8, 4.7))
	) * 0.4;
	cloud = fbm(sample_pos + warp);

	// Coverage threshold: convert noise to cloud mask
	float threshold = 1.0 - cloud_coverage;
	float alpha = smoothstep(threshold - 0.05, threshold + 0.15, cloud * 0.5 + 0.5);

	// Soft edges
	alpha *= smoothstep(0.0, 0.08, alpha);
	alpha *= cloud_density;

	// Sun lighting on clouds
	vec3 world_n = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	vec3 sun_dir = normalize(sun_direction);
	float ndotl = dot(world_n, sun_dir);

	// Bright on sun side, darker on shadow side
	float sun_lit = smoothstep(-0.3, 0.5, ndotl);
	vec3 lit_color = mix(cloud_shadow_color.rgb, cloud_color.rgb, sun_lit);

	// Silver lining effect at cloud edges facing sun
	float edge_glow = (1.0 - alpha) * smoothstep(0.0, 0.3, alpha) * sun_lit * 0.4;
	lit_color += vec3(edge_glow);

	ALBEDO = lit_color;
	ALPHA = clamp(alpha * 0.85, 0.0, 0.8); // Never fully opaque
}
