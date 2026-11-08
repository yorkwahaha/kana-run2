shader_type canvas_item;

uniform vec4 warning_tint : source_color = vec4(0.0);
varying vec4 canvas_modulate;

void vertex() {
	canvas_modulate = COLOR;
}

void fragment() {
	vec4 art = texture(TEXTURE, UV);
	float value = max(art.r, max(art.g, art.b));
	float chroma = value - min(art.r, min(art.g, art.b));
	// Recolor the saturated fill while retaining the light stripes and outline.
	vec3 warning = vec3(value) - (vec3(1.0) - warning_tint.rgb) * chroma;
	COLOR = vec4(mix(art.rgb, warning, warning_tint.a), art.a) * canvas_modulate;
}
