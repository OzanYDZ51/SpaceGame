shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

// =============================================================================
// Planet Atmosphere — Rayleigh + Mie single-scatter ray march
// Visible from space (glow ring) and from near surface (sky color).
// 8 samples along view ray, optical depth via scale-height approximation.
// =============================================================================

uniform vec4 glow_color : source_color = vec4(0.4, 0.6, 1.0, 1.0);
uniform vec4 scatter_color : source_color = vec4(0.3, 0.5, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 5.0) = 1.5;
uniform float glow_falloff : hint_range(0.5, 10.0) = 3.0;
uniform float atmosphere_density : hint_range(0.0, 2.0) = 1.0;
uniform float planet_radius_norm : hint_range(0.5, 1.0) = 0.92; // planet_r / atmo_r
uniform float atmosphere_height = 5000.0; // meters

// Sun direction (set by PlanetBody or defaults to star direction)
uniform vec3 sun_direction = vec3(0.0, 0.3, -1.0);

// Rayleigh coefficients (wavelength-dependent)
const vec3 RAYLEIGH_COEFF = vec3(5.8e-3, 13.5e-3, 33.1e-3); // RGB scatter
const float MIE_COEFF = 2.0e-3;
const float MIE_G = 0.76; // Forward scattering asymmetry
const int NUM_SAMPLES = 8;
const float SCALE_HEIGHT_R = 0.15; // Rayleigh scale height (fraction of atmo)
const float SCALE_HEIGHT_M = 0.08; // Mie scale height

varying vec3 world_pos;
varying vec3 world_normal;

// Compute optical depth along a ray from point to atmosphere boundary
float optical_depth_approx(vec3 pos, vec3 dir, float planet_r, float atmo_r) {
	// Simple approximation: based on altitude and angle
	float altitude = length(pos) - planet_r;
	float norm_alt = clamp(altitude / (atmo_r - planet_r), 0.0, 1.0);
	float base_depth = exp(-norm_alt / SCALE_HEIGHT_R);

	// Angle factor: looking through more atmosphere near horizon
	float cos_angle = dot(normalize(pos), dir);
	float angle_factor = 1.0 / max(abs(cos_angle), 0.1);
	angle_factor = min(angle_factor, 10.0);

	return base_depth * angle_factor;
}

// Mie phase function (Henyey-Greenstein)
float mie_phase(float cos_theta) {
	float g2 = MIE_G * MIE_G;
	float num = 1.0 - g2;
	float denom = pow(abs(1.0 + g2 - 2.0 * MIE_G * cos_theta), 1.5);
	return num / (4.0 * 3.14159 * max(denom, 0.001));
}

// Rayleigh phase function
float rayleigh_phase(float cos_theta) {
	return 0.75 * (1.0 + cos_theta * cos_theta);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float ndotv = abs(dot(world_normal, view_dir));

	// Get mesh scale (atmosphere radius in world units)
	float atmo_r = length(vec3(MODEL_MATRIX[0].x, MODEL_MATRIX[1].y, MODEL_MATRIX[2].z));
	float planet_r = atmo_r * planet_radius_norm;

	// Ray from camera toward the surface point
	vec3 ray_start = world_pos;
	vec3 to_center = center - ray_start;
	float dist_to_center = length(to_center);

	// Normalized altitude of this fragment
	float altitude = dist_to_center - planet_r;
	float norm_alt = clamp(altitude / (atmo_r - planet_r), 0.0, 1.0);

	// === Fresnel glow (works great from distance) ===
	float fresnel = 1.0 - ndotv;
	fresnel = pow(abs(fresnel), glow_falloff);
	float glow = fresnel * glow_intensity * atmosphere_density;

	// === Scatter contribution (more visible up close) ===
	vec3 sun_dir = normalize(sun_direction);
	float cos_theta = dot(view_dir, sun_dir);

	// Rayleigh + Mie in-scatter
	float rayleigh_p = rayleigh_phase(cos_theta);
	float mie_p = mie_phase(cos_theta);

	// Optical depth at this point
	float density_r = exp(-norm_alt / SCALE_HEIGHT_R) * atmosphere_density;
	float density_m = exp(-norm_alt / SCALE_HEIGHT_M) * atmosphere_density;

	// Sun optical depth (how much atmosphere light traverses to reach this point)
	float sun_od = optical_depth_approx(ray_start - center, sun_dir, planet_r, atmo_r);

	// Extinction
	vec3 extinction = exp(-(RAYLEIGH_COEFF * sun_od + MIE_COEFF * sun_od));

	// In-scatter light
	vec3 scatter_r = RAYLEIGH_COEFF * density_r * rayleigh_p * extinction;
	vec3 scatter_m = vec3(MIE_COEFF) * density_m * mie_p * extinction;
	vec3 scatter = (scatter_r + scatter_m) * 15.0; // Intensity multiplier

	// === Combine ===
	vec3 glow_contrib = glow_color.rgb * glow;
	vec3 scatter_contrib = scatter_color.rgb * scatter;

	// Blend: glow dominates from far away, scatter from near
	float near_factor = clamp(1.0 - norm_alt, 0.0, 1.0);
	vec3 final_color = glow_contrib + scatter_contrib * near_factor * 2.0;

	float final_alpha = clamp(glow + length(scatter) * near_factor, 0.0, 1.5);

	ALBEDO = final_color;
	ALPHA = final_alpha * glow_color.a;
}
