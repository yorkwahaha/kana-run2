extends SceneTree

const OUT_DIR := "C:/Users/York/.gemini/antigravity/brain/ffac2da6-5838-475f-8815-ccaa0e071612"
const TARGET_SZ := Vector2i(390, 844)

var g
var screens := ["run", "idle", "brake", "shatter"]
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
				# Running forward in Shibuya streetscape
				g.set_speed_mode("race", false)
				g.reset_run()
				g.start_run()
				g.ctrl.speed = 10.0
				g.elapsed = 15.0
				g.correct = 8
				g._set_combo(8)
				g.player_dist = g.active_row().dist - 8.0
			"idle":
				# Stopped at 0 km/h: must show upright standing idle pose
				g.reset_run()
				g.start_run()
				g.ctrl.speed = 0.0
				g.ctrl.holding = false
				g.ctrl.brake_held = false
				g.runner.set_loop("idle")
			"brake":
				# Braking: must show low squat sliding brake pose with sole sparks
				g.reset_run()
				g.start_run()
				g.ctrl.speed = 8.0
				g.ctrl.brake_held = true
				g.runner.play_once("brake", 0, true)
			"shatter":
				# Shattering / punching correct stone
				g.reset_run()
				g.start_run()
				g.ctrl.speed = 10.0
				var row = g.active_row()
				g.player_dist = row.dist
				g.player_x = g.lane_x(row.target)
				g._fx_correct(row.stones[row.target])

	wait_frames += 1
	if wait_frames >= 14:
		var img := root.get_texture().get_image()
		var out_p := "%s/v4_390x844_%s.png" % [OUT_DIR, scr]
		img.save_png(out_p)
		print("Saved screenshot: ", out_p)
		current_idx += 1
		wait_frames = 0
	return false

