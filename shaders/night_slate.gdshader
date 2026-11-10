shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D painted_slate : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 hit_tint : source_color = vec4(1.0);
uniform float hit_strength = 0.0;

void fragment() {
	vec4 slate = texture(painted_slate, UV);
	ALBEDO = mix(slate.rgb, hit_tint.rgb, hit_strength);
	ALPHA = slate.a;
}
