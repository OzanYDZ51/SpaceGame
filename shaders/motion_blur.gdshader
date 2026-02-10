shader_type spatial;
render_mode depth_test_disabled, depth_draw_never, unshaded, cull_disabled;

// =============================================================================
// Motion Blur — Screen-space camera-velocity blur (ported from Bauxitedev)
// Applied on a fullscreen quad child of the Camera3D.
// Reconstructs world position from depth, computes per-pixel velocity from
// camera linear + angular velocity (rigid body formula), then samples along
// the motion vector.
// =============================================================================

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform vec3 linear_velocity = vec3(0.0);
uniform vec3 angular_velocity = vec3(0.0);
uniform int iteration_count : hint_range(2, 50) = 15;
uniform float intensity : hint_range(0.0, 3.0) = 0.5;
uniform float start_radius : hint_range(0.0, 200.0) = 0.5;

void vertex() {
	// Fullscreen quad: map VERTEX.xy [-1,1] directly to clip space
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	// Skip if no camera movement
	if (length(linear_velocity) + length(angular_velocity) < 0.0001) {
		ALBEDO = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
		ALPHA = 1.0;
	} else {
		// Read depth and reconstruct camera-space position
		float depth = texture(depth_tex, SCREEN_UV).x;
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
		vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		vec3 pixel_pos_cam = view_pos.xyz / view_pos.w;

		// Camera-space → world-space
		vec3 pixel_pos_world = (INV_VIEW_MATRIX * vec4(pixel_pos_cam, 1.0)).xyz;

		// Camera world position
		vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;

		// Vector from camera to this pixel in world space
		vec3 r = pixel_pos_world - cam_pos;

		// Per-pixel velocity: v_linear + omega × r (rigid body formula)
		vec3 total_velocity = linear_velocity + cross(angular_velocity, r);

		// Project the "previous frame" position back to screen space
		vec3 prev_world = pixel_pos_world - total_velocity;
		vec3 prev_cam = (VIEW_MATRIX * vec4(prev_world, 1.0)).xyz;
		vec4 prev_clip = PROJECTION_MATRIX * vec4(prev_cam, 1.0);
		vec3 prev_ndc = prev_clip.xyz / prev_clip.w;

		// Screen-space motion vector
		vec2 motion = prev_ndc.xy - ndc.xy;

		// Blur along motion vector (skip pixels too close to camera)
		vec3 col = vec3(0.0);
		int counter = 0;

		if (length(r) >= start_radius) {
			for (int i = 0; i < iteration_count; i++) {
				vec2 offset = motion * (float(i) / float(iteration_count) - 0.5) * intensity;
				col += textureLod(screen_tex, SCREEN_UV + offset, 0.0).rgb;
				counter++;
			}
			ALBEDO = col / float(counter);
		} else {
			ALBEDO = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
		}

		ALPHA = 1.0;
	}
}
