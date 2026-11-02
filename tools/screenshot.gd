extends SceneTree
## Renders the HUD screens at several window sizes (needs a real window, not --headless).
## Godot --path . -s res://tools/screenshot.gd -- --out=C:/some/dir
## Writes <out>/<w>x<h>_<screen>.png

const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(390, 844), Vector2i(844, 390)]
var g
var out := "user://shots"
var steps: Array = []
var wait := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = "user://screenshot_save.json"
	root.add_child(g)
	for sz in SIZES:
		for scr in ["select", "settings", "run", "run_step", "pause", "results"]:
			steps.append([sz, scr])

func _process(_d: float) -> bool:
	if steps.is_empty():
		quit(0)
		return true
	var st: Array = steps[0]
	if wait == 0:
		DisplayServer.window_set_size(st[0])
		root.size = st[0]
		match st[1]:
			"select": g.show_select()
			"ready": g.set_level(0); g.reset_run()
			"run":
				g.set_speed_mode("race", false); g.reset_run(); g.start_run(); g.ctrl.speed = 11.0; g.ctrl.toggle_lock()
				g.lbl_notice.text = "聽音模式"; g.correct = 12; g._set_combo(12); g.ctrl.press(); g.ctrl.speed = 12.0
			"settings":
				g.show_select(); g.show_settings()
			"run_step":
				g.set_speed_mode("step", false); g.reset_run(); g.start_run(); g.ctrl.tap_up(); g.ctrl.tap_up(); g.ctrl.speed = 3.0
			"pause":
				g.reset_run(); g.start_run(); g.pause_game()
			"results":
				g.reset_run(); g.start_run(); g.correct = 20; g._tick(0.0)
	wait += 1
	if wait >= 8:
		var img := root.get_texture().get_image()
		img.save_png("%s/%dx%d_%s.png" % [out, st[0].x, st[0].y, st[1]])
		steps.pop_front()
		wait = 0
	return false
