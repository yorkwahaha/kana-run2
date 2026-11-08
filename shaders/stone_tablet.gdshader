shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 hit_tint : source_color = vec4(1.0);
uniform float hit_strength = 0.0;

varying vec3 stone_pos;
varying vec3 stone_normal;

float grain(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	stone_pos = VERTEX;
	stone_normal = NORMAL;
}

void fragment() {
	// Quantized mineral speckle keeps the stone compatible with the pixel city.
	vec2 p = stone_pos.xy;
	float fine = grain(floor(p * 105.0));
	float coarse = grain(floor(p * 19.0));
	float shade = 0.62 + 0.48 * max(dot(normalize(stone_normal), normalize(vec3(-0.5, 0.8, 0.9))), 0.0);
	vec3 rock = mix(vec3(0.25, 0.28, 0.32), vec3(0.48, 0.50, 0.51), coarse * 0.55 + fine * 0.45);
	rock += vec3(0.11) * step(0.965, fine);
	// Hairline fractures live at the outer face, away from the reading area.
	float fissure = abs(p.x - (0.51 + 0.035 * floor(p.y * 17.0)));
	float crack = (1.0 - step(0.012, fissure)) * step(0.27, p.y);
	float left_crack = (1.0 - step(0.009, abs(p.y + 0.54 + 0.12 * p.x))) * (1.0 - step(-0.35, p.x));
	vec3 base = rock * shade * (1.0 - max(crack, left_crack) * 0.66);
	// Mobile writes linear colour; Compatibility writes sRGB directly.
	if (!OUTPUT_IS_SRGB) {
		base = pow(base, vec3(2.2));
	}
	ALBEDO = mix(base, hit_tint.rgb, clamp(hit_strength, 0.0, 0.8));
}
