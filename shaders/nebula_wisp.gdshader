shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 wisp_color : source_color = vec4(0.1, 0.04, 0.15, 0.02);
uniform float softness : hint_range(0.0, 10.0) = 3.0;
uniform sampler2D depth_texture : hint_depth_texture;

void vertex() {
    // Billboard - always face camera
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
        vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
        vec4(vec3(0.0, 1.0, 0.0), 0.0),
        vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0),
        MODEL_MATRIX[3]
    );
    MODELVIEW_MATRIX[0] *= length(MODEL_MATRIX[0]);
    MODELVIEW_MATRIX[1] *= length(MODEL_MATRIX[1]);
    MODELVIEW_MATRIX[2] *= length(MODEL_MATRIX[2]);
}

void fragment() {
    vec2 center_uv = UV - vec2(0.5);
    float dist = length(center_uv);

    // Simple soft radial falloff - bright center fading to transparent edges
    // Using a cubic falloff for very soft edges (no hard ring artifacts)
    float shape = 1.0 - smoothstep(0.0, 0.5, dist);
    shape = shape * shape; // Extra soft falloff - concentrated at center

    float alpha = shape * wisp_color.a;

    // Soft depth fade
    float depth_raw = textureLod(depth_texture, SCREEN_UV, 0.0).r;
    float depth_fade = clamp((depth_raw - FRAGCOORD.z) * softness, 0.0, 1.0);
    alpha *= depth_fade;

    // Lifetime fade from ParticleProcessMaterial
    alpha *= COLOR.a;
    vec3 final_color = wisp_color.rgb * COLOR.rgb;

    ALBEDO = final_color;
    ALPHA = alpha;
    EMISSION = final_color * 0.3;
}
