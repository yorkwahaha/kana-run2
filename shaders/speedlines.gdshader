shader_type canvas_item;
render_mode blend_add;

uniform vec2 center = vec2(0.5, 0.45);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.20;
uniform float outer_radius : hint_range(0.0, 1.5) = 0.70;
uniform vec4 line_color : source_color = vec4(0.45, 0.92, 1.0, 0.85);
uniform float line_density : hint_range(20.0, 300.0) = 90.0;
uniform float time_speed : hint_range(1.0, 50.0) = 30.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	if (intensity <= 0.001) {
		discard;
	}
	vec2 uv = UV;
	vec2 dir = uv - center;
	// Aspect ratio correction: make radial lines circular and scale properly
	float aspect = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.0001);
	vec2 aspect_dir = vec2(dir.x * aspect, dir.y);
	float dist = length(aspect_dir);
	float angle = atan(dir.y, dir.x);

	// Stepped radial streaks along angle
	float sector = floor(angle * (line_density / 6.2831853));
	float noise = hash(sector + floor(TIME * time_speed));
	float streak = step(0.42, noise) * pow(noise, 1.5);

	// Radial mask: 0 at center (inner_radius), 1 toward outer edges
	float radial_mask = smoothstep(inner_radius, outer_radius, dist);

	float alpha = streak * radial_mask * intensity * line_color.a;
	COLOR = vec4(line_color.rgb, alpha);
}
