extends SceneTree
## Godot --headless --path . -s res://tools/night_road_check.gd

var failures := 0

func _initialize() -> void:
	call_deferred("_check_scene")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL ", description)

func _check_scene() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	if not game.has_method("reset_run"):
		game.free()
		quit(1)
		return
	game.skip_select = true
	game.save_path = "user://night_road_check.json"
	root.add_child(game)
	_check_motion(game)
	for window_size in [Vector2i(1080, 1920), Vector2i(390, 844), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = window_size
		game.runner.play_once("lane_right")
		game.reset_run()
		check(game.runner.anim == "idle" and not game.runner.is_one_shot(), "restart returns to the rear idle pose")
		game.start_run()
		await process_frame
		await process_frame
		var row: Dictionary = game.active_row()
		check(row.stones.size() == 3, "three stones on the opening row")
		var expected_width: float = game.stone_w
		for stone in row.stones:
			var glyph := stone.get_node("Kana") as Label3D
			check(glyph.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "kana faces the viewport")
			check(glyph.visible and glyph.modulate == Color("fff4d9"), "all active kana use the same ink")
			check(is_equal_approx(stone.mesh.size.x, expected_width), "slate width follows configured collision width")
			check(stone.get_node("FocusFrame").visible, "active indicator is shared by all three lanes")
		if game.rows.size() > 1:
			for stone in game.rows[1].stones:
				check(not stone.get_node("Kana").visible, "upcoming slabs do not compete with the active kana")
		var plate: TextureRect = game.street_rect
		var art_horizon: Vector2 = plate.position + game.STREET_VP * (plate.size / plate.texture.get_size())
		var camera_horizon: Vector2 = game.cam.unproject_position(Vector3(0.0, game.cam.position.y, -1000.0))
		check(art_horizon.distance_to(camera_horizon) < 0.5, "painted street and lane projection share a vanishing point")
		check(not game.lbl_hint.get_global_rect().intersects(game.lbl_notice.get_global_rect()), "notice cannot overlap the listening cue")
		var opening_distance: float = game.player_dist
		for remaining in [8.0, 2.0, 0.01]:
			game.player_dist = row.dist - remaining
			game._update_view(0.0)
			var drawn_gap: float = game.runner.global_position.z - row.stones[1].global_position.z
			var surface: ShaderMaterial = game.street_rect.material
			var scene_scale: float = surface.get_shader_parameter("travel_m") / game.player_dist
			check(absf(drawn_gap - remaining * scene_scale) < 0.001, "the slate and street use the same visual metre")
		var start_x: float = game.player_x
		for lane_index in [0, 2]:
			game.player_x = game.lane_x(lane_index)
			game._update_view(0.0)
			var extent: float = game.Art.RUNNER_CELL.x * game.runner.px * 0.5
			var left: Vector2 = game.cam.unproject_position(game.runner.global_position - Vector3(extent, 0.0, 0.0))
			var right: Vector2 = game.cam.unproject_position(game.runner.global_position + Vector3(extent, 0.0, 0.0))
			check(left.x >= 0.0 and right.x <= root.get_visible_rect().size.x, "outer lanes keep the complete runner in frame")
		game.player_x = start_x
		game.player_dist = opening_distance
		game._update_view(0.0)
		for child in game.get_children():
			check(not (child is Label3D), "the road contains no glyphs")
		var shield: Label = game.lbl_boss
		for locale in ["zh_TW", "zh_CN", "en", "ja"]:
			game.set_language(locale, false)
			shield.text = I18n.t("HUD_SHIELD_BROKEN_CNT", "護盾・已破 %d/%d") % [0, 3]
			check(shield.get_minimum_size().x <= game.shield_box.size.x, "full shield count fits " + locale)
		game.pause_game()
		await process_frame
		var menu: Control = game.pause_box.get_child(0)
		var view := root.get_visible_rect()
		var leftmost: Vector2 = game.cam.unproject_position(row.stones[0].global_position)
		if window_size.x > window_size.y:
			check(menu.get_global_rect().end.x < leftmost.x, "landscape pause leaves the road clear")
		check(view.grow(2.0).encloses(menu.get_global_rect()), "pause fits " + str(window_size))
		game.resume()
		game.player_x = game.lane_x(row.target)
		game.lane = row.target
		game.player_dist = row.dist - 0.02
		game._update_view(0.0)
		game.ctrl.speed = 8.0
		game._process(1.0 / 60.0)
		var contact: MeshInstance3D = row.stones[row.target]
		check(row.resolved and not contact.visible, "a real tick breaks the slate on contact")
		check(absf(contact.global_position.z - game.runner.global_position.z) < 0.001,
			"the fracture starts on the runner's contact line even when a frame crosses it")
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("Night road checks: %d failures" % failures)
	quit(int(failures > 0))

func _check_motion(game) -> void:
	var street: TextureRect = game.street_rect
	var surface := street.material as ShaderMaterial
	check(surface != null, "the painting supports continuous distance-driven motion")
	if surface == null:
		return
	game.save.set_setting("reduced_motion", false)
	game.reset_run()
	game.start_run()
	var crop := Rect2(street.position, street.size)
	var camera_origin: float = game.cam.position.z
	game._process(0.25)
	check(surface.get_shader_parameter("travel_m") == 0.0, "the street holds still at zero speed")
	game.ctrl.press()
	game._process(0.25)
	var scene_travel: float = surface.get_shader_parameter("travel_m")
	check(is_equal_approx(scene_travel, camera_origin - game.cam.position.z) and game.player_dist > scene_travel and scene_travel > 0.0,
		"scenery and camera share one calmer visual scale")
	check(surface.get_shader_parameter("sky_reveal") is Texture2D, "moving eaves can uncover the painted sky")
	game.pause_game()
	game._process(0.25)
	check(is_equal_approx(surface.get_shader_parameter("travel_m"), scene_travel), "pause holds the current view")
	game.player_dist = 1200.0
	game._update_view(0.0)
	check(is_equal_approx(surface.get_shader_parameter("travel_m"), camera_origin - game.cam.position.z), "long runs keep camera and scenery in sync")
	check(Rect2(street.position, street.size).is_equal_approx(crop), "motion keeps the crop and vanishing point fixed")
	game.save.set_setting("reduced_motion", true)
	game._update_view(0.0)
	check(surface.get_shader_parameter("travel_m") == 0.0, "reduced motion holds the painting")
	game.save.set_setting("reduced_motion", false)
	game.reset_run()
	check(surface.get_shader_parameter("travel_m") == 0.0, "restart restores the first view")
