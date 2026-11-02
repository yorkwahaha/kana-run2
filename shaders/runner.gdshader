shader_type spatial;
// Runner sprite-sheet frame on a quad + white flash (hit_wrong / hit_shield). Never shakes the camera.
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);   // uv x, y, w, h of the current frame
uniform float flash : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 c = texture(tex, region.xy + UV * region.zw);
	ALBEDO = mix(c.rgb, vec3(1.0), flash);
	ALPHA = c.a;
}
