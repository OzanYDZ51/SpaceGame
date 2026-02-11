shader_type canvas_item;

// =============================================================================
// Quantum Travel VFX - Star Citizen style post-processing
// Radial scene stretch (stars become lines) + blue quantum vignette
// No fake animated streaks. The actual scene content stretches naturally.
//
// Two intensity drivers:
//   flight_ratio  = speed / boost_max  → subtle blur during normal/boost flight
//   cruise_spool  = cruise_time / spool_duration  → 0→1 over 10s, main quantum effect
//   cruise_warp   = phase 2 warp active → full quantum intensity
// =============================================================================

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float flight_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float cruise_spool : hint_range(0.0, 1.0) = 0.0;
uniform float damage_flash : hint_range(0.0, 1.0) = 0.0;
uniform float cruise_warp : hint_range(0.0, 1.0) = 0.0;
uniform float quantum_engage : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 center = SCREEN_UV - 0.5;
	float dist = length(center);

	// Intensity curves
	float flight_sq = flight_ratio * flight_ratio;    // Normal/boost: 0→1
	float spool_sq = cruise_spool * cruise_spool;     // Cruise spool: quadratic ramp

	// === DAMAGE ZOOM DISTORTION ===
	float dmg = damage_flash * damage_flash;
	vec2 uv = SCREEN_UV + center * dmg * 0.06;

	// === RADIAL STRETCH — core quantum travel effect ===
	// flight_sq gives subtle blur during boost
	// spool_sq drives the spool-up phase (visible immediately when you press C)
	// cruise_warp adds the final warp intensity
	float stretch = flight_sq * 0.004 + spool_sq * 0.025 + cruise_warp * 0.04 + quantum_engage * 0.02;
	float stretch_mask = smoothstep(0.05, 0.55, dist);
	vec2 stretch_dir = normalize(center + vec2(0.0001)) * stretch_mask * stretch;

	// 8-tap radial blur along stretch direction
	vec3 col = vec3(0.0);
	col += texture(screen_texture, uv).rgb                       * 0.22;
	col += texture(screen_texture, uv - stretch_dir * 0.14).rgb  * 0.18;
	col += texture(screen_texture, uv - stretch_dir * 0.29).rgb  * 0.16;
	col += texture(screen_texture, uv - stretch_dir * 0.43).rgb  * 0.13;
	col += texture(screen_texture, uv - stretch_dir * 0.57).rgb  * 0.10;
	col += texture(screen_texture, uv - stretch_dir * 0.71).rgb  * 0.08;
	col += texture(screen_texture, uv - stretch_dir * 0.86).rgb  * 0.07;
	col += texture(screen_texture, uv - stretch_dir * 1.0).rgb   * 0.06;

	// === CHROMATIC ABERRATION (subtle, edge-weighted) ===
	float ab_strength = flight_sq * 0.001 + spool_sq * 0.002 + cruise_warp * 0.003;
	float ab = ab_strength * dist;
	vec2 ab_dir = normalize(center + vec2(0.0001)) * ab;
	if (ab_strength > 0.0003) {
		col.r = mix(col.r, texture(screen_texture, uv + ab_dir).r, 0.7);
		col.b = mix(col.b, texture(screen_texture, uv - ab_dir).b, 0.7);
	}

	// === QUANTUM VIGNETTE (blue-tinted darkening at edges) ===
	// Builds during spool, full during warp
	float quantum_intensity = spool_sq + cruise_warp;
	float vig_strength = flight_sq * 0.06 + quantum_intensity * 0.18;
	float vig_mask = smoothstep(0.35, 0.9, dist);
	col *= 1.0 - vig_mask * vig_strength;

	// Blue tint at edges (cruise only)
	if (quantum_intensity > 0.01) {
		vec3 blue_tint = vec3(0.06, 0.1, 0.22) * vig_mask * quantum_intensity * 0.25;
		col += blue_tint;
	}

	// === QUANTUM EDGE GLOW (subtle blue luminance at screen borders) ===
	float edge_glow = smoothstep(0.6, 0.95, dist) * cruise_warp * 0.1;
	col += vec3(0.15, 0.3, 0.7) * edge_glow;

	// === ENGAGE PULSE (brief bright surge when quantum activates) ===
	if (quantum_engage > 0.01) {
		float pulse_ring = smoothstep(0.1, 0.3, dist) * smoothstep(0.6, 0.3, dist);
		col += vec3(0.3, 0.5, 0.9) * pulse_ring * quantum_engage * 0.2;
	}

	// === DAMAGE CHROMATIC ABERRATION + RED VIGNETTE ===
	if (dmg > 0.01) {
		float dmg_ab = dmg * 0.012 * (0.5 + dist);
		vec2 dmg_ab_dir = normalize(center + vec2(0.0001)) * dmg_ab;
		col.r = texture(screen_texture, uv + dmg_ab_dir).r;
		col.b = texture(screen_texture, uv - dmg_ab_dir).b;
	}
	float dmg_vig = smoothstep(0.15, 0.65, dist) * dmg * 0.45;
	col += vec3(0.5, 0.02, 0.01) * dmg_vig;

	// === COLOR GRADE (subtle blue shift during quantum) ===
	vec3 grade = mix(vec3(1.0), vec3(0.95, 0.96, 1.05), quantum_intensity * 0.25);
	col *= grade;

	COLOR = vec4(col, 1.0);
}
