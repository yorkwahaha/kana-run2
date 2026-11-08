extends SceneTree

const OUT_DIR := "C:/Users/York/.gemini/antigravity-cli/brain/1e908bfc-f048-451c-80ed-4337cb1cb087"
const TARGET_SZ := Vector2i(1280, 720)

var g
var screens := ["cyber_shop", "cyber_settings", "cyber_props_run", "cyber_combo_sfx"]
var current_idx := 0
var wait_frames := 0
var shutdown_msec := 0

func _initialize() -> void:
	DisplayServer.window_set_size(TARGET_SZ)
	root.size = TARGET_SZ
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = "user://screenshot_save.json"
	g.skip_title = true
	g.instant_transitions = true
	root.add_child(g)

func _process(_d: float) -> bool:
	if current_idx >= screens.size():
		if g != null:
			root.remove_child(g)
			g.free()
			g = null
			shutdown_msec = Time.get_ticks_msec()
		if Time.get_ticks_msec() - shutdown_msec >= 200:
			quit(0)
		return false

	var scr: String = screens[current_idx]
	if wait_frames == 0:
		match scr:
			"cyber_shop":
				g.save.add_points(1200)
				g.save.unlock_aura("emerald", 150)
				g.save.unlock_aura("crimson", 250)
				g.save.equip_aura("emerald")
				g._apply_upgrades_from_save()
				g.show_shop()
			"cyber_settings":
				g.hide_shop()
				g.show_settings()
				g._update_hit_pitch_button()
			"cyber_props_run":
				g.hide_settings()
				g.save.equip_aura("emerald")
				g._apply_upgrades_from_save()
				g.set_level(0)
				g.start_run()
				g.ctrl.speed = 12.0
				g.elapsed = 12.0
				g.correct = 6
				g._set_combo(6)
				g.player_dist = 85.0
				g._spawn_props()
			"cyber_combo_sfx":
				g.reset_run()
				g.save.equip_aura("crimson")
				g._apply_upgrades_from_save()
				g.set_level(3)
				g.start_run()
				g.ctrl.speed = 15.0
				g.elapsed = 24.0
				g.correct = 15
				g._set_combo(15)
				g.player_dist = 140.0
				g._spawn_props()
				g._spawn_shockwave(g.player.global_position + Vector3(0, 1.2, -1.0), Color(1.0, 0.88, 0.3), 320.0)
				g._screen_flash(Color(1.0, 0.92, 0.4, 0.16), 0.12)

	wait_frames += 1
	if wait_frames >= 16:
		var img := root.get_texture().get_image()
		if img != null:
			var out_p := "%s/1280x720_%s.png" % [OUT_DIR, scr]
			img.save_png(out_p)
			print("Saved screenshot: %s" % out_p)
		current_idx += 1
		wait_frames = 0
	return false
