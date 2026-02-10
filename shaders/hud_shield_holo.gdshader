shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Shield health per facing: x=FRONT, y=REAR, z=LEFT, w=RIGHT (0.0 to 1.0)
uniform vec4 shield_ratios = vec4(1.0, 1.0, 1.0, 1.0);
// Which facing was just hit (-1 = none, 0=front, 1=rear, 2=left, 3=right)
uniform int hit_facing = -1;
uniform float hit_time = 1.0;
uniform float pulse_time = 0.0;
// Half-extents of the shield ellipsoid (used for angular normalization)
uniform vec3 shield_scale = vec3(1.0);

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	// Normalize by shield scale so angular math works on ellipsoid
	vec3 n = normalize(obj_pos / shield_scale);

	// Determine facing: FRONT(0)=-Z, REAR(1)=+Z, LEFT(2)=-X, RIGHT(3)=+X
	int facing;
	float ratio;
	if (abs(n.z) >= abs(n.x)) {
		if (n.z < 0.0) {
			facing = 0;
			ratio = shield_ratios.x;
		} else {
			facing = 1;
			ratio = shield_ratios.y;
		}
	} else {
		if (n.x < 0.0) {
			facing = 2;
			ratio = shield_ratios.z;
		} else {
			facing = 3;
			ratio = shield_ratios.w;
		}
	}

	// Fresnel edge glow — visible at shield boundaries
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.8);
	float base_alpha = fresnel * ratio * 0.25;

	// Subtle per-quadrant pulse
	float pulse = sin(pulse_time * 1.8 + float(facing) * 1.57) * 0.015 + 0.015;
	base_alpha += pulse * ratio;

	// Color gradient: healthy (cyan-blue) -> damaged (orange-red)
	vec3 col = mix(vec3(0.9, 0.35, 0.08), vec3(0.1, 0.5, 0.9), clamp(ratio, 0.0, 1.0));

	// Hit flash effect on the struck facing
	float flash = 0.0;
	if (facing == hit_facing && hit_time < 0.6) {
		float hit_fade = max(0.0, 1.0 - hit_time * 2.0);

		// Direction to the center of this facing
		vec3 face_dir;
		if (facing == 0) {
			face_dir = vec3(0.0, 0.0, -1.0);
		} else if (facing == 1) {
			face_dir = vec3(0.0, 0.0, 1.0);
		} else if (facing == 2) {
			face_dir = vec3(-1.0, 0.0, 0.0);
		} else {
			face_dir = vec3(1.0, 0.0, 0.0);
		}

		float dist = acos(clamp(dot(n, face_dir), -1.0, 1.0));

		// Expanding ripple ring
		float ripple_pos = hit_time * 3.0;
		float ripple = smoothstep(0.06, 0.0, abs(dist - ripple_pos)) * hit_fade;

		// Central impact glow
		float glow = exp(-dist * dist * 6.0) * hit_fade;

		flash = glow * 0.5 + ripple * 0.4;
		// White-blue flash at impact center
		col = mix(col, vec3(0.5, 0.7, 1.0), glow * 0.6);
	}

	float alpha = base_alpha + flash;
	if (alpha < 0.003) {
		discard;
	}

	ALBEDO = col;
	EMISSION = col * (0.3 + flash * 2.5);
	ALPHA = clamp(alpha, 0.0, 0.45);
}
