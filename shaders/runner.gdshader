shader_type spatial;
// Runner sprite-sheet frame on a quad + white flash (hit_wrong / hit_shield). Never shakes the camera.
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D tex : source_color, filter_nearest_mipmap;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);   // uv x, y, w, h of the current frame
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 aura_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float aura_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 c = texture(tex, region.xy + UV * region.zw);
	vec3 tinted = mix(c.rgb, c.rgb * aura_color.rgb * 1.4, aura_strength);
	if (rim_strength > 0.05 && c.a > 0.1) {
		float rim = smoothstep(0.2, 0.65, abs(UV.x - 0.5) * 2.0);
		tinted += rim_color.rgb * rim * rim_strength * 0.45;
	}
	ALBEDO = mix(tinted, vec3(1.0), flash);
	ALPHA = c.a * opacity;
}
