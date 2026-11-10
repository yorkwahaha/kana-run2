shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.035, 0.042, 0.073, 0.75);
uniform float strength = 1.0;

void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * strength * (1.0 - smoothstep(0.08, 1.0, radius));
}
