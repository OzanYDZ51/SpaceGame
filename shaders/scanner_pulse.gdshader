shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never;

uniform vec4  pulse_color : source_color = vec4(0.2, 0.82, 1.0, 1.0);
uniform float brightness  : hint_range(0.0, 10.0) = 5.0;
uniform float rim_power   : hint_range(1.0, 10.0) = 5.0;
uniform float fade        : hint_range(0.0,  1.0) = 1.0;

void fragment() {
	float rim    = pow(1.0 - dot(NORMAL, VIEW), rim_power);
	float ripple = 0.88 + sin(TIME * 10.0) * 0.12;
	ALBEDO = pulse_color.rgb * brightness * ripple * fade;
	ALPHA  = clamp(rim * fade, 0.0, 1.0);
}
