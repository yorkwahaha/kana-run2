extends SceneTree
## Headless smoke test: runs level 1 on autopilot (always correct lane,
## always accelerating) and checks it clears. Also runs unit checks.
## Run:  Godot --headless --path . --fixed-fps 60 -s res://tools/smoke_test.gd

const SpeedController = preload("res://scripts/speed_controller.gd")
const Rules = preload("res://scripts/rules.gd")

var game
var frames := 0
var fails := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		fails += 1
		printerr("  FAIL ", msg)

func unit_tests() -> void:
	print("unit tests")
	var c = SpeedController.new()
	c.configure({"max_speed_kmh": 60, "accel_time_s": 3.0, "brake_time_s": 1.2, "coast_time_s": 5.0, "double_tap_window_s": 0.28})
	c.press()
	var t := 0.0
	while c.speed < c.max_speed - 0.0001 and t < 10.0:
		c.step(1.0 / 60.0); t += 1.0 / 60.0
	check(absf(t - 3.0) < 0.05, "0->60 km/h in ~3 s (got %.2f)" % t)
	check(absf(c.kmh() - 60.0) < 0.01, "caps at 60 km/h")
	c.release(); c.step(0.1)
	c.press()   # second press within window = brake
	check(c.is_braking(), "double-tap starts brake")
	t = 0.0
	while c.speed > 0.0 and t < 10.0:
		c.step(1.0 / 60.0); t += 1.0 / 60.0
	check(t <= 1.25, "brake to 0 within ~1.2 s (got %.2f)" % t)
	c.release()
	c.step(1.0)
	c.press()
	check(not c.is_braking(), "slow second press is not a double-tap")
	c.speed = 10.0; c.scale_speed(0.5)
	check(is_equal_approx(c.speed, 5.0), "wrong hit halves speed")
	var lvl := {"time_limit_s": 63, "star2_s": 47, "star3_s": 36}
	check(Rules.stars_for(35.9, lvl) == 3 and Rules.stars_for(46, lvl) == 2 and Rules.stars_for(62, lvl) == 1 and Rules.stars_for(64, lvl) == 0, "star thresholds")
	var xs := [-2.2, 0.0, 2.2]
	check(Rules.hit_lane(0.0, xs, 0.9, 1.2) == 1 and Rules.hit_lane(-2.2, xs, 0.9, 1.2) == 0, "lane hit detection")
	check(Rules.hit_lane(-1.1, xs, 0.9, 1.2) == -1, "gap between stones = dodge")
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	var ok := true
	var prev := ""
	for i in 200:
		var r := Rules.make_row(["あ","い","う","え","お"], prev, rng)
		var k: Array = r.kana
		if k.size() != 3 or r.target < 0 or k[r.target] == prev: ok = false
		if k[0] == k[1] or k[1] == k[2] or k[0] == k[2]: ok = false
		prev = k[r.target]
	check(ok, "rows: 3 distinct kana, target present, no immediate repeat")

## Regression: first accelerate press from rest must accelerate (was braking).
func regression_tests() -> void:
	print("regression: first press from rest")
	var g = reg_game
	for keycode in [KEY_SPACE, KEY_W]:
		g.reset_run()
		var ev := InputEventKey.new(); ev.keycode = keycode; ev.pressed = true
		g._unhandled_input(ev)          # starts the run AND holds accelerate
		check(g.state == g.State.RUNNING, "key %s starts the run" % OS.get_keycode_string(keycode))
		check(g.ctrl.is_accelerating() and not g.ctrl.is_braking(), "first %s press accelerates, not brakes" % OS.get_keycode_string(keycode))
		g._tick(0.5)
		check(g.ctrl.kmh() > 5.0, "speed rises after first %s press (%.1f km/h)" % [OS.get_keycode_string(keycode), g.ctrl.kmh()])
	# touch / mouse
	g.reset_run()
	var t := InputEventScreenTouch.new(); t.pressed = true; t.index = 0
	g._unhandled_input(t)
	check(g.ctrl.is_accelerating() and not g.ctrl.is_braking(), "first touch accelerates")
	# real double-tap still brakes
	g._tick(0.5)
	t = InputEventScreenTouch.new(); t.pressed = false; t.index = 0; g._unhandled_input(t)
	g._tick(0.1)
	t = InputEventScreenTouch.new(); t.pressed = true; t.index = 0; g._unhandled_input(t)
	check(g.ctrl.is_braking(), "real double-tap (touch) brakes")
	# keyboard double-tap
	g.reset_run()
	var k := InputEventKey.new(); k.keycode = KEY_SPACE; k.pressed = true; g._unhandled_input(k)
	g._tick(0.3)
	k = InputEventKey.new(); k.keycode = KEY_SPACE; k.pressed = false; g._unhandled_input(k)
	g._tick(0.1)
	k = InputEventKey.new(); k.keycode = KEY_SPACE; k.pressed = true; g._unhandled_input(k)
	check(g.ctrl.is_braking(), "real double-tap (Space) brakes")
	# controller level: reset clears pending double-tap
	var c = SpeedController.new()
	c.press(); c.release(); c.reset(); c.press()
	check(not c.is_braking(), "reset() clears pending double-tap")
	var c2 = SpeedController.new()
	c2.release(); c2.press()
	check(not c2.is_braking(), "release without prior press is not a first tap")
	root.remove_child(g)
	g.free()

var reg_game

func _initialize() -> void:
	unit_tests()
	# nodes only get _ready() once the main loop runs, so the scene-based
	# tests start from _process (frame 1).
	reg_game = load("res://scenes/main.tscn").instantiate()
	reg_game.rng_seed = 3
	root.add_child(reg_game)

func _start_autopilot() -> void:
	print("autopilot run")
	game = load("res://scenes/main.tscn").instantiate()
	game.autopilot = true
	game.force_dev_mode = true
	game.rng_seed = 7
	root.add_child(game)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 1:
		regression_tests()
		_start_autopilot()
		return false
	if frames == 3:
		game.start_run()
	if game.state == game.State.CLEARED or game.state == game.State.FAILED or frames > 60 * 90:
		check(game.state == game.State.CLEARED, "autopilot clears level 1 (clock %.2f s, correct %d, wrong %d, miss %d)" % [game.clock(), game.correct, game.wrong, game.missed])
		check(game.wrong == 0 and game.missed == 0, "autopilot makes no mistakes")
		check(game.logger.entries.size() == 20, "dev logger recorded 20 questions")
		check(FileAccess.file_exists("user://timing/runs.csv"), "timing CSV written")
		print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
		root.remove_child(game)
		game.free()
		quit(1 if fails > 0 else 0)
		return true
	return false
