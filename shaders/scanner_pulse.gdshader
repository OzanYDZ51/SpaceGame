shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never;

uniform vec4 pulse_color : source_color = vec4(0.3, 0.75, 1.0, 1.0);
uniform float brightness : hint_range(0.0, 20.0) = 8.0;
uniform float rim_power  : hint_range(0.5, 8.0)  = 3.5;
uniform float fade       : hint_range(0.0, 1.0)  = 1.0;

void fragment() {
	float rim    = pow(1.0 - dot(NORMAL, VIEW), rim_power);
	float ripple = 0.80 + sin(TIME * 12.0) * 0.20;
	ALBEDO = pulse_color.rgb * brightness * ripple * fade;
	ALPHA  = clamp(rim * fade, 0.0, 1.0);
}
