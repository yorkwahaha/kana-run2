extends SceneTree

const OUT_DIR := "C:/Users/York/.gemini/antigravity/brain/ffac2da6-5838-475f-8815-ccaa0e071612"
const TARGET_SZ := Vector2i(390, 844)

var g
var screens := ["run", "pause", "select", "ready", "results", "review", "settings"]
var current_idx := 0
var wait_frames := 0

func _initialize() -> void:
	DisplayServer.window_set_size(TARGET_SZ)
	root.size = TARGET_SZ
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = "user://screenshot_save.json"
	root.add_child(g)

func _process(_d: float) -> bool:
	if current_idx >= screens.size():
		quit(0)
		return true
	
	var scr: String = screens[current_idx]
	if wait_frames == 0:
		match scr:
			"run":
				g.set_speed_mode("race", false)
				g.reset_run()
				g.start_run()
				g.ctrl.speed = 10.0
				g.elapsed = 14.5
				g.correct = 8
				g._set_combo(8)
				g.player_dist = g.active_row().dist - 8.0
			"pause":
				g.reset_run()
				g.start_run()
				g.pause_game()
			"select":
				g.save.clear_all()
				g.select_tab = "hira"
				g.set_speed_mode("race", false)
				g.set_level(0)
				g.show_select()
			"ready":
				g.show_select()
				g.set_level(0)
				g.reset_run()
			"settings":
				g.show_select()
				g.show_settings()
			"results", "review":
				g.set_level(3)
				g.reset_run()
				g.start_run()
				g.elapsed = 51.0
				var row = g.active_row()
				g.player_dist = row.dist
				g.player_x = g.lane_x((row.target + 1) % row.kana.size())
				g._resolve(row)
				g.correct = int(g.lvl.target_correct)
				g._tick(0.0)
				if scr == "review":
					if g.btn_review != null and g.btn_review.visible:
						g.btn_review.pressed.emit()

	wait_frames += 1
	if wait_frames >= 14:
		var img := root.get_texture().get_image()
		var out_p := "%s/v3_390x844_%s.png" % [OUT_DIR, scr]
		img.save_png(out_p)
		print("Saved screenshot: ", out_p)
		current_idx += 1
		wait_frames = 0
	return false
