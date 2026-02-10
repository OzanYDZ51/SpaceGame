shader_type canvas_item;

// =============================================================================
// Speed VFX - Cinematic post-processing for space flight
// Radial motion blur + animated speed streaks + vignette + aberration + flashes
// =============================================================================

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float speed_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float boost_flash : hint_range(0.0, 1.0) = 0.0;
uniform float damage_flash : hint_range(0.0, 1.0) = 0.0;
uniform float cruise_warp : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center = uv - 0.5;
	float dist = length(center);
	float angle = atan(center.y, center.x);
	float sq = speed_ratio * speed_ratio;

	// === RADIAL MOTION BLUR (5-tap, edges only) ===
	float blur_str = sq * 0.018;
	vec2 blur_dir = center * blur_str;
	vec3 col = vec3(0.0);
	col += texture(screen_texture, uv).rgb                    * 0.34;
	col += texture(screen_texture, uv - blur_dir * 0.3).rgb   * 0.24;
	col += texture(screen_texture, uv - blur_dir * 0.65).rgb  * 0.18;
	col += texture(screen_texture, uv - blur_dir * 1.0).rgb   * 0.14;
	col += texture(screen_texture, uv + blur_dir * 0.25).rgb  * 0.10;

	// === ANIMATED SPEED STREAKS ===
	float num_lines = 80.0;
	float line_id = floor(angle * num_lines / TAU);
	float line_frac = fract(angle * num_lines / TAU);

	// Per-line random seed
	float seed = fract(sin(line_id * 78.233 + 12.9898) * 43758.5453);
	float seed2 = fract(sin(line_id * 127.1 + 311.7) * 43758.5453);

	// Animated outward pulse (each line pulses at its own phase)
	float anim_speed = 0.6 + seed * 0.8;
	float anim = fract(TIME * anim_speed + seed * 6.28);
	float pulse = smoothstep(0.0, 0.25, anim) * smoothstep(1.0, 0.55, anim);

	// Line shape: soft thin streak
	float line_w = 0.04 + seed2 * 0.04;
	float line = smoothstep(0.0, line_w, line_frac) * smoothstep(line_w * 2.5, line_w, line_frac);

	// Radial fade (nothing at center, strong at edges)
	float inner_r = 0.08 + seed * 0.15;
	float radial = smoothstep(inner_r, 0.52, dist);

	// Brightness variation per line
	float bright = 0.4 + seed2 * 0.6;

	// Color: warm white at center → cool blue at edges
	vec3 line_tint = mix(vec3(0.8, 0.9, 1.0), vec3(0.3, 0.55, 1.0), clamp(dist * 2.2, 0.0, 1.0));
	vec3 streak_col = line_tint * line * radial * pulse * bright * sq * 0.6;

	// Second layer: thinner, faster, brighter lines (fewer)
	float line_id2 = floor(angle * 30.0 / TAU);
	float line_frac2 = fract(angle * 30.0 / TAU);
	float seed3 = fract(sin(line_id2 * 45.17) * 43758.5453);
	float anim2 = fract(TIME * 1.2 + seed3 * 6.28);
	float pulse2 = smoothstep(0.0, 0.15, anim2) * smoothstep(1.0, 0.4, anim2);
	float line2 = smoothstep(0.0, 0.02, line_frac2) * smoothstep(0.06, 0.02, line_frac2);
	float radial2 = smoothstep(0.2, 0.55, dist);
	vec3 streak2 = vec3(0.6, 0.8, 1.0) * line2 * radial2 * pulse2 * sq * 0.4;

	// === VIGNETTE (closes in at higher speed) ===
	float vig_inner = mix(0.4, 0.2, speed_ratio);
	float vig = smoothstep(vig_inner, 0.82, dist) * speed_ratio * 0.55;

	// === CHROMATIC ABERRATION (distance-scaled) ===
	float ab = sq * 0.003 * dist;
	vec2 ab_dir = normalize(center + vec2(0.001)) * ab;
	float r_ch = texture(screen_texture, uv + ab_dir).r;
	float b_ch = texture(screen_texture, uv - ab_dir).b;
	col = mix(col, vec3(r_ch, col.g, b_ch), step(0.15, speed_ratio));

	// === BOOST FLASH (intense white burst) ===
	float flash = boost_flash * boost_flash * max(0.0, 1.0 - dist * 1.6);

	// === DAMAGE FLASH (red pulse) ===
	float dmg_pulse = damage_flash * (0.85 + 0.15 * sin(TIME * 15.0));
	vec3 dmg_col = vec3(0.35, 0.03, 0.02) * dmg_pulse;

	// === COLOR GRADE (subtle blue shift at high speed) ===
	vec3 grade = mix(vec3(1.0), vec3(0.92, 0.95, 1.08), sq * 0.4);

	// === CRUISE WARP TUNNEL (phase 2 — intense radial streaks + blur) ===
	float warp_streaks = 0.0;
	if (cruise_warp > 0.01) {
		// Intensified radial lines converging to center
		float warp_lines = 120.0;
		float wl_id = floor(angle * warp_lines / TAU);
		float wl_frac = fract(angle * warp_lines / TAU);
		float ws = fract(sin(wl_id * 91.3 + 7.7) * 43758.5453);
		float wa = fract(TIME * (1.0 + ws * 0.6) + ws * 6.28);
		float wp = smoothstep(0.0, 0.1, wa) * smoothstep(1.0, 0.3, wa);
		float wl = smoothstep(0.0, 0.015, wl_frac) * smoothstep(0.05, 0.015, wl_frac);
		float wr = smoothstep(0.05, 0.6, dist);
		warp_streaks = wl * wr * wp * cruise_warp * 1.2;
	}
	vec3 warp_col = mix(vec3(0.5, 0.7, 1.0), vec3(0.2, 0.4, 1.0), dist * 2.0) * warp_streaks;

	// Extra warp vignette (tight tunnel)
	float warp_vig = smoothstep(0.15, 0.75, dist) * cruise_warp * 0.4;

	// Extra radial blur for warp
	if (cruise_warp > 0.01) {
		float warp_blur = cruise_warp * 0.03;
		vec2 wb_dir = center * warp_blur;
		col = col * 0.5
			+ texture(screen_texture, uv - wb_dir * 0.5).rgb * 0.25
			+ texture(screen_texture, uv - wb_dir * 1.0).rgb * 0.25;
	}

	// === COMBINE ===
	vec3 result = col * grade;
	result += streak_col + streak2 + warp_col;
	result *= 1.0 - vig - warp_vig;
	result += vec3(flash);
	result += dmg_col;

	COLOR = vec4(result, 1.0);
}
