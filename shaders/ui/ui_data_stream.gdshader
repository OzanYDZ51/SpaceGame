shader_type canvas_item;

// Decorative falling data columns (Matrix / holographic console style)
// Apply on a ColorRect for background decoration

render_mode unshaded;

uniform vec4 stream_color : source_color = vec4(0.0, 0.85, 1.0, 0.15);
uniform float speed : hint_range(0.1, 4.0) = 1.0;
uniform float density : hint_range(2.0, 30.0) = 12.0;
uniform float fade_length : hint_range(0.05, 0.5) = 0.2;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float col_id = floor(UV.x * density);
	float col_offset = hash(col_id * 17.3);
	float col_speed = 0.5 + hash(col_id * 31.7) * 0.8;

	// Scrolling Y position per column
	float scroll_y = fract(UV.y + TIME * speed * col_speed + col_offset);

	// Fade trail
	float trail = smoothstep(0.0, fade_length, scroll_y) * smoothstep(1.0, 1.0 - fade_length * 2.0, scroll_y);

	// Character blocks (simulated)
	float char_y = floor(scroll_y * 30.0);
	float char_vis = step(0.4, hash2(vec2(col_id, char_y + floor(TIME * 4.0))));

	// Column visibility (not all columns active)
	float col_vis = step(0.35, hash(col_id * 7.1 + floor(TIME * 0.3)));

	float alpha = trail * char_vis * col_vis * stream_color.a;
	COLOR = vec4(stream_color.rgb, alpha);
}
