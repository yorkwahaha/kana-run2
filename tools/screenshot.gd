extends SceneTree
## Renders the HUD screens at several window sizes (needs a real window, not --headless).
## Godot --path . -s res://tools/screenshot.gd -- --out=C:/some/dir
## Writes <out>/<w>x<h>_<screen>.png

const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(390, 844), Vector2i(844, 390)]
var g
var out := "user://shots"
var steps: Array = []
var wait := 0
var shutdown_msec := 0
var night_road := false
var failures := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--night-road":
			night_road = true
	DirAccess.make_dir_recursive_absolute(out)
	g = load("res://scenes/main.tscn").instantiate()
	if not g.has_method("reset_run"):
		g.free()
		g = null
		failures += 1
		quit(1)
		return
	g.save_path = "user://screenshot_save.json"
	g.rng_seed = 20261109
	root.add_child(g)
	if night_road:
		for screen in ["ready", "run", "run_near", "pause", "select", "results", "boss_shield", "lane_left", "lane_right", "answer_ok", "answer_ng"]:
			steps.append([Vector2i(1080, 1920), screen])
		for sz in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
			for screen in ["ready", "run", "pause", "select", "results", "boss_shield"]:
				steps.append([sz, screen])
		return
	for sz in SIZES:
		for scr in ["select", "select_kata", "settings", "tutorial", "tutorial_replay", "tutorial_complete", "ready", "run", "run_step", "hp_damage", "boss_shield", "pause", "results", "review", "first_boss", "save_failed"]:
			steps.append([sz, scr])

func _process(_d: float) -> bool:
	if steps.is_empty():
		if g != null:
			root.remove_child(g); g.free(); g = null
			shutdown_msec = Time.get_ticks_msec()
		if Time.get_ticks_msec() - shutdown_msec >= 200:
			quit(int(failures > 0))
		return false
	var st: Array = steps[0]
	if wait == 0:
		DisplayServer.window_set_size(st[0])
		root.size = st[0]
		if night_road:
			g.set_distance("short", false)
			g.set_level(0)
			g.achievement_toast.hide()
			g.toast_queue.clear()
		match st[1]:
			"select":
				g.save.clear_all(); g.progress_pending = false; g.select_tab = "hira"; g.set_speed_mode("race", false)
				g.set_level(0); g.set_distance("mid", false); g.show_select()
			"select_kata":
				g.save.record("1-BOSS", "short", 1, 60.0)
				g.select_tab = "kata"; g.show_select(); g.select_tab = "hira"
			"tutorial": g.start_tutorial()
			"tutorial_replay", "tutorial_complete":
				g.start_tutorial()
				var exercises := 3 if st[1] == "tutorial_complete" else 2
				for i in exercises:
					if i == 2:
						g.replay_voice()
					var row = g.active_row()
					g.player_dist = row.dist
					g.player_x = g.lane_x(row.target)
					g._resolve(row)
				if exercises == 2:
					g.player_dist = g.active_row().dist - 4.0
			"hp_damage":
				g.set_level(0); g.reset_run(); g.start_run(); g.elapsed = 4.0; g.take_damage(35); g.hp_delay_wait = 99.0
			"boss_shield":
				g.set_level(3); g.reset_run(); g.start_run(); g.elapsed = 18.0
				if not g.shield_thresholds.is_empty():
					g.correct = ceili(float(g.shield_thresholds[0]) * int(g.lvl.target_correct))
					g._check_boss_shield()
				g.player_dist = g.active_row().dist - 12.0
			"ready": g.show_select(); g.set_level(0); g.reset_run()
			"run", "run_near":
				g.set_speed_mode("race", false); g.reset_run(); g.start_run(); g.ctrl.speed = 11.0; g.ctrl.toggle_lock()
				g.elapsed = 18.0; g.correct = 12; g._set_combo(12); g.ctrl.press(); g.ctrl.speed = 12.0
				g.player_dist = g.active_row().dist - (2.5 if st[1] == "run_near" else 12.0)
			"settings":
				g.show_select(); g.show_settings()
			"run_step":
				g.set_speed_mode("step", false); g.reset_run(); g.start_run(); g.ctrl.tap_up(); g.ctrl.tap_up(); g.ctrl.speed = 3.0
			"pause":
				g.reset_run(); g.start_run(); g.pause_game()
				g.player_dist = g.active_row().dist - 12.0
			"lane_left", "lane_right":
				g.reset_run(); g.start_run(); g.ctrl.speed = 8.0
				g.player_dist = g.active_row().dist - 13.0
				g.change_lane(-1 if st[1] == "lane_left" else 1)
			"answer_ok", "answer_ng":
				g.reset_run(); g.start_run(); g.ctrl.speed = 8.0
				var row = g.active_row()
				var lane_index: int = row.target if st[1] == "answer_ok" else (row.target + 1) % row.kana.size()
				g.player_dist = row.dist
				g.player_x = g.lane_x(lane_index)
				g.lane = lane_index
				g._resolve(row)
			"results", "review":
				g.set_level(3); g.reset_run(); g.start_run(); g.elapsed = 51.0
				var row = g.active_row()
				g.player_dist = row.dist
				g.player_x = g.lane_x((row.target + 1) % row.kana.size())
				g._resolve(row)
				g.correct = int(g.lvl.target_correct)
				g._tick(0.0)
				if st[1] == "review":
					g.btn_review.pressed.emit()
			"first_boss", "save_failed":
				g.save.clear_all(); g.set_level(3); g.reset_run(); g.start_run(); g.elapsed = 60.0
				var path: String = g.save.path
				if st[1] == "save_failed": g.save.path = "user://missing-screenshot-dir/save.json"
				g._finish(true)
				g.save.path = path
				if st[1] == "first_boss": g.btn_next.grab_focus()
	wait += 1
	if wait >= (36 if night_road and st[1] == "results" else 8):
		var img := root.get_texture().get_image()
		var saved := img.save_png("%s/%dx%d_%s.png" % [out, st[0].x, st[0].y, st[1]])
		if saved != OK or img.get_size() != st[0]:
			failures += 1
			printerr("Capture %s requested %s, rendered %s, save status %d" % [st[1], st[0], img.get_size(), saved])
		steps.pop_front()
		wait = 0
	return false
