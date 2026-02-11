shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

// =============================================================================
// Star Corona — Additive glow halo around the star
// Placed on a sphere ~1.3x the star radius. Inverse fresnel = bright at edges.
// Animated noise gives corona shimmer.
// =============================================================================

uniform vec4 corona_color : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float corona_intensity : hint_range(0.0, 5.0) = 1.5;
uniform float corona_falloff : hint_range(0.5, 8.0) = 2.5;
uniform float animation_speed : hint_range(0.0, 2.0) = 0.2;

varying vec3 world_pos;
varying vec3 world_normal;

// =============================================================================
// Noise
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

// =============================================================================

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float ndotv = abs(dot(world_normal, view_dir));

	// Inverse fresnel: bright at edges (corona glow)
	float rim = 1.0 - ndotv;
	float corona = pow(abs(rim), corona_falloff) * corona_intensity;

	// Animated noise for shimmer
	float t = TIME * animation_speed;
	vec3 n = normalize(world_normal);
	float shimmer = noise3d(n * 4.0 + vec3(t * 0.3, t * -0.2, t * 0.1));
	shimmer = shimmer * 0.4 + 0.6; // Modulate 60-100%

	// Streaky corona rays using latitude-biased noise
	float rays = noise3d(n * vec3(2.0, 8.0, 2.0) + vec3(t * 0.1, 0.0, t * -0.05));
	rays = smoothstep(0.3, 0.7, rays);

	float final_corona = corona * shimmer * (0.7 + rays * 0.3);

	ALBEDO = corona_color.rgb * final_corona;
	ALPHA = clamp(final_corona, 0.0, 1.0);
}
