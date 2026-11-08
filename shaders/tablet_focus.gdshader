shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// All three choices in the current question share this frame; no answer cue.
void fragment() {
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	ALBEDO = vec3(0.2, 0.92, 1.0);
	ALPHA = (1.0 - smoothstep(0.014, 0.026, edge)) * 0.72;
}
