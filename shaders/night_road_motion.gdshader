shader_type canvas_item;
render_mode unshaded;

uniform sampler2D corridor : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sky_reveal : source_color, filter_linear, repeat_disable;
uniform vec2 vanishing_px;
uniform float camera_height;
uniform float focal_px;
uniform float travel_m = 0.0;

// Geometry and period match tools/bake_night_corridor.py.
const float LEFT_WALL = 1.28;
const float RIGHT_WALL = 1.22;
const float WALL_HEIGHT = 11.6;
const float STRIP_START_M = 12.0;
const float STRIP_LENGTH_M = 14.0;

void fragment() {
	vec2 ray = UV / TEXTURE_PIXEL_SIZE - vanishing_px;
	float side = abs(ray.x);
	float wall = ray.x < 0.0 ? LEFT_WALL : RIGHT_WALL;
	float plane_px = max(1.0, max(ray.y, side / wall));
	float depth_m = focal_px * camera_height / plane_px;
	COLOR = texture(TEXTURE, UV);

	// Fade only by distance. An entire facade, including its eaves, shares one depth.
	float weight = 1.0 - smoothstep(44.0, 66.0, depth_m);
	if (weight > 0.0) {
		float left_m = LEFT_WALL * camera_height;
		float right_m = RIGHT_WALL * camera_height;
		float width_m = 2.0 * WALL_HEIGHT + left_m + right_m;
		float height_m = clamp(camera_height * (1.0 - ray.y / plane_px), 0.0, WALL_HEIGHT);
		float ground_x = ray.x * camera_height / plane_px;
		float section_m = WALL_HEIGHT + left_m + ground_x;
		if (ray.y < side / wall) {
			section_m += ray.x < 0.0 ? -height_m : height_m;
		}
		float u = clamp(section_m / width_m, 0.0003, 0.9997);
		// Keep derivatives continuous across the repeating strip.
		float v = (depth_m + travel_m - STRIP_START_M) / STRIP_LENGTH_M;
		vec4 street = texture(corridor, vec2(u, v));
		vec3 sky = texture(sky_reveal, UV).rgb;
		COLOR.rgb = mix(COLOR.rgb, mix(sky, street.rgb, street.a), weight);
	}
}
