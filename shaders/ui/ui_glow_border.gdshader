shader_type canvas_item;

// Pulsating energy border for active/selected panels
// Applied as material on highlighted UIComponents

uniform vec4 glow_color : source_color = vec4(0.0, 0.85, 1.0, 0.8);
uniform float border_width : hint_range(0.005, 0.1) = 0.02;
uniform float pulse_speed : hint_range(0.0, 8.0) = 2.0;
uniform float pulse_min : hint_range(0.0, 1.0) = 0.3;
uniform float glow_falloff : hint_range(0.01, 0.2) = 0.06;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Distance from nearest edge
	float dx = min(UV.x, 1.0 - UV.x);
	float dy = min(UV.y, 1.0 - UV.y);
	float d = min(dx, dy);

	// Border glow with falloff
	float glow = smoothstep(border_width + glow_falloff, border_width, d);

	// Pulse animation
	float pulse = mix(pulse_min, 1.0, (sin(TIME * pulse_speed * 6.28318) + 1.0) * 0.5);

	// Apply glow
	tex.rgb += glow_color.rgb * glow * pulse * glow_color.a;

	COLOR = tex;
}
