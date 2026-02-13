shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// =============================================================================
// Engine Exhaust Core — Thick volumetric plume shader (Star Citizen style)
// Applied to a CylinderMesh — nearly cylindrical, NOT a thin cone.
// Produces a fat, solid-looking plasma plume with HDR bloom.
// =============================================================================

uniform vec3 color_core : source_color = vec3(0.85, 0.92, 1.0);
uniform vec3 color_mid : source_color = vec3(0.3, 0.6, 1.0);
uniform vec3 color_tip : source_color = vec3(0.15, 0.35, 0.9);
uniform float intensity : hint_range(0.0, 30.0) = 10.0;
uniform float throttle : hint_range(0.0, 2.0) = 1.0;
uniform float flame_length : hint_range(0.5, 6.0) = 1.0;
uniform float flicker_speed : hint_range(0.0, 20.0) = 8.0;
uniform float flicker_strength : hint_range(0.0, 1.0) = 0.35;
uniform float pulse_speed : hint_range(0.0, 5.0) = 2.5;
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.15;
uniform float boost_glow : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p, float t) {
	float val = 0.0;
	float amp = 0.5;
	vec2 shift = vec2(t * 0.7, t * 0.3);
	for (int i = 0; i < 4; i++) {
		val += amp * noise(p + shift);
		p *= 2.1;
		shift *= 1.3;
		amp *= 0.5;
	}
	return val;
}

void vertex() {
	// Breathing pulse
	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount * throttle;
	// Boost swells the nozzle area
	float nozzle_prox = 1.0 - clamp(abs(VERTEX.z) / max(flame_length * 3.0, 0.1), 0.0, 1.0);
	float boost_swell = 1.0 + boost_glow * nozzle_prox * 0.5;
	VERTEX.xy *= pulse * boost_swell;
	VERTEX.z *= flame_length;
}

void fragment() {
	float z_pos = UV.y;
	float radial = abs(UV.x - 0.5) * 2.0;

	// Z-gradient: very bright at nozzle, fades aggressively toward tip
	float z_fade = pow(max(1.0 - smoothstep(0.0, 0.9, z_pos), 0.0), 1.2);
	float z_core = pow(max(1.0 - z_pos, 0.0), 2.2);

	// Radial: bright fat center near nozzle, tighter at tip
	// Radial tolerance shrinks along Z = natural taper in the shader too
	float radial_width = mix(1.0, 0.4, z_pos);  // Nozzle=full width, tip=40%
	float r_norm = radial / radial_width;
	float r_fade = 1.0 - smoothstep(0.0, 1.0, r_norm);
	float r_core = pow(max(1.0 - r_norm, 0.0), 2.5);

	// Turbulence noise — breaks the silhouette, creates flame-like wisps
	float flicker_t = TIME * flicker_speed;
	float n1 = fbm(vec2(z_pos * 4.0, radial * 2.0), flicker_t);
	float n2 = fbm(vec2(z_pos * 8.0 + 5.0, radial * 4.0 + 3.0), flicker_t * 1.5);
	// Large-scale wisps that carve holes in the flame
	float n3 = fbm(vec2(z_pos * 2.0 + 10.0, radial * 1.0), flicker_t * 0.7);
	float flicker = mix(1.0, n1 * 0.6 + n2 * 0.2 + n3 * 0.2, flicker_strength);
	// Noise-driven alpha cutout — erodes edges, creates wispy tongues
	float edge_erode = smoothstep(0.3, 0.7, n1 * 0.5 + n3 * 0.5);
	float alpha_noise = mix(1.0, edge_erode, flicker_strength * (0.5 + z_pos * 0.5));

	// Color temperature
	vec3 col;
	if (z_pos < 0.1) {
		col = mix(color_core, color_mid, z_pos / 0.1);
	} else if (z_pos < 0.5) {
		col = mix(color_mid, mix(color_mid, color_tip, 0.5), (z_pos - 0.1) / 0.4);
	} else {
		col = mix(mix(color_mid, color_tip, 0.5), color_tip, (z_pos - 0.5) / 0.5);
	}

	// Hot nozzle ring
	float nozzle_ring = pow(max(1.0 - z_pos * 6.0, 0.0), 2.5) * r_fade;
	float ring_boost = nozzle_ring * (1.0 + boost_glow * 3.0);

	float alpha = z_fade * r_fade * flicker * alpha_noise * throttle;
	float core_boost = z_core * r_core * 2.0;

	float final_intensity = intensity * throttle;
	vec3 emission = col * (alpha + core_boost + ring_boost) * final_intensity;

	// White-hot punch at nozzle during boost
	emission += vec3(1.0, 0.95, 0.9) * ring_boost * boost_glow * intensity * 0.4;

	ALBEDO = emission;
	ALPHA = clamp((alpha + ring_boost * 0.3) * throttle, 0.0, 1.0);
}
