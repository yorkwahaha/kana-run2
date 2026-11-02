extends SceneTree
## Headless smoke test: runs level 1 on autopilot (always correct lane,
## always accelerating) and checks it clears. Also runs unit checks.
## Run:  Godot --headless --path . --fixed-fps 60 -s res://tools/smoke_test.gd

const SpeedController = preload("res://scripts/speed_controller.gd")
const Rules = preload("res://scripts/rules.gd")
const Assets = preload("res://scripts/asset_manifest.gd")
const SaveData = preload("res://scripts/save_data.gd")
const GameConfig = preload("res://scripts/game_config.gd")
const LevelDB = preload("res://scripts/level_db.gd")
const DevLogger = preload("res://scripts/dev_logger.gd")

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
	c.configure({"max_speed_kmh": 60, "accel_time_s": 3.0, "brake_time_s": 1.2, "coast_time_s": 5.0})
	c.press()
	var t := 0.0
	while c.speed < c.max_speed - 0.0001 and t < 10.0:
		c.step(1.0 / 60.0); t += 1.0 / 60.0
	check(absf(t - 3.0) < 0.05, "0->60 km/h in ~3 s (got %.2f)" % t)
	check(absf(c.kmh() - 60.0) < 0.01, "caps at 60 km/h")
	c.release(); c.press(); c.release(); c.press()
	check(c.is_accelerating() and not c.is_braking(), "rapid re-presses of accelerate never brake (no double-tap)")
	c.release()
	var v0: float = c.speed
	c.step(1.0)
	check(c.speed < v0 and c.speed > 0.0 and absf((v0 - c.speed) - c.max_speed / 5.0) < 0.01, "neither held = natural coast-down")
	c.speed = c.max_speed
	c.brake_press()
	t = 0.0
	while c.speed > 0.0 and t < 10.0:
		c.step(1.0 / 60.0); t += 1.0 / 60.0
	check(t <= 1.25, "brake held: 60 -> 0 within ~1.2 s (got %.2f)" % t)
	c.press()
	check(c.is_braking() and not c.is_accelerating(), "brake wins when both are held")
	c.release_all()
	check(not c.holding and not c.brake_held, "release_all lets go of both")
	mode_unit_tests()

func _run(c, secs: float) -> void:
	var t := 0.0
	while t < secs - 0.00001:
		c.step(1.0 / 60.0); t += 1.0 / 60.0

func mode_unit_tests() -> void:
	print("cruise lock (race)")
	var c = SpeedController.new()
	c.configure({"max_speed_kmh": 60, "accel_time_s": 3.0, "brake_time_s": 1.2, "coast_time_s": 5.0, "step_kmh": 5})
	c.press(); _run(c, 2.0); c.release()
	var v: float = c.kmh()
	c.toggle_lock()
	check(c.locked and absf(c.lock_kmh() - v) < 0.01, "lock captures current speed (%.1f km/h)" % v)
	_run(c, 3.0)
	check(absf(c.kmh() - v) < 0.01, "locked + no input = holds speed (no coast)")
	c.press(); _run(c, 0.5)
	check(c.kmh() > v + 5.0, "hold accel while locked = temporary speed-up")
	c.release(); _run(c, 0.1)
	check(c.kmh() > v + 0.5 and c.kmh() < v + 10.0, "on release speed returns gradually (not instant)")
	_run(c, 2.0)
	check(absf(c.kmh() - v) < 0.01, "returns to locked speed")
	c.brake_press(); _run(c, 0.4); c.brake_release()
	var low: float = c.kmh()
	check(low < v - 10.0, "hold brake while locked = temporary slow-down")
	_run(c, 0.2)
	check(c.kmh() > low and c.kmh() < v, "climbs back along accel curve")
	_run(c, 3.0)
	check(absf(c.kmh() - v) < 0.01, "back at locked speed")
	c.toggle_lock(); _run(c, 1.0)
	check(not c.locked and c.kmh() < v - 5.0, "unlock = coasts again")
	print("step mode")
	var d = SpeedController.new()
	d.configure({"max_speed_kmh": 60, "accel_time_s": 3.0, "brake_time_s": 1.2, "coast_time_s": 5.0, "step_kmh": 5, "step_wrong_halves_target": true})
	d.set_mode("step")
	d.press(); d.release(); d.press(); d.release(); d.press(); d.release()
	check(is_equal_approx(d.target_kmh(), 15.0), "3 taps = target 15 km/h")
	_run(d, 0.1)
	check(d.kmh() > 0.0 and d.kmh() < 15.0, "speed chases target along accel curve (%.1f)" % d.kmh())
	_run(d, 1.0)
	check(is_equal_approx(d.kmh(), 15.0), "reaches target")
	_run(d, 5.0)
	check(is_equal_approx(d.kmh(), 15.0), "no input = holds target (no coast)")
	for i in 20: d.press(); d.release()
	check(is_equal_approx(d.target_kmh(), 60.0), "target clamps at 60")
	_run(d, 4.0)
	d.brake_press(); d.brake_release()
	check(is_equal_approx(d.target_kmh(), 55.0), "brake tap = -5")
	_run(d, 0.05)
	check(d.kmh() < 60.0 and d.kmh() > 55.0 and d.is_braking(), "slows toward target along brake curve")
	for i in 30: d.brake_press(); d.brake_release()
	check(d.target_kmh() == 0.0, "target clamps at 0")
	_run(d, 3.0)
	check(d.kmh() == 0.0, "stops at target 0")
	for i in 6: d.press(); d.release()
	_run(d, 3.0)
	d.scale_speed(0.5)
	check(is_equal_approx(d.kmh(), 15.0) and is_equal_approx(d.target_kmh(), 15.0), "wrong hit halves speed and target (switch on)")
	d.step_halves_target = false
	d.scale_speed(0.5)
	check(is_equal_approx(d.target_kmh(), 15.0), "switch off: target kept")
	d.speed = 40.0 / 3.6; d.set_mode("race"); d.set_mode("step")
	check(is_equal_approx(d.target_kmh(), 40.0), "race->step mid-run: target = current speed (rounded to step)")
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

func _key(g, code: int, down: bool) -> void:
	var ev := InputEventKey.new(); ev.keycode = code; ev.pressed = down
	g._unhandled_input(ev)

func _tap(g, idx: int, pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new(); ev.index = idx; ev.position = pos; ev.pressed = down
	g._touch(ev)

func _drag(g, idx: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new(); ev.index = idx; ev.position = pos
	g._touch(ev)

func regression_tests() -> void:
	print("controls")
	var g = reg_game
	for keycode in [KEY_SPACE, KEY_W, KEY_UP]:
		g.reset_run()
		_key(g, keycode, true)
		check(g.state == g.State.RUNNING and g.ctrl.is_accelerating() and not g.ctrl.is_braking(), "first %s press starts and accelerates" % OS.get_keycode_string(keycode))
		g._tick(0.5)
		check(g.ctrl.kmh() > 5.0, "speed rises (%.1f km/h)" % g.ctrl.kmh())
		_key(g, keycode, false)
	# rapid double press of accelerate must not brake any more
	g.reset_run()
	_key(g, KEY_SPACE, true); g._tick(0.3); _key(g, KEY_SPACE, false); g._tick(0.05); _key(g, KEY_SPACE, true)
	check(g.ctrl.is_accelerating() and not g.ctrl.is_braking(), "double-tapping Space accelerates (double-tap brake removed)")
	_key(g, KEY_SPACE, false)
	for keycode in [KEY_S, KEY_DOWN]:
		g.ctrl.speed = 10.0
		_key(g, keycode, true)
		check(g.ctrl.is_braking(), "%s held = brake" % OS.get_keycode_string(keycode))
		g._tick(1.0)
		check(g.ctrl.speed == 0.0, "%s brakes to a stop" % OS.get_keycode_string(keycode))
		_key(g, keycode, false)
		check(not g.ctrl.is_braking(), "%s released = no brake" % OS.get_keycode_string(keycode))
	g.ctrl.speed = 10.0; g._tick(0.5)
	check(g.ctrl.speed < 10.0 and g.ctrl.speed > 0.0, "no key = coast-down")
	var l0: int = g.lane
	_key(g, KEY_A, true); _key(g, KEY_A, false)
	_key(g, KEY_D, true); _key(g, KEY_D, false); _key(g, KEY_RIGHT, true)
	check(g.lane == mini(l0 + 1, 2), "A/D/arrow lane changes without holding accelerate")
	print("touch")
	g.reset_run()
	var acc: Vector2 = g.btn_accel.get_global_rect().get_center()
	var brk: Vector2 = g.btn_brake.get_global_rect().get_center()
	var mid: Vector2 = g.get_viewport().get_visible_rect().size * Vector2(0.5, 0.45)
	_tap(g, 0, acc, true)
	check(g.state == g.State.RUNNING and g.ctrl.is_accelerating(), "first touch on 「加速」 starts and accelerates")
	g.lane = 1; g.player_x = g.lane_x(1)
	_tap(g, 1, mid, true)
	_drag(g, 1, mid + Vector2(120, 0))
	check(g.lane == 2 and g.ctrl.is_accelerating(), "second finger swipes lane while 「加速」 stays held")
	_tap(g, 1, mid + Vector2(120, 0), false)
	_drag(g, 0, acc + Vector2(-120, 0))
	check(g.lane == 1 and g.ctrl.is_accelerating(), "accelerate finger can swipe sideways and keep accelerating")
	_tap(g, 2, brk, true)
	check(g.ctrl.is_braking(), "「煞車」 held brakes (even with 加速 held)")
	_tap(g, 2, brk, false)
	check(not g.ctrl.is_braking() and g.ctrl.is_accelerating(), "release 「煞車」 -> back to accelerate")
	_tap(g, 0, acc, false)
	check(not g.ctrl.holding and not g.ctrl.brake_held, "all fingers up = coast")
	_tap(g, 3, mid, true); _tap(g, 3, mid, false); _tap(g, 3, mid, true)
	check(not g.ctrl.is_braking() and not g.ctrl.holding, "double-tap on screen does nothing (no brake)")
	_tap(g, 3, mid, false)
	print("pause")
	g.reset_run(); _key(g, KEY_SPACE, true)
	g._tick(1.0)
	var e0: float = g.elapsed
	_key(g, KEY_ESCAPE, true); _key(g, KEY_ESCAPE, false)
	check(g.state == g.State.PAUSED and g.pause_box.visible, "Esc pauses, menu shown")
	check(not g.ctrl.holding, "pause releases held accelerate")
	_key(g, KEY_SPACE, false)
	for i in 120: g._process(1.0 / 60.0)
	check(is_equal_approx(g.elapsed, e0), "timer frozen while paused (2 s of frames)")
	_key(g, KEY_ESCAPE, true)
	check(g.state == g.State.RUNNING and not g.pause_box.visible and not g.ctrl.holding, "Esc again resumes, nothing stuck held")
	g._process(0.5)
	check(absf(g.elapsed - (e0 + 0.5)) < 0.001, "clock = play time only (paused time excluded)")
	_key(g, KEY_P, true)
	check(g.state == g.State.PAUSED, "P pauses")
	g.btn_resume.pressed.emit()
	check(g.state == g.State.RUNNING, "「繼續」 resumes")
	_key(g, KEY_P, true); _key(g, KEY_R, true)
	check(g.state == g.State.READY and g.elapsed == 0.0, "R in pause = restart")
	_key(g, KEY_SPACE, true); _key(g, KEY_SPACE, false); _key(g, KEY_ESCAPE, true); _key(g, KEY_Q, true)
	check(g.state == g.State.SELECT and not g.pause_box.visible, "Q in pause = back to level select")
	g.reset_run(); g.start_run(); g.pause_game(); g.btn_restart.pressed.emit()
	check(g.state == g.State.READY, "「重來」 restarts")
	g.start_run(); g.pause_game(); g.btn_quit.pressed.emit()
	check(g.state == g.State.SELECT, "「回選關」 from pause")
	g.reset_run(); g.start_run()
	_tap(g, 5, g.btn_pause.get_global_rect().get_center(), true)
	check(g.state == g.State.PAUSED, "on-screen pause button pauses")
	g.resume()
	g.ctrl.press()
	g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(g.state == g.State.PAUSED and not g.ctrl.holding, "focus-out auto-pauses and releases input")
	g.resume()
	g._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(g.state == g.State.PAUSED, "app paused (mobile/background) auto-pauses")
	g.resume()
	g._on_js_visibility(null)   # not web: document missing, must not crash
	check(g.state == g.State.RUNNING, "web visibility handler is safe outside web")
	print("voice replay")
	g.voice.stop(); g.voice.stream = null
	_key(g, KEY_E, true)
	check(g.voice.stream != null, "E replays the current voice")
	g.voice.stream = null
	_tap(g, 6, g.btn_voice.get_global_rect().get_center(), true)
	check(g.voice.stream != null and g.state == g.State.RUNNING, "speaker button replays voice")
	_key(g, KEY_R, true)
	check(g.state == g.State.RUNNING, "R while running does nothing (moved to E)")
	feature_tests(g)
	hp_tests(g)
	mode_game_tests(g)

func _answer(g, mode: String) -> void:
	var r = g.active_row()
	g.player_dist = r.dist
	if mode == "correct":
		g.player_x = g.lane_x(r.target)
	elif mode == "wrong":
		g.player_x = g.lane_x((r.target + 1) % 3)
	else:
		g.player_x = g.lane_x(0) + g.lane_w * 0.5   # gap between stones
	g._resolve(r)
	g._spawn_rows()

func feature_tests(g) -> void:
	print("hints / voice-only mode")
	check(Rules.hint_visible(0, 3, 0.0, 0.5) and Rules.hint_visible(2, 3, 0.45, 0.5), "hint_visible: shown for first N, before ratio")
	check(not Rules.hint_visible(3, 3, 0.0, 0.5) and not Rules.hint_visible(0, 3, 0.5, 0.5), "hint_visible: hidden after N or at ratio")
	g.reset_run(); g.start_run()
	var seen := {}
	var hint_ok := true
	var notice_before := false
	g.set_level(0); g.reset_run(); g.start_run()
	while g.correct < 8:
		var r = g.active_row()
		var k: String = r.kana[r.target]
		var n: int = seen.get(k, 0)
		if r.hint != (n < 3): hint_ok = false
		if r.hint and g.lbl_hint.text != g._romaji(k): hint_ok = false
		seen[k] = n + 1
		if g.voice_only_announced: notice_before = true
		_answer(g, "correct")
	check(hint_ok, "romaji hint shown exactly for each kana's first 3 appearances")
	check(not notice_before, "no voice-only notice before 50%% (8/15 is the switch)")
	var r2 = g.active_row()
	check(not r2.hint and g.lbl_hint.text == "?", "after 50%% progress the question is voice-only")
	check(g.voice_only_announced and g.lbl_notice.text == "聽音模式", "「聽音模式」notice shown on switch")
	check(Assets.FONT_HUD.has_char("模".unicode_at(0)) and Assets.FONT_HUD.has_char("聽".unicode_at(0)) and Assets.FONT_HUD.has_char("擊".unicode_at(0)), "HUD font has 聽音模式 / 連擊 glyphs")
	print("wrong-hit retry / miss re-queue / combo")
	g.reset_run(); g.start_run()
	_answer(g, "correct"); _answer(g, "correct")
	check(g.combo == 2 and g.lbl_combo.text == "2 連擊", "combo counts consecutive correct (2)")
	var r = g.active_row()
	var k: String = r.kana[r.target]
	var old_lane: int = r.target
	_answer(g, "wrong")
	check(g.combo == 0, "wrong hit resets combo")
	var nx = g.active_row()
	check(nx.kana[nx.target] == k and nx.target != old_lane and nx.retry, "wrong hit: same kana comes back in a different lane")
	var lab_ok := true
	for i in 3:
		if (nx.stones[i].get_node("Kana") as Label3D).text != nx.kana[i]: lab_ok = false
	check(lab_ok and nx.kana.size() == 3 and nx.kana[0] != nx.kana[1] and nx.kana[1] != nx.kana[2] and nx.kana[0] != nx.kana[2], "retry row labels updated, 3 distinct kana")
	_answer(g, "correct")
	check(g.combo == 1, "combo restarts at 1")
	var mr = g.active_row()
	var mk: String = mr.kana[mr.target]
	var before_rows: int = g.rows.size()
	_answer(g, "miss")
	check(g.combo == 0, "miss also resets combo")
	check(g.missed == 1, "dodging all three counts as miss")
	check(g.rows.size() > before_rows, "a new row spawned after the miss")
	var nr = g.rows[before_rows] if g.rows.size() > before_rows else null
	var came_back: bool = nr != null and nr.kana[nr.target] == mk and nr.voice_t < 0.0
	check(came_back and g.requeue.is_empty(), "missed kana re-queued into a later row")
	print("random play terminates")
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	g.reset_run(); g.start_run()
	g.set_max_hp(999, true)   # this test is about re-queue termination, not HP
	var steps := 0
	var need: int = int(g.lvl.target_correct)
	while g.correct < need and steps < 500:
		var p := rng.randf()
		_answer(g, "correct" if p < 0.6 else ("wrong" if p < 0.85 else "miss"))
		steps += 1
	check(g.correct >= need and steps < 500, "mixed correct/wrong/miss still reaches %d correct (%d rows)" % [need, steps])

var reg_game
var auto_level := 0
var auto_i := 0
const AUTO_RUNS := [[0, "race"], [3, "race"], [20, "race"], [0, "step"], [3, "step"], [20, "step"]]
var phase := "unit"
var layout_i := 0
var layout_wait := 0
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(390, 844), Vector2i(844, 390), Vector2i(720, 1280), Vector2i(2560, 600)]

func _initialize() -> void:
	unit_tests()
	# nodes only get _ready() once the main loop runs, so the scene-based
	# tests start from _process (frame 1).
	DirAccess.remove_absolute("user://selftest_save.json")
	reg_game = load("res://scenes/main.tscn").instantiate()
	reg_game.rng_seed = 3
	reg_game.save_path = "user://selftest_save.json"
	root.add_child(reg_game)

func _start_autopilot() -> void:
	print("autopilot run")
	game = load("res://scenes/main.tscn").instantiate()
	game.autopilot = true
	game.save_path = "user://selftest_save_auto.json"
	game.skip_select = true
	auto_level = AUTO_RUNS[auto_i][0]
	game.level_index = auto_level
	game.force_mode = AUTO_RUNS[auto_i][1]
	game.force_dev_mode = true
	game.rng_seed = 7
	game.force_distance = "short"
	root.add_child(game)

func hp_tests(g) -> void:
	print("HP")
	var cfg: Dictionary = GameConfig.load_config()
	check(int(cfg.hp.max_hp) == 100 and int(cfg.hp.wrong_damage) == 35 and int(cfg.hp.miss_damage) == 0, "config: HP 100, wrong -35, miss 0 by default")
	g.set_level(0); g.reset_run(); g.start_run()
	check(g.hp == 100 and g.max_hp == 100 and g.lbl_hp.text == "100 / 100", "run starts at 100 / 100")
	var got := []
	var cb := func(h, m, sh): got.append([h, m, sh])
	g.hp_changed.connect(cb)
	g.ctrl.speed = 10.0
	var p0: float = g.penalty
	_answer(g, "wrong")
	check(g.hp == 65 and g.lbl_hp.text == "65 / 100", "wrong hit = -35 HP")
	check(is_equal_approx(g.penalty - p0, 2.0) and is_equal_approx(g.ctrl.speed, 5.0), "wrong hit still -2 s and speed halved")
	check(got.size() >= 1 and got[-1][0] == 65, "hp_changed signal emitted")
	check(g.hp_delayed > 65.0 and g.hp_chunk.offset_right > g.hp_fill.offset_right, "delayed red chunk stays visible right after the hit")
	for i in 200: g._tick_hp_bar(1.0 / 60.0)
	check(is_equal_approx(g.hp_delayed, 65.0), "delayed chunk drains down to the real HP (%.1f)" % g.hp_delayed)
	check(g.cam.h_offset == 0.0 and g.cam.v_offset == 0.0, "no camera/screen shake on damage")
	_answer(g, "miss")
	check(g.hp == 65, "miss costs no HP by default")
	g.elapsed = 0.0
	for i in 30: g._tick(1.0 / 60.0)
	check(g.hp == 65, "no passive HP drain")
	_answer(g, "wrong")
	check(g.hp == 30 and g.state == g.State.RUNNING, "30 HP left, still running")
	_answer(g, "wrong")
	check(g.hp == 0 and g.state == g.State.FAILED and g.fail_reason == "hp_out", "0 HP ends the run immediately (reason hp_out)")
	check(g.lbl_result.text.begins_with("體力耗盡") and g.results_box.visible, "results show 「體力耗盡」")
	check(not g.save.cleared_any("1-1"), "hp_out is not saved as a clear")
	g.hp_changed.disconnect(cb)
	g.reset_run(); g.start_run(); g.elapsed = 999.0; g._tick(0.0)
	check(g.fail_reason == "time_up" and g.lbl_result.text.begins_with("時間到"), "time-up shows 「時間到」 (distinct reason)")
	g.reset_run(); g.start_run(); g.miss_damage = 20
	_answer(g, "miss")
	check(g.hp == 80, "miss_damage switch: miss = -20")
	var lv: Array = GameConfig.levels(cfg)
	lv[0]["max_hp"] = 150; lv[0]["miss_damage"] = 10
	g.levels = lv; g.set_level(0); g.reset_run()
	check(g.max_hp == 150 and g.hp == 150 and g.miss_damage == 10, "per-level max_hp / miss_damage override")
	g.levels = GameConfig.levels(GameConfig.load_config()); g.set_level(0); g.reset_run(); g.start_run()
	g.add_shield(1)
	check(g.lbl_shield.text == "盾1", "shield shown")
	var blocked := []
	var dcb := func(a, b): blocked.append(b)
	g.damaged.connect(dcb)
	check(not g.take_damage(35) and g.hp == 100 and g.shield == 0 and blocked == [true], "shield (charm) blocks one hit")
	g.take_damage(35)
	check(g.hp == 65 and blocked[-1] == false, "next hit goes through")
	g.damaged.disconnect(dcb)
	g.heal(20); g.heal(50)
	check(g.hp == 100, "heal(value), capped at max")
	g.set_damage_reduction(20.0)
	g.take_damage(35)
	check(g.hp == 72, "damage_reduction 20%%: 35 -> 28")
	g.set_damage_reduction(0.0)
	g.set_max_hp_bonus(50)
	check(g.max_hp == 150 and g.hp == 150, "max-HP upgrade hook (+50) refills to 150")
	g.reset_run()
	check(g.max_hp == 150, "max-HP bonus persists across restarts")
	g.set_max_hp_bonus(0); g.reset_run()
	check(g.max_hp == 100, "bonus removable")
	g.force_dev_mode = true; g.dev_mode = true
	g.start_run(); g.take_damage(100)
	var j = JSON.parse_string(FileAccess.get_file_as_string(g.last_saved_path))
	check(j is Dictionary and j.outcome == "hp_out" and int(j.hp_left) == 0, "timing log records outcome hp_out")
	g.dev_mode = false
	g.set_level(0)

func mode_game_tests(g) -> void:
	print("speed modes in game")
	g.set_speed_mode("race")
	g.set_level(0); g.reset_run(); _key(g, KEY_W, true); g._tick(2.0); _key(g, KEY_W, false)
	_key(g, KEY_F, true); _key(g, KEY_F, false)
	g._update_hud()
	check(g.ctrl.locked and g.lbl_speed.text.contains("鎖定") and g.btn_lock.visible, "F locks, HUD shows 鎖定 + km/h, 鎖定 button visible")
	var v: float = g.ctrl.kmh()
	for i in 120: g.ctrl.step(1.0 / 60.0)
	check(absf(g.ctrl.kmh() - v) < 0.01, "in game: locked speed held")
	_tap(g, 8, g.btn_lock.get_global_rect().get_center(), true); _tap(g, 8, g.btn_lock.get_global_rect().get_center(), false)
	check(not g.ctrl.locked, "鎖定 button toggles lock off")
	g.set_speed_mode("step")
	g._update_hud()
	check(not g.btn_lock.visible and g.lbl_speed.text.contains("→"), "step mode: no 鎖定 button, HUD shows current → target")
	g.reset_run()
	_key(g, KEY_W, true); _key(g, KEY_W, false)
	var echo := InputEventKey.new(); echo.keycode = KEY_W; echo.pressed = true; echo.echo = true
	g._unhandled_input(echo)
	_key(g, KEY_UP, true); _key(g, KEY_UP, false)
	check(is_equal_approx(g.ctrl.target_kmh(), 10.0), "W / ↑ taps = +5 each, key-repeat (echo) ignored")
	_key(g, KEY_S, true); _key(g, KEY_S, false)
	check(is_equal_approx(g.ctrl.target_kmh(), 5.0), "S tap = -5")
	var acc: Vector2 = g.btn_accel.get_global_rect().get_center()
	_tap(g, 0, acc, true); _tap(g, 0, acc, false); _tap(g, 0, acc, true); _tap(g, 0, acc, false)
	check(is_equal_approx(g.ctrl.target_kmh(), 15.0), "「加速」 taps = +5 each")
	_tap(g, 1, g.btn_brake.get_global_rect().get_center(), true); _tap(g, 1, g.btn_brake.get_global_rect().get_center(), false)
	check(is_equal_approx(g.ctrl.target_kmh(), 10.0), "「煞車」 tap = -5")
	var sd = SaveData.new(); sd.path = g.save.path; sd.load_file()
	check(sd.get_setting("speed_mode") == "step", "mode saved to save file")
	# pause-menu switch
	g.ctrl.speed = 32.0 / 3.6
	g.pause_game()
	check(g.btn_mode_pause.text.begins_with("模式：點放"), "pause menu shows mode switch")
	g.btn_mode_pause.pressed.emit()
	check(g.speed_mode == "race" and g.ctrl.mode == "race" and g.state == g.State.PAUSED and not g.ctrl.locked, "pause-menu switch to 賽車 applies (still paused, unlocked)")
	g.btn_mode_pause.pressed.emit()
	check(g.speed_mode == "step" and is_equal_approx(g.ctrl.target_kmh(), 30.0), "switch to 點放 mid-run: target = current speed rounded (30)")
	check(not g.lbl_hint.visible, "romaji hint hidden behind pause menu")
	g.resume()
	check(g.lbl_hint.visible, "hint back after resume")
	# settings screen
	g.show_select()
	check(g.btn_settings != null and g.btn_settings.text.contains("點放"), "level select has 「設定」 showing mode")
	g.btn_settings.pressed.emit()
	check(g.settings_box.visible and not g.select_box.visible and g.btn_mode_step.button_pressed, "settings panel opens, current mode selected")
	g.btn_mode_race.pressed.emit()
	sd.load_file()
	check(g.speed_mode == "race" and sd.get_setting("speed_mode") == "race" and g.btn_mode_race.button_pressed and not g.btn_mode_step.button_pressed, "settings: 賽車 chosen and saved")
	g.btn_settings_back.pressed.emit()
	check(g.select_box.visible and not g.settings_box.visible, "返回 goes back to level select")
	# results + log field
	g.set_speed_mode("step")
	g.force_dev_mode = true; g.dev_mode = true
	g.set_level(0); g.reset_run(); g.start_run()
	while g.correct < int(g.lvl.target_correct): _answer(g, "correct")
	g._tick(0.0)
	check(g.lbl_result.text.contains("點放模式"), "results show mode")
	var j = JSON.parse_string(FileAccess.get_file_as_string(g.last_saved_path))
	check(j is Dictionary and j.mode == "step", "timing JSON records mode")
	check(j.distance == g.distance and int(j.target_correct) == int(g.lvl.target_correct) and j.has("points"), "timing JSON records distance / target / points")
	var csv := FileAccess.get_file_as_string(DevLogger.RUNS_FILE).strip_edges().split("\n")
	check(DevLogger.RUNS_FILE.ends_with("runs_v4.csv") and csv[0].ends_with(",mode,distance,target,points") and csv[-1].contains(",step,%s," % g.distance), "runs_v4.csv has mode + distance columns")
	g.dev_mode = false
	g.set_speed_mode("race")
	g.save.clear_all(); g.save.save_file()
	g.set_level(0)

func level_tests(g) -> void:
	print("level table (Kana Warrior skeleton)")
	var cfg: Dictionary = GameConfig.load_config()
	var lv: Array = GameConfig.levels(cfg)
	var hira := lv.filter(func(L): return L.script == "hira")
	var kata := lv.filter(func(L): return L.script == "kata")
	check(hira.size() == 21 and kata.size() == 12, "21 hiragana + 12 katakana stages (%d + %d)" % [hira.size(), kata.size()])
	var shape := ""
	for L in hira: shape += {"normal": "n", "boss": "B", "ultimate": "U"}[L.type]
	check(shape == "nnnBnnnBnnnBnnnBnnnBU", "hiragana: 5 zones x (3 stages + boss) + ultimate (%s)" % shape)
	shape = ""
	for L in kata: shape += {"normal": "n", "boss": "B", "ultimate": "U"}[L.type]
	check(shape == "nnnBnnnBnnnU", "katakana follows KATAKANA_STAGES (nnnB nnnB nnn U) (%s)" % shape)
	check(lv[0].id == "1-1" and lv[0].name == "1-1 あ行" and lv[1].id == "1-2" and lv[3].name.begins_with("1-BOSS") and lv[20].name.begins_with("究極魔王"), "neutral names: 1-1 あ行 / 1-BOSS … / 究極魔王")
	check(lv[3].rows == ["あ行", "か行", "さ行"] and lv[20].rows.size() == 26 and lv[24].rows == ["ア行", "カ行", "サ行"], "poolRows copied (1-BOSS = あかさ, ultimate = all 26 rows)")
	var kn_ok := true
	var missing_glyphs := ""
	for L in lv:
		if str(L.get("knowledge", "")).length() < 8: kn_ok = false
		for ch in str(L.knowledge) + str(L.name):
			if ch.unicode_at(0) > 0x2000 and not Assets.FONT_HUD.has_char(ch.unicode_at(0)):
				kn_ok = false; missing_glyphs += ch
	check(kn_ok, "every stage has knowledge text and the HUD font covers names + knowledge %s" % missing_glyphs)
	check(cfg.kata_lookalikes.get("シ", []).has("ツ") and cfg.kata_lookalikes.size() >= 20, "KATA_LOOKALIKES loaded (%d)" % cfg.kata_lookalikes.size())
	print("distances / counts / limits")
	var want := {"short": [15, 25, 40], "mid": [20, 35, 55], "long": [30, 50, 75]}
	var cnt_ok := true
	for d in want:
		if LevelDB.effective(cfg, lv, 0, d).target_correct != want[d][0] or LevelDB.effective(cfg, lv, 3, d).target_correct != want[d][1] \
				or LevelDB.effective(cfg, lv, 20, d).target_correct != want[d][2]: cnt_ok = false
	check(cnt_ok, "required correct per distance: normal 15/20/30, boss 25/35/50, ultimate 40/55/75")
	var e := LevelDB.effective(cfg, lv, 0, "short")
	check(e.time_limit_s == 48.0 and e.star2_s == 36.0 and e.star3_s == 28.0, "1-1 短程: T_dev 15x1.6=24 -> clear 48 / 2★ 36 / 3★ 28 (%s/%s/%s)" % [e.time_limit_s, e.star2_s, e.star3_s])
	e = LevelDB.effective(cfg, lv, 3, "long")
	check(e.time_limit_s == 180.0 and e.star2_s == 135.0 and e.star3_s == 104.0, "1-BOSS 長程: 50x1.8=90 -> 180 / 135 / 104 (%s/%s/%s)" % [e.time_limit_s, e.star2_s, e.star3_s])
	e = LevelDB.effective(cfg, lv, 20, "mid")
	check(e.time_limit_s == 198.0 and e.star2_s == 149.0 and e.star3_s == 114.0, "ultimate 中程: 55x1.8=99 -> 198 / 149 / 114 (ceil) (%s/%s/%s)" % [e.time_limit_s, e.star2_s, e.star3_s])
	check(bool(cfg.limit_formula.provisional), "limits marked provisional in config")
	print("voices / katakana lock")
	var miss_all := {}
	var locked := []
	var voices_ok := true
	for i in lv.size():
		var E := LevelDB.effective(cfg, lv, i, "short")
		for k in E.missing_voice: miss_all[k] = true
		if E.voice_locked: locked.append(E.id)
		for r in E.romaji:
			if not LevelDB.has_voice(r): voices_ok = false
	check(voices_ok, "every askable kana has a preloaded voice clip")
	check(miss_all.keys().all(func(k): return "ぢづヂヅ".contains(k)), "only ぢ/づ/ヂ/ヅ lack a clip (dropped from questions): %s" % str(miss_all.keys()))
	check(locked.is_empty(), "no stage needs locking for missing voices (katakana reuse the same romaji clips) %s" % str(locked))
	var LK := lv.duplicate(true)
	LK[1]["rows"] = ["ヴ行"]   # simulate a row with no clips
	check(LevelDB.effective(cfg, LK, 1, "short").voice_locked, "stage with <3 voiced kana is voice-locked")
	print("review / lookalikes / same sound")
	check(LevelDB.effective(cfg, lv, 0, "short").review_kana.is_empty(), "1-1 has no review kana")
	var e2 := LevelDB.effective(cfg, lv, 2, "short")
	check("".join(e2.review_kana) == "あいうえおかきくけこ" and "".join(e2.kana) == "さしすせそ", "1-3 さ行 reviews あ行+か行 (learned rows)")
	check(LevelDB.effective(cfg, lv, 21, "short").review_kana.is_empty(), "片1-1 has no review (katakana learned list is separate)")
	g.set_level(2); g.reset_run(); g.start_run()
	var rv := 0
	var tot := 0
	var pool_ok := true
	while tot < 400:
		var r = g.active_row()
		if r.review: rv += 1
		for x in r.kana:
			if not (e2.kana.has(x) or e2.review_kana.has(x)): pool_ok = false
		tot += 1
		g.correct = 0
		_answer(g, "correct")
	check(pool_ok, "rows only use current + learned kana")
	check(rv > tot * 0.12 and rv < tot * 0.28, "~20%% review questions (%d / %d)" % [rv, tot])
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var ss_ok := true
	var look_hit := 0
	for i in 300:
		var r := Rules.make_row_ex(["わ","を","ん","お","あ"], "を" if i % 2 == 0 else "お", "", -1, rng, 3, {}, cfg.same_sound)
		if r.kana.has("を") and r.kana.has("お"): ss_ok = false
		var k := Rules.make_row_ex(["シ","ツ","ソ","ン","ア","イ"], "シ", "", -1, rng, 3, cfg.kata_lookalikes, cfg.same_sound)
		if k.kana.has("ツ") or k.kana.has("ン") or k.kana.has("ソ"): look_hit += 1
	check(ss_ok, "お / を (same sound) never share a row")
	check(look_hit == 300, "katakana rows put a lookalike trap next to the target (シ -> ツ/ン/ソ)")
	print("boss shield")
	g.set_level(3); g.reset_run(); g.start_run()
	check(g.lvl.target_correct == 25 and g.shield_thresholds == [0.3, 0.6] and g.break_chain == 2, "1-BOSS 短程: 25 correct, shields at 30%%/60%%, break chain 2")
	while g.correct < 8: _answer(g, "correct")
	check(g.boss_shield_up and g.lbl_notice.text == "護盾展開！", "shield rises at ceil(0.3x25)=8 correct")
	_answer(g, "correct")
	check(g.correct == 8 and g.break_progress == 1, "correct while shielded does not count toward progress")
	_answer(g, "wrong")
	check(g.break_progress == 0 and g.boss_shield_up, "wrong hit resets the break chain")
	_answer(g, "correct"); _answer(g, "correct")
	check(not g.boss_shield_up and g.shields_broken == 1 and g.correct == 8, "2 in a row break the shield")
	while g.correct < 15: _answer(g, "correct")
	check(g.boss_shield_up and g.shield_phase == 2, "second shield at ceil(0.6x25)=15")
	g.set_level(0); g.reset_run()
	check(g.shield_thresholds.is_empty(), "normal stages have no shield")
	g.set_distance("long", false); g.set_level(3)
	check(g.lvl.target_correct == 50, "shield phases follow the chosen distance count (長程 50 -> 15 / 30)")
	g.set_distance("short", false); g.set_level(0)

func save_tests() -> void:
	print("save / unlock / per-distance records / points")
	var cfg: Dictionary = GameConfig.load_config()
	var lv: Array = GameConfig.levels(cfg)
	var sd = SaveData.new(); sd.path = "user://selftest_save2.json"; sd.clear_all()
	check(sd.is_unlocked(lv, 0) and not sd.is_unlocked(lv, 1), "fresh save: only 1-1 open")
	var r1: Dictionary = sd.record("1-1", "long", 2, 40.0)
	check(r1.first_clear and r1.new_stars == 2 and r1.better, "first clear recorded at 長程")
	check(sd.is_unlocked(lv, 1), "clearing at any distance (長程) unlocks 1-2")
	check(not sd.get_record("1-1", "short").cleared and sd.get_record("1-1", "long").cleared, "records are per distance")
	var r2: Dictionary = sd.record("1-1", "long", 1, 45.0)
	check(not r2.better and not r2.first_clear and r2.new_stars == 0, "worse run does not count as better")
	check(int(sd.get_record("1-1", "long").best_stars) == 2 and is_equal_approx(float(sd.get_record("1-1", "long").best_time), 40.0), "best kept after worse run")
	var r3: Dictionary = sd.record("1-1", "long", 3, 31.3)
	check(r3.better and r3.new_stars == 1, "better run: +1 new star")
	sd.record("1-1", "short", 1, 50.0)
	check(int(sd.get_record("1-1", "short").best_stars) == 1 and int(sd.get_record("1-1", "long").best_stars) == 3, "short and long bests independent")
	var P: Dictionary = cfg.points
	check(Rules.points_for(true, 0, 1.0, P) == 10 and Rules.points_for(true, 3, 1.0, P) == 25, "points: first clear 10, +5 per new star (3★ first = 25)")
	check(Rules.points_for(false, 0, 1.0, P) == 2 and Rules.points_for(false, 1, 1.0, P) == 7, "points: repeat clear 2 (+5 if a new star)")
	check(Rules.points_for(true, 2, 1.5, P) == 30 and Rules.points_for(false, 0, 1.5, P) == 3 and Rules.points_for(true, 3, 2.2, P) == 55 and Rules.points_for(false, 0, 2.2, P) == 4, "multipliers 中x1.5 長x2.2, round half up (2x2.2=4.4->4, 2x1.5=3)")
	sd.add_points(25); sd.add_points(3)
	sd.set_setting("distance", "mid")
	check(sd.save_file(), "save written")
	var sd2 = SaveData.new(); sd2.path = sd.path; sd2.load_file()
	check(int(sd2.get_record("1-1", "long").best_stars) == 3 and is_equal_approx(float(sd2.get_record("1-1", "long").best_time), 31.3) and sd2.is_unlocked(lv, 1), "save reloads per-distance records")
	check(sd2.points() == 28 and sd2.get_setting("distance") == "mid", "total points + distance choice persist")
	check(not sd2.is_unlocked(lv, 21), "片1-1 locked until 1-BOSS cleared")
	sd2.record("1-BOSS", "short", 1, 80.0)
	check(sd2.is_unlocked(lv, 21), "片1-1 opens after 1-BOSS (unlock_after)")
	var f := FileAccess.open("user://selftest_v1.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "levels": {"level_01": {"cleared": true, "best_stars": 3, "best_time": 31.3}, "level_02": {"cleared": true, "best_stars": 2, "best_time": 50.0}}, "settings": {"speed_mode": "step"}}))
	f.close()
	var sd3 = SaveData.new(); sd3.path = "user://selftest_v1.json"; sd3.load_file()
	check(sd3.migrated_from == 1 and sd3.get_record("1-1", "short").cleared and sd3.get_record("1-2", "short").cleared and int(sd3.get_record("1-1", "short").best_stars) == 0, "v1 save migrated: L1/L2 -> 1-1/1-2 cleared at 短程, stars/times reset")
	check(sd3.is_unlocked(lv, 2) and not sd3.is_unlocked(lv, 3) and sd3.get_setting("speed_mode") == "step" and sd3.points() == 0, "migration keeps unlocks + settings, no points")

func distance_tests(g) -> void:
	print("distance toggle")
	g.save.clear_all(); g.save.save_file()
	g.set_distance("short"); g.show_select()
	check(g.btn_distance.text.contains("短程"), "level select shows 距離：短程")
	g.btn_distance.pressed.emit()
	check(g.distance == "mid" and g.btn_distance.text.contains("中程"), "toggle -> 中程")
	var sd = SaveData.new(); sd.path = g.save.path; sd.load_file()
	check(sd.get_setting("distance") == "mid", "distance choice saved")
	g.btn_distance.pressed.emit(); g.btn_distance.pressed.emit()
	check(g.distance == "short", "toggle cycles 短程 -> 中程 -> 長程 -> 短程")
	g.btn_distance.pressed.emit()
	g.choose_level(0)
	check(g.lvl.target_correct == 20 and g.lvl.time_limit_s == 64.0, "中程 1-1: 20 correct, clear 64 s")
	g.start_run()
	while g.correct < 20: _answer(g, "correct")
	g._tick(0.0)
	check(g.state == g.State.CLEARED and g.lbl_result.text.contains("中程") and g.lbl_result.text.contains("獲得點數"), "results show distance + 獲得點數")
	var first_pts: int = g.last_points
	check(first_pts == Rules.points_for(true, g.last_record.new_stars, 1.5, g.cfg.points) and g.save.points() == first_pts, "first clear points x1.5 saved as total (%d)" % first_pts)
	check(g.save.get_record("1-1", "mid").cleared and not g.save.get_record("1-1", "short").cleared, "clear recorded under 中程 only")
	check(g.can_go_next(), "中程 clear unlocks 1-2")
	g.reset_run(); g.start_run(); g.elapsed = 0.0
	while g.correct < 20: _answer(g, "correct")
	g.penalty = 63.0   # slower than any star improvement, still inside the limit
	g._tick(0.0)
	check(g.state == g.State.CLEARED and g.last_points == 3 and g.save.points() == first_pts + 3, "repeat clear (no new star) = 2 x1.5 -> 3 points (%d)" % g.last_points)
	check(g.lbl_result.text.contains("總點數 %d" % g.save.points()), "results show total points")
	var g2 = load("res://scenes/main.tscn").instantiate()
	g2.save_path = g.save.path; g2.skip_select = true
	root.add_child(g2)
	check(g2.distance == "mid", "new session restores last distance (中程)")
	root.remove_child(g2); g2.free()
	g.set_distance("short"); g.set_level(0)
	g.save.clear_all(); g.save.save_file()

func results_tests(g) -> void:
	print("results / level select")
	g.save.clear_all()
	g.show_select()
	check(g.state == g.State.SELECT and g.select_box.visible, "level select shown")
	check(g.level_buttons.size() >= 2 and not g.level_buttons[0].disabled and g.level_buttons[1].disabled, "level 2 locked before clearing level 1")
	g.choose_level(1)
	check(g.state == g.State.SELECT, "locked level cannot be started")
	g.choose_level(0)
	check(g.state == g.State.READY and g.level_index == 0, "choosing level 1 goes to ready")
	g.start_run()
	while g.correct < int(g.lvl.target_correct):
		_answer(g, "correct")
	g._tick(0.0)
	check(g.state == g.State.CLEARED and g.results_box.visible, "results panel shown on clear")
	check(g.lbl_result.text.contains("小知識") and g.lbl_result.text.contains("獲得點數 +"), "results show knowledge + points")
	check(g.btn_next.visible and not g.btn_next.disabled and g.btn_select.visible, "「下一關」enabled after clearing level 1")
	check(g.save.get_record("1-1", g.distance).cleared, "clear saved")
	g.btn_next.pressed.emit()
	check(g.level_index == 1 and g.state == g.State.READY, "「下一關」goes to level 2")
	g.set_level(g.levels.size() - 1); g.reset_run()
	g.start_run()
	g.elapsed = 999.0
	g._tick(0.0)
	check(g.state == g.State.FAILED and g.results_box.visible and g.btn_next.visible == false, "last level: no 「下一關」")
	g.btn_select.pressed.emit()
	check(g.state == g.State.SELECT and not g.level_buttons[1].disabled, "「回選關」returns; 1-2 now open")
	check(g.level_buttons.size() == 21 and g.btn_tab_hira.button_pressed, "平假名 tab lists 21 stages")
	g.btn_tab_kata.pressed.emit()
	check(g.level_buttons.size() == 12 and g.level_buttons[0].disabled and g.level_buttons[0].text.contains("鎖定"), "片假名 tab lists 12 stages, locked at start")
	g.btn_tab_hira.pressed.emit()
	g.set_level(0)

func layout_check(g, sz: Vector2i) -> void:
	var vr: Rect2 = g.get_viewport().get_visible_rect()
	var cx := vr.size.x * 0.5
	var tag := "%dx%d" % [sz.x, sz.y]
	var centered := true
	var inside := true
	var bad := []
	for item in [["hint", g.lbl_hint], ["notice", g.lbl_notice], ["float", g.lbl_float], ["center", g.lbl_center],
			["results", g.results_box.get_child(0)], ["select", g.select_box.get_child(0)], ["pause", g.pause_box.get_child(0)], ["settings", g.settings_box.get_child(0)],
			["speed", g.lbl_speed], ["combo", g.lbl_combo], ["boss", g.lbl_boss]]:
		var rc: Rect2 = item[1].get_global_rect()
		if absf(rc.get_center().x - cx) > 2.0:
			centered = false; bad.append(item[0])
	for item in [g.lbl_time, g.lbl_count, g.lbl_speed, g.lbl_combo, g.lbl_hint, g.results_box.get_child(0), g.select_box.get_child(0),
			g.pause_box.get_child(0), g.btn_accel, g.btn_brake, g.btn_pause, g.btn_voice, g.hearts_box, g.btn_lock, g.settings_box.get_child(0)]:
		var rc: Rect2 = item.get_global_rect()
		if rc.position.x < -1 or rc.position.y < -1 or rc.end.x > vr.size.x + 1 or rc.end.y > vr.size.y + 1:
			inside = false; bad.append(str(item.name) + " " + str(item.get_global_rect()))
	check(centered, "%s: centered text/panels are centered (canvas %.0fx%.0f) %s" % [tag, vr.size.x, vr.size.y, str(bad)])
	check(inside, "%s: all HUD/panels inside the screen %s" % [tag, str(bad)])
	check(g.lbl_center.get_global_rect().size.x >= vr.size.x - 60, "%s: info text spans the full width" % tag)
	var a: Rect2 = g.btn_accel.get_global_rect(); var b: Rect2 = g.btn_brake.get_global_rect()
	var p: Rect2 = g.btn_pause.get_global_rect(); var v: Rect2 = g.btn_voice.get_global_rect()
	check(a.get_center().x > vr.size.x * 0.5 and a.end.y > vr.size.y * 0.75 and b.get_center().x < vr.size.x * 0.5 and b.end.y > vr.size.y * 0.75, "%s: 加速 bottom-right, 煞車 bottom-left" % tag)
	var h: Rect2 = g.hearts_box.get_global_rect()
	check(h.get_center().x < vr.size.x * 0.5 and not h.intersects(p) and not h.intersects(v) and not h.intersects(g.lbl_time.get_global_rect()) and not h.intersects(g.lbl_count.get_global_rect()), "%s: HP bar top-left, clear of time/count/pause %s t%s c%s p%s" % [tag, str(h), str(g.lbl_time.get_global_rect()), str(g.lbl_count.get_global_rect()), str(p)])
	var sc: Rect2 = g.select_scroll.get_global_rect()
	var inner: Control = g.select_scroll.get_child(0)
	check(sc.position.y >= -1 and sc.end.y <= vr.size.y + 1 and inner.size.y > sc.size.y, "%s: level list scrolls inside the screen (list %.0f > view %.0f)" % [tag, inner.size.y, sc.size.y])
	var lk: Rect2 = g.btn_lock.get_global_rect()
	var mn := minf(vr.size.x, vr.size.y)
	check(a.size.x >= mn * 0.27 and b.size.x >= mn * 0.23 and p.size.x >= mn * 0.12, "%s: touch buttons scale with short side (加速 %.0f of %.0f)" % [tag, a.size.x, mn])
	check(not lk.intersects(a) and not lk.intersects(b) and not lk.intersects(p) and not lk.intersects(v) and not lk.intersects(g.lbl_speed.get_global_rect()) and not lk.intersects(g.lbl_combo.get_global_rect()), "%s: 鎖定 clear of other buttons and HUD" % tag)
	check(not a.intersects(g.lbl_speed.get_global_rect()) and not b.intersects(g.lbl_speed.get_global_rect()) and not a.intersects(g.lbl_combo.get_global_rect()) and not b.intersects(g.lbl_combo.get_global_rect()), "%s: speed/combo text clear of buttons" % tag)
	check(p.position.y < vr.size.y * 0.2 and p.get_center().x > vr.size.x * 0.75 and not p.intersects(v) and not a.intersects(b), "%s: pause/speaker top-right, buttons don't overlap" % tag)

func _layout_prepare(g) -> void:
	g.set_level(0); g.reset_run()
	g.lbl_hint.text = "ka"; g._notice("聽音模式"); g.lbl_float.text = "○"; g.lbl_combo.text = "20 連擊"
	g.lbl_result.text = "CLEAR!  ★★★\n1-BOSS あ・か・さ行綜合  長程\n小知識：%s\n" % g.levels[3].knowledge + "CLEAR!\n★★★\n\nTime 31.30 s\n(run 31.30 + penalty 0.0)\nwrong 0   miss 0\nbest combo 20\n新紀錄！"
	g.results_box.visible = true
	g.show_select()
	g.lbl_boss.text = "護盾 連續答對 1 / 2"; g.lbl_boss.visible = true
	g.results_box.visible = true
	g.pause_box.visible = true
	g.settings_box.visible = true
	g.btn_lock.visible = true

var total_frames := 0
var _relayout := true

func _process(_delta: float) -> bool:
	frames += 1
	total_frames += 1
	if total_frames > 60 * 900 or (reg_game != null and not reg_game.has_method("reset_run")):
		printerr("ABORT: game script failed to load or test ran too long")
		quit(2)
		return true
	if phase == "unit":
		regression_tests()
		level_tests(reg_game)
		save_tests()
		distance_tests(reg_game)
		results_tests(reg_game)
		print("layout")
		_layout_prepare(reg_game)
		phase = "layout"
		layout_wait = 0
		root.size = SIZES[0]
		return false
	if phase == "layout":
		layout_wait += 1
		if layout_wait == 2 and _relayout:
			_layout_prepare(reg_game)   # rebuild the level list for the new canvas size
			_relayout = false
			layout_wait = 0
			return false
		if layout_wait < 3:
			return false
		layout_check(reg_game, SIZES[layout_i])
		layout_i += 1
		layout_wait = 0
		if layout_i < SIZES.size():
			root.size = SIZES[layout_i]
			_relayout = true
			return false
		root.size = Vector2i(720, 1280)
		root.remove_child(reg_game)
		reg_game.free()
		reg_game = null
		phase = "auto"
		auto_i = 0
		_start_autopilot()
		frames = 0
		return false
	if frames == 3:
		game.start_run()
	if frames < 3:
		return false
	if game.state == game.State.CLEARED or game.state == game.State.FAILED or frames > 60 * 120:
		var n := "%s (%s)" % [game.level_id, game.speed_mode]
		var tgt: int = int(game.lvl.target_correct) + game.shields_broken * game.break_chain
		check(game.state == game.State.CLEARED, "autopilot clears level %s (clock %.2f s, stars %d, correct %d, wrong %d, miss %d)" % [n, game.clock(), Rules.stars_for(game.clock(), game.lvl), game.correct, game.wrong, game.missed])
		check(game.wrong == 0 and game.missed == 0, "autopilot L%s makes no mistakes" % n)
		check(game.logger.entries.size() == tgt, "dev logger recorded %d questions (incl. %d shield-break answers)" % [tgt, game.shields_broken * game.break_chain])
		if game.shield_thresholds.size() > 0:
			check(game.shields_broken == game.shield_thresholds.size(), "autopilot broke both boss shields")
		check(FileAccess.file_exists(DevLogger.RUNS_FILE), "timing CSV written")
		if game.speed_mode != AUTO_RUNS[auto_i][1]:
			check(false, "autopilot mode forced")
		if auto_i + 1 < AUTO_RUNS.size():
			root.remove_child(game); game.free()
			auto_i += 1
			_start_autopilot()
			frames = 0
			return false
		print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
		root.remove_child(game)
		game.free()
		quit(1 if fails > 0 else 0)
		return true
	return false
