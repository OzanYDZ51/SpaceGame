shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

// =============================================================================
// Planet Atmosphere — Ray-based limb glow
// Instead of fresnel on the atmosphere mesh (creates hard edge), we compute
// how close the view ray passes to the PLANET surface. Glow peaks at the
// planet limb and decays smoothly outward — no visible mesh boundary.
// =============================================================================

uniform vec4 glow_color : source_color = vec4(0.4, 0.6, 1.0, 1.0);
uniform vec4 scatter_color : source_color = vec4(0.3, 0.5, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 5.0) = 1.5;
uniform float glow_falloff : hint_range(0.5, 10.0) = 3.0;
uniform float atmosphere_density : hint_range(0.0, 2.0) = 1.0;
uniform float planet_radius_norm : hint_range(0.5, 1.0) = 0.92;
uniform float atmosphere_height = 5000.0;

uniform vec3 sun_direction = vec3(0.0, 0.3, -1.0);

// Mie phase function
const float MIE_G = 0.76;

varying vec3 world_pos;
varying vec3 world_normal;

float mie_phase(float cos_theta) {
	float g2 = MIE_G * MIE_G;
	float num = 1.0 - g2;
	float denom = pow(abs(1.0 + g2 - 2.0 * MIE_G * cos_theta), 1.5);
	return num / (4.0 * 3.14159 * max(denom, 0.001));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 cam_pos = CAMERA_POSITION_WORLD;
	vec3 view_dir = normalize(cam_pos - world_pos);

	// Atmosphere and planet radii in world units
	float atmo_r = length(vec3(MODEL_MATRIX[0].x, MODEL_MATRIX[1].y, MODEL_MATRIX[2].z));
	float planet_r = atmo_r * planet_radius_norm;
	float shell_thickness = atmo_r - planet_r;

	// === Ray closest approach to planet center ===
	// Ray: from camera through this fragment toward the scene
	vec3 ray_dir = -view_dir; // from camera into scene
	vec3 oc = center - cam_pos;
	float b = dot(oc, ray_dir);
	float closest_dist_sq = dot(oc, oc) - b * b;
	float closest_dist = sqrt(max(closest_dist_sq, 0.0));

	// How far above the planet surface does the ray pass?
	// 0 = ray grazes planet surface (limb), grows outward
	float above_surface = max(closest_dist - planet_r, 0.0);
	float t = clamp(above_surface / shell_thickness, 0.0, 1.0); // 0=limb, 1=atmo edge

	// === Ring glow profile: peaks at planet limb, decays outward ===
	// Steeper falloff = thinner ring
	float ring = exp(-t * t * glow_falloff * glow_falloff);

	// For rays that HIT the planet (closest_dist < planet_r):
	// Show a very subtle tint (looking through atmosphere at the planet face)
	float hits_planet = step(closest_dist, planet_r);
	float depth_into_planet = (planet_r - closest_dist) / planet_r;
	float front_tint = hits_planet * (1.0 - depth_into_planet) * 0.04 * atmosphere_density;

	// === Sun modulation ===
	vec3 sun_dir = normalize(sun_direction);
	vec3 frag_dir = normalize(world_pos - center);
	float sun_facing = dot(frag_dir, sun_dir);
	// Bright crescent on sun side, dim on dark side
	float sun_mod = smoothstep(-0.5, 0.4, sun_facing) * 0.85 + 0.15;

	// === Forward scattering (Mie) for bright halo when looking toward sun ===
	float cos_theta = dot(-view_dir, sun_dir);
	float mie = mie_phase(cos_theta);
	float scatter_boost = mie * 0.15 * atmosphere_density;

	// === Final glow ===
	float total_glow = (ring * glow_intensity * atmosphere_density * sun_mod + front_tint + scatter_boost * ring);

	// Color: glow_color for the ring, scatter_color for forward scatter
	vec3 ring_contrib = glow_color.rgb * ring * glow_intensity * atmosphere_density * sun_mod;
	vec3 scatter_contrib = scatter_color.rgb * scatter_boost * ring;
	vec3 tint_contrib = glow_color.rgb * front_tint;

	vec3 final_color = ring_contrib + scatter_contrib + tint_contrib;
	float final_alpha = clamp(total_glow * 0.5, 0.0, 0.5);

	ALBEDO = final_color;
	ALPHA = final_alpha * glow_color.a;
}
