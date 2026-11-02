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
	var lvl := {"time_limit_s": 60, "star2_s": 44, "star3_s": 32}
	check(Rules.stars_for(31.9, lvl) == 3 and Rules.stars_for(40, lvl) == 2 and Rules.stars_for(59, lvl) == 1 and Rules.stars_for(61, lvl) == 0, "star thresholds")
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

func _initialize() -> void:
	unit_tests()
	print("autopilot run")
	game = load("res://scenes/main.tscn").instantiate()
	game.autopilot = true
	game.force_dev_mode = true
	game.rng_seed = 7
	root.add_child(game)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
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
