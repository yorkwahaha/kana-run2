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
	shop_tests(g)
	achievement_tests(g)
	vfx_tests(g)
	endless_mode_tests(g)

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
var shutdown_msec := 0
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(390, 844), Vector2i(844, 390), Vector2i(720, 1280), Vector2i(2560, 600)]

func _initialize() -> void:
	unit_tests()
	# nodes only get _ready() once the main loop runs, so the scene-based
	# tests start from _process (frame 1).
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute("user://selftest_save.json" + suffix)
	reg_game = load("res://scenes/main.tscn").instantiate()
	reg_game.rng_seed = 3
	reg_game.save_path = "user://selftest_save.json"
	reg_game.skip_title = true
	reg_game.instant_transitions = true
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
	check(g.music.stream is AudioStreamMP3 and g.music.stream.loop, "the default BGM loops during a long run")
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
	check(g.lbl_result_heading.text == "體力耗盡" and g.results_box.visible, "results show 「體力耗盡」")
	check(not g.save.cleared_any("1-1"), "hp_out is not saved as a clear")
	g.hp_changed.disconnect(cb)
	g.reset_run(); g.start_run(); g.elapsed = 999.0; g._tick(0.0)
	check(g.fail_reason == "time_up" and g.lbl_result_heading.text == "時間到", "time-up shows 「時間到」 (distinct reason)")
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
	check(g.ctrl.locked and g.btn_lock.visible and g.lbl_lock_kmh.text == str(roundi(g.ctrl.lock_kmh())) and g.lbl_speed.text.ends_with("km/h"), "F locks and the lock badge shows the set speed separately from current speed")
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
	var pause_race: Button = g.btn_mode_pause_race
	var pause_step: Button = g.btn_mode_pause_step
	check(pause_race.is_visible_in_tree() and pause_step.is_visible_in_tree() and pause_step.button_pressed and not pause_race.button_pressed, "pause exposes two modes and selects only the current mode")
	var step_style := pause_step.get_theme_stylebox("normal") as StyleBoxTexture
	check(step_style != null and step_style.texture.resource_path.ends_with("mode_step_active.png"), "pause highlights the active step mode")
	check(step_style == pause_step.get_theme_stylebox("hover") and step_style == pause_step.get_theme_stylebox("hover_pressed"), "pause step keeps its active art during hover and hover-press")
	pause_race.pressed.emit()
	check(g.speed_mode == "race" and g.ctrl.mode == "race" and g.state == g.State.PAUSED and not g.ctrl.locked, "pause-menu switch to 賽車 applies (still paused, unlocked)")
	var race_style := pause_race.get_theme_stylebox("hover_pressed") as StyleBoxTexture
	check(pause_race.button_pressed and not pause_step.button_pressed and race_style != null and race_style.texture.resource_path.ends_with("mode_race_active.png"), "pause highlights only the chosen race mode even with a pointer over it")
	g.ctrl.toggle_lock()
	pause_race.pressed.emit()
	check(g.ctrl.locked, "reselecting the active race mode preserves cruise lock")
	pause_step.pressed.emit()
	check(g.speed_mode == "step" and is_equal_approx(g.ctrl.target_kmh(), 30.0), "switch to 點放 mid-run: target = current speed rounded (30)")
	check(not g.lbl_hint.visible, "romaji hint hidden behind pause menu")
	g.resume()
	check(g.lbl_hint.visible, "hint back after resume")
	# settings screen
	g.show_select()
	check(g.btn_settings != null and g.btn_settings.text.contains("點放"), "level select has 「設定」 showing mode")
	g.btn_settings.pressed.emit()
	check(g.settings_box.visible and not g.select_box.visible and g.btn_mode_step.button_pressed, "settings panel opens, current mode selected")
	check(g.btn_mode_step.button_group != null and g.btn_mode_step.button_group == g.btn_mode_race.button_group and not g.btn_mode_step.button_group.allow_unpress, "settings speed choices are exclusive and keep one selected")
	check(g.lbl_settings_mode.text.contains("點放"), "settings heading names the selected speed mode in text")
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
	check(DevLogger.RUNS_FILE.ends_with("runs_v5.csv") and csv[0].contains(",mode,distance,target,points,")
		and csv[-1].contains(",step,%s," % g.distance), "runs_v5.csv preserves mode + distance columns")
	g.dev_mode = false
	g.set_speed_mode("race")
	g.save.clear_all(); g.save.save_file()
	g.set_level(0)

func shop_tests(g) -> void:
	print("shop & vanity upgrades")
	var s: RefCounted = g.save
	s.clear_all()
	check(s.points() == 0, "shop starts at 0 points")
	check(s.get_equipped_aura() == "default", "default aura equipped by default")
	check(s.is_aura_unlocked("default"), "default aura unlocked by default")
	check(not s.is_aura_unlocked("cyan"), "cyan aura locked by default")
	check(not s.unlock_aura("cyan", 100), "cannot unlock aura with insufficient points")
	s.add_points(250)
	check(s.points() == 250, "points added successfully")
	check(s.unlock_aura("cyan", 100), "unlocks cyan aura with sufficient points")
	check(s.points() == 150, "points deducted after purchase")
	check(s.is_aura_unlocked("cyan"), "cyan aura is now unlocked")
	s.equip_aura("cyan")
	check(s.get_equipped_aura() == "cyan", "equipped aura changes to cyan")

	# Tactical upgrades purchase
	check(s.get_upgrade_level("hp_level") == 0, "HP upgrade starts at Lv.0")
	check(s.buy_upgrade("hp_level", 2, 150), "buys HP upgrade Lv.1 for 150 pts")
	check(s.points() == 0, "points reduced to 0")
	check(s.get_upgrade_level("hp_level") == 1, "HP upgrade is now Lv.1")
	check(not s.buy_upgrade("hp_level", 2, 300), "cannot buy HP Lv.2 with 0 points")
	s.add_points(500)
	check(s.buy_upgrade("shield_level", 2, 250), "buys shield upgrade Lv.1 for 250 pts")
	check(s.get_upgrade_level("shield_level") == 1, "shield upgrade is now Lv.1")

	# In-game integration
	g.reset_run()
	check(g.max_hp == 120 and g.hp == 120, "HP upgrade (+20) raises max HP to 120 on reset_run")
	check(g.shield == 1, "starting shield upgrade grants 1 shield on reset_run")
	check(g.lbl_shield.text == "盾1", "shield pip displays 盾1 on HUD")
	# Shield blocks damage
	g.take_damage(35)
	check(g.shield == 0, "first hit breaks starting shield")
	check(g.hp == 120, "starting shield completely prevented HP loss")
	check(g.lbl_shield.text == "", "shield HUD text clears when 0")

	# Armor damage reduction upgrade
	check(s.buy_upgrade("armor_level", 2, 200), "buys armor upgrade Lv.1 for 200 pts")
	check(s.get_upgrade_level("armor_level") == 1, "armor upgrade is now Lv.1")
	g.reset_run()
	check(is_equal_approx(g.damage_reduction, 15.0), "armor upgrade sets damage reduction to 15%")
	# take 35 damage with 1 shield (from shield Lv.1):
	g.take_damage(35) # absorbed by shield
	g.take_damage(35) # reduced by 15%: 35 * 0.85 = 29.75 -> 30
	check(g.hp == 90, "armor Lv.1 reduces 35 damage to 30 (120 -> 90)")

	# Shop UI dialog tests
	g.show_select()
	check(g.btn_shop != null and is_instance_valid(g.btn_shop), "btn_shop exists in level select")
	g.btn_shop.pressed.emit()
	check(g.shop_box.visible and not g.select_box.visible, "clicking btn_shop opens shop dialog")
	check(g.lbl_shop_points.text.contains("持有點數"), "shop displays player's current points")
	g.btn_shop_back.pressed.emit()
	check(g.select_box.visible and not g.shop_box.visible, "clicking btn_shop_back closes shop")

	# Joypad Back / Escape closes shop
	g.show_shop()
	check(g.shop_box.visible, "re-opened shop")
	_key(g, KEY_ESCAPE, true)
	check(not g.shop_box.visible and g.select_box.visible, "Escape closes shop and returns to select")
	g.show_shop()
	var ev_b := InputEventJoypadButton.new()
	ev_b.button_index = JOY_BUTTON_B
	ev_b.pressed = true
	g._unhandled_input(ev_b)
	check(not g.shop_box.visible and g.select_box.visible, "Joypad B closes shop and returns to select")

	# Cleanup test save
	s.clear_all()
	g.set_max_hp_bonus(0)
	g.set_damage_reduction(0.0)
	g.reset_run()

func achievement_tests(g) -> void:
	print("achievements & milestones")
	if g.toast_tween != null:
		g.toast_tween.kill()
	g.toast_queue.clear()
	g.achievement_toast.visible = false
	var s: RefCounted = g.save
	s.clear_all()
	check(s.achievement_count() == 0, "achievements start at 0 unlocked")
	check(s.unclaimed_achievement_count() == 0, "0 unclaimed achievements at start")
	check(not s.is_achievement_unlocked("first_step"), "first_step locked initially")
	check(not s.is_achievement_claimed("first_step"), "first_step unclaimed initially")

	# Trigger unlock via check_achievement
	g.check_achievement("first_step")
	check(s.is_achievement_unlocked("first_step"), "first_step unlocked after check_achievement")
	check(not s.is_achievement_claimed("first_step"), "first_step unlocked but remains unclaimed")
	check(s.achievement_count() == 1, "unlocked achievement count is 1")
	check(s.unclaimed_achievement_count() == 1, "unclaimed achievement count is 1")
	check(s.points() == 0, "points are not awarded immediately upon unlock")
	check(g.achievement_toast != null and g.achievement_toast.visible, "achievement toast appears on unlock")
	var toast_title: String = g.toast_lbl_name.text if g.toast_lbl_name != null else ""
	check(toast_title.contains("初試身手"), "toast displays achievement title")

	# Claiming reward
	check(s.claim_achievement("first_step", 50), "first claim succeeds")
	check(s.is_achievement_claimed("first_step"), "first_step is now claimed")
	check(s.unclaimed_achievement_count() == 0, "unclaimed count drops to 0 after claim")
	check(s.points() == 50, "claim_achievement awards points (+50)")
	check(not s.claim_achievement("first_step", 50), "cannot claim the same achievement twice")
	check(s.points() == 50, "points unchanged after redundant claim attempt")

	# Combo milestone trigger
	g.set_level(0); g.reset_run()
	g._set_combo(10)
	check(s.is_achievement_unlocked("combo_10"), "reaching 10 combo unlocks combo_10 achievement")
	check(not s.is_achievement_claimed("combo_10"), "combo_10 is unclaimed")

	# Achievements UI dialog tests
	g.show_select()
	check(g.btn_achievements != null and is_instance_valid(g.btn_achievements), "btn_achievements exists in level select")
	g.btn_achievements.pressed.emit()
	check(g.achievements_box.visible and not g.select_box.visible, "clicking btn_achievements opens dialog")
	check(g.lbl_achievements_count.text.contains("達成進度"), "dialog shows achievement progress")

	# Claim all button in dialog
	check(g.btn_claim_all != null and is_instance_valid(g.btn_claim_all), "btn_claim_all exists")
	g.btn_claim_all.pressed.emit()
	check(s.is_achievement_claimed("combo_10"), "btn_claim_all claims unclaimed achievements")
	check(s.points() == 50 + 50, "points increased by combo_10 reward (+50)")
	check(s.unclaimed_achievement_count() == 0, "all achievements are now claimed")

	# Close dialog via back button
	g.btn_achievements_back.pressed.emit()
	check(g.select_box.visible and not g.achievements_box.visible, "btn_achievements_back closes dialog")

	# Joypad Back / Escape closes achievements dialog
	g.show_achievements()
	check(g.achievements_box.visible, "re-opened achievements dialog")
	_key(g, KEY_ESCAPE, true)
	check(not g.achievements_box.visible and g.select_box.visible, "Escape closes achievements and returns to select")
	g.show_achievements()
	var ev_b := InputEventJoypadButton.new()
	ev_b.button_index = JOY_BUTTON_B
	ev_b.pressed = true
	g._unhandled_input(ev_b)
	check(not g.achievements_box.visible and g.select_box.visible, "Joypad B closes achievements and returns to select")

	# Cleanup test save
	s.clear_all()
	s.save_file()
	if g.toast_tween != null:
		g.toast_tween.kill()
	g.toast_queue.clear()
	g.achievement_toast.visible = false
	g.reset_run()

func vfx_tests(g) -> void:
	print("visual juice & vfx (speedlines, shockwave, shatter)")
	g.set_level(0); g.reset_run()
	check(g.speedlines_rect != null and is_instance_valid(g.speedlines_rect), "speedlines overlay exists on fx_layer")
	check(g.speedlines_mat != null and is_instance_valid(g.speedlines_mat), "speedlines shader material active")
	check(g.speedlines_intensity == 0.0, "speedlines intensity starts at 0 while stationary")

	# Speed lines ramp up at high speeds (> 24 km/h)
	g.ctrl.speed = 15.0 # 54 km/h
	g.state = g.State.RUNNING
	g._update_view(0.5)
	check(g.speedlines_intensity > 0.0, "speedlines intensify at high speed (intensity %.2f)" % g.speedlines_intensity)
	check(float(g.speedlines_mat.get_shader_parameter("intensity")) > 0.0, "shader uniform intensity updated")

	# Cruise lock tint on speedlines
	g.ctrl.locked = true
	g._update_view(0.1)
	var col: Color = g.speedlines_mat.get_shader_parameter("line_color")
	check(is_equal_approx(col.g, 1.0), "cruise lock gives electric cyan tint to speed lines")
	g.ctrl.locked = false

	# Screen flash test
	check(g.hit_flash != null and is_instance_valid(g.hit_flash), "hit_flash overlay exists")
	g._screen_flash(Color(1.0, 0.9, 0.4, 0.2), 0.12)
	check(g.hit_flash.color.a > 0.1, "screen flash triggers color tint")

	# Shockwave spawn test
	var child_cnt_before: int = g.fx_layer.get_child_count()
	g._spawn_shockwave(Vector3(0, 1.0, -10.0), Color(0.35, 0.95, 1.0), 160.0)
	check(g.fx_layer.get_child_count() > child_cnt_before, "spawn_shockwave adds shockwave node to fx_layer")

	# 2D shatter sprite spawn test
	child_cnt_before = g.fx_layer.get_child_count()
	g._spawn_shatter_sprite(Vector3(0, 1.0, -10.0))
	check(g.fx_layer.get_child_count() > child_cnt_before, "spawn_shatter_sprite adds animated shatter sprite")

	# Reset cleanup
	g.reset_run()
	check(g.speedlines_intensity == 0.0 and g.hit_flash.color.a == 0.0, "reset_run clears speedlines and hit flash")

func endless_mode_tests(g) -> void:
	print("endless survival mode")
	# 1. Save data endless records
	var ed: Dictionary = g.save.get_endless()
	check(ed is Dictionary and ed.has("best_score"), "save data has endless record structure")
	var rec: Dictionary = g.save.record_endless(1500, 420.5, 18, 12)
	check(bool(rec.get("new_high_score", false)) and g.save.get_endless_best_score() == 1500, "record_endless updates high score")

	# 2. Level select button and dialog
	g.show_select()
	check(g.btn_endless != null and is_instance_valid(g.btn_endless), "btn_endless exists in level select")
	g.btn_endless.pressed.emit()
	check(g.endless_box != null and g.endless_box.visible and not g.select_box.visible, "clicking btn_endless opens endless_box dialog")
	g.btn_endless_back.pressed.emit()
	check(not g.endless_box.visible and g.select_box.visible, "btn_endless_back returns to level select")

	# Keyboard/Joypad cancel on endless dialog
	g.show_endless()
	_key(g, KEY_ESCAPE, true)
	check(not g.endless_box.visible and g.select_box.visible, "Escape closes endless dialog")

	# 3. Starting Endless Mode
	g.start_endless()
	check(g.is_endless, "start_endless sets is_endless to true")
	check(g.level_id == "endless", "endless level_id is 'endless'")
	check(int(g.lvl.target_correct) == 999999, "endless target_correct is infinite")
	check(g.state == g.State.READY, "endless state is READY")
	g.start_run()
	check(g.state == g.State.RUNNING, "endless run starts")

	# 4. Correct answer, score and combo
	var prev_score: int = g.endless_score
	_answer(g, "correct")
	check(g.correct == 1 and g.endless_score > prev_score, "correct answer increases score and correct count in endless mode")

	# 5. Dynamic Wave progression
	g.correct = 10
	g._tick(0.016)
	check(g.endless_tier == 1, "tier advances to 1 when reaching 10 correct answers")
	check(g.ctrl.max_speed > 38.0 / 3.6, "speed ceiling increases on wave 2")

	# 6. Combo HP recovery
	g.hp = 50
	g.combo = 9
	_answer(g, "correct")
	check(g.hp == 65, "10-combo milestone heals 15 HP in endless mode")

	# 7. Miss deals damage in Endless mode
	var hp_before: int = g.hp
	_answer(g, "miss")
	check(g.hp < hp_before, "miss deals damage in endless mode")

	# 8. Game over and results
	var prev_pts: int = g.save.points()
	g.take_damage(200)
	check(g.state == g.State.FAILED, "endless mode finishes when HP drops to 0")
	check(g.results_box.visible, "results dialog is shown")
	check(g.lbl_result_heading.text == "極限挑戰結束", "results heading reflects endless finish")
	check(g.btn_retry.text == "再戰極限", "retry button text reflects endless mode")
	check(not g.btn_next.visible, "next stage button hidden in endless results")
	check(g.save.points() > prev_pts, "points awarded and stored after endless run")

	# 9. Returning to Select resets endless state
	g.show_select()
	check(not g.is_endless, "show_select resets is_endless to false")
	g.set_level(0); g.reset_run()

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
	check(not sd.record("1-1", "long", 3, 31.299).better, "same displayed clear time is not a new record")
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
	var migrated: Dictionary = sd3.get_record("1-1", "short")
	check(sd3.data.version == SaveData.VERSION and migrated.cleared and sd3.get_record("1-2", "short").cleared
		and migrated.best_stars == 0 and migrated.best_time == -1.0, "v1 save migrates to v2, preserving clears and resetting stars/time")
	check(sd3.is_unlocked(lv, 2) and not sd3.is_unlocked(lv, 3) and sd3.get_setting("speed_mode") == "step" and sd3.points() == 0, "migration keeps unlocks + settings, no points")
	var tmp_lock := FileAccess.open(sd2.path + ".tmp", FileAccess.WRITE_READ)
	sd2.add_points(1)
	var replaced: bool = sd2.save_file()
	if tmp_lock:
		tmp_lock.close()
	sd.load_file()
	check(sd.points() == (29 if replaced else 28), "failed replacement keeps old save; success installs new save")
	check(sd2.save_file() and DirAccess.rename_absolute(sd2.path, sd2.path + ".bak") == OK, "simulate interruption between save moves")
	sd.load_file()
	check(sd.points() == 29 and sd.save_file() and FileAccess.file_exists(sd.path + ".bak"), "interrupted replacement recovers backup and a successful retry retains it")
	check(DirAccess.rename_absolute(sd.path, sd.path + ".bak") == OK, "stage backup before corrupting primary save")
	f = FileAccess.open(sd.path, FileAccess.WRITE)
	f.store_string('{"version":')
	f.close()
	sd.load_file()
	check(sd.points() == 29 and sd.cleared_any("1-1") and sd.get_setting("distance") == "mid",
		"truncated primary recovers points, level clears and settings from backup")
	tmp_lock = FileAccess.open(sd.path + ".tmp", FileAccess.WRITE_READ)
	sd.add_points(1)
	replaced = sd.save_file()
	if tmp_lock:
		tmp_lock.close()
	sd2.load_file()
	check(sd2.points() == (30 if replaced else 29), "failed retry after corruption preserves the valid backup")
	var blocked = SaveData.new()
	blocked.path = "user://selftest_blocked_save.json"
	check(DirAccess.make_dir_absolute(blocked.path) == OK, "simulate blocked save destination")
	check(not blocked.save_file() and not FileAccess.file_exists(blocked.path + ".tmp"), "failed save removes its unlocked temporary file")
	DirAccess.remove_absolute(blocked.path)
	for invalid_path in [blocked.path, blocked.path + ".bak"]:
		f = FileAccess.open(invalid_path, FileAccess.WRITE)
		f.store_string("[")
		f.close()
	blocked.load_file()
	check(blocked.points() == 0 and not blocked.cleared_any("1-1") and blocked.get("unreadable"),
		"two unreadable saves fall back to default progress and expose a warning to the menu")
	DirAccess.remove_absolute(blocked.path)
	DirAccess.remove_absolute(blocked.path + ".bak")
	var logger = DevLogger.new()
	var paths := []
	for i in 3:
		logger.start("selftest_%d" % i)
		paths.append(logger.save("time_up", 0.0, 0.0, 0))
	var earliest = JSON.parse_string(FileAccess.get_file_as_string(paths[0]))
	check(paths[0] != paths[1] and paths[1] != paths[2] and earliest is Dictionary and earliest.get("level") == "selftest_0",
		"rapid timing saves retain each run file")
	f = FileAccess.open(sd3.path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"version": 1, "levels": {"level_01": {"cleared": true}, "level_02": null}, "settings": null,
	}))
	f.close()
	sd3.load_file()
	check(sd3.cleared_any("1-1") and not sd3.cleared_any("1-2") and sd3.get_setting("speed_mode", "race") == "race",
		"malformed v1 entries preserve valid clears")
	f = FileAccess.open(sd3.path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"version": 2, "points": [], "settings": null,
		"levels": {
			"1-1": {"short": [], "long": {"cleared": true, "best_stars": 3, "best_time": 31.3}},
			"1-2": "bad",
			"1-3": {"mid": {"cleared": "false", "best_stars": [], "best_time": {}}},
		},
	}))
	f.close()
	sd3.load_file()
	check(sd3.cleared_any("1-1") and not sd3.cleared_any("1-2") and sd3.get_record("1-1", "short").get("best_time", -2.0) == -1.0,
		"malformed v2 records preserve valid sibling distances")
	var malformed: Dictionary = sd3.get_record("1-3", "mid")
	check(malformed.cleared == false and malformed.best_stars == 0 and malformed.best_time == -1.0,
		"malformed v2 record fields cannot unlock levels or award stars")
	check(sd3.get_setting("speed_mode", "race") == "race" and sd3.points() == 0, "malformed v2 settings and points fall back to defaults")
	timing_shield_tests()

func timing_shield_tests() -> void:
	var logger = DevLogger.new()
	logger.start("selftest_shield_metrics")
	logger.add(1, "あ", "correct", 1.0, 30.0, 1.0)
	logger.add(2, "あ", "shield", 3.0, 30.0, 4.0)
	logger.add(3, "あ", "wrong", 9.0, 30.0, 15.0)
	var path: String = logger.save("hp_out", 15.0, 15.0, 0)
	var run = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(run.counts.correct == 1 and run.counts.shield == 1 and run.questions[1].result == "shield",
		"JSON keeps stage progress and shield hits distinct")
	check(run.avg_reaction_correct_s == 1.0 and run.get("avg_reaction_success_s", 0.0) == 2.0,
		"successful reaction mean includes shield hits and excludes wrong answers")
	var rows := FileAccess.get_file_as_string(DevLogger.RUNS_FILE).strip_edges().split("\n")
	check(rows[0].ends_with(",shield_hits,avg_reaction_success_s") and rows[-1].ends_with(",1,2.000"),
		"timing CSV exposes shield hits and mean reaction across all successful answers")

func distance_tests(g) -> void:
	print("distance selection")
	g.save.clear_all(); g.save.save_file()
	g.set_distance("short"); g.show_select()
	check(g.btn_distance.text == "短程", "level select shows 短程")
	g.btn_distance.pressed.emit()
	check(g.distance == "short", "clicking selected distance keeps 短程")
	g.btn_distance.get_parent().get_child(1).pressed.emit()
	check(g.distance == "mid" and g.btn_distance.text == "中程", "clicking 中程 chooses 中程 directly")
	var sd = SaveData.new(); sd.path = g.save.path; sd.load_file()
	check(sd.get_setting("distance") == "mid", "distance choice saved")
	g.btn_distance.get_parent().get_child(2).pressed.emit()
	check(g.distance == "long", "clicking 長程 chooses 長程 directly")
	g.btn_distance.get_parent().get_child(1).pressed.emit()
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
	check(g.btn_tab_kata.disabled, "katakana tab is disabled before 1-BOSS clears")
	g.btn_tab_kata.pressed.emit()
	check(g.select_tab == "hira" and g.level_buttons.size() == 21, "locked katakana tab cannot replace the hiragana list")
	g.save.record("1-BOSS", g.distance, 1, 30.0)
	g.show_select()
	check(not g.btn_tab_kata.disabled, "katakana tab unlocks after 1-BOSS clears")
	g.btn_tab_kata.pressed.emit()
	check(g.level_buttons.size() == 12 and not g.level_buttons[0].disabled, "unlocked katakana tab lists 12 stages with the first playable")
	g.btn_tab_hira.pressed.emit()
	g.save.data.levels.erase("1-BOSS")
	g.set_level(0)

func _review_tests(g) -> void:
	print("post-run kana review")
	if not g.has_method("_open_review"):
		check(false, "finished runs offer listening practice for missed and wrong kana")
		return
	g.save.clear_all()
	g.set_level(0); g.reset_run(); g.start_run()
	var row = g.active_row()
	var missed_kana: String = row.kana[row.target]
	_answer(g, "miss")
	row = g.active_row()
	var wrong_kana: String = row.kana[row.target]
	var chosen_kana: String = row.kana[(row.target + 1) % 3]
	g.hp = 1
	_answer(g, "wrong")
	check(g.state == g.State.FAILED and g.btn_review.visible and g.lbl_result.text.contains(missed_kana),
		"failed run lists kana to practice and includes the final mistake")
	check(g.review_items[missed_kana].missed == 1 and g.review_items[wrong_kana].wrong == 1
		and g.review_items[wrong_kana].confused_with == chosen_kana,
		"review distinguishes skipped answers from the selected incorrect kana")
	var finished_save: Dictionary = g.save.data.duplicate(true)
	var finished_clock: float = g.clock()
	g.result_time = 1.0
	_menu_key(KEY_ENTER)
	check(g.review_box.visible and not g.results_box.visible and g.voice.playing and g.voice.stream == Assets.VOICE[g._romaji(missed_kana)],
		"Enter on the focused result action opens practice and plays the first review kana")
	if not g.review_box.visible:
		g.show_select()
		return
	var wrong_button: Button = g.review_choices.filter(func(b): return b.text != missed_kana)[0]
	wrong_button.pressed.emit()
	check(not g.lbl_review_feedback.text.contains(missed_kana) and g.voice.playing,
		"first incorrect practice answer replays sound without revealing the answer")
	wrong_button.pressed.emit()
	check(g.lbl_review_feedback.text.contains(missed_kana) and g.btn_review_next.disabled,
		"second incorrect practice answer supplies corrective feedback without advancing")
	g.voice.stop()
	g.btn_review_replay.pressed.emit()
	check(g.voice.playing, "review audio can be replayed without changing the item")
	var correct_button: Button = g.review_choices.filter(func(b): return b.text == missed_kana)[0]
	correct_button.pressed.emit()
	check(not g.btn_review_next.disabled, "choosing the correct kana unlocks the next review item")
	g.btn_review_next.pressed.emit()
	correct_button = g.review_choices.filter(func(b): return b.text == wrong_kana)[0]
	correct_button.pressed.emit()
	g.btn_review_next.pressed.emit()
	check(g.results_box.visible and not g.review_box.visible and not g.voice.playing,
		"finishing practice returns to the original results and stops audio")
	check(g.save.data == finished_save and g.clock() == finished_clock and g.state == g.State.FAILED,
		"kana practice leaves scores, time, progression and the failed result intact")
	g.btn_retry.pressed.emit()
	check(g.review_items.is_empty(), "retry starts a new review history")
	g.start_run()
	g.elapsed = 999.0
	g._tick(0.0)
	check(not g.btn_review.visible, "results without a wrong or missed kana do not offer empty practice")
	g.show_select()

func run_rule_tests(g) -> void:
	print("run boundaries / answer logs / voice lock")
	g.save.clear_all()
	g.set_speed_mode("race", false)
	g.set_level(0); g.reset_run(); g.start_run()
	var row = g.active_row()
	var limit: float = g.lvl.time_limit_s
	g.correct = int(g.lvl.target_correct) - 1
	g.elapsed = limit - 0.05
	g.player_dist = row.dist - 0.75
	g.lane = row.target
	g.player_x = g.lane_x(g.lane)
	g.ctrl.speed = 10.0
	g.ctrl.toggle_lock()
	g._tick(0.1)
	check(g.fail_reason == "time_up" and not row.resolved and not g.save.cleared_any("1-1") and g.last_points == 0,
		"last answer reached after the deadline cannot clear or award points")

	g.reset_run(); g.start_run()
	row = g.active_row()
	g.correct = int(g.lvl.target_correct) - 1
	g.elapsed = limit - 0.05
	g.player_dist = row.dist - 0.25
	g.lane = row.target
	g.player_x = g.lane_x(g.lane)
	g.ctrl.speed = 10.0
	g.ctrl.toggle_lock()
	g._tick(0.1)
	check(g.state == g.State.CLEARED and g.save.get_record("1-1", g.distance).best_stars == 1,
		"answer reached before the deadline still clears with a star during a long frame")
	check(not g.voice.playing, "no question audio continues into results")

	g.dev_mode = true
	for outcome in ["wrong", "miss"]:
		g.reset_run(); g.start_run()
		g.hp = 1
		g.miss_damage = 1
		_answer(g, outcome)
		var j = JSON.parse_string(FileAccess.get_file_as_string(g.last_saved_path))
		check(j is Dictionary and j.outcome == "hp_out" and j.questions.size() == 1 and j.counts[outcome] == 1,
			"lethal %s is present in the saved questions and count" % outcome)
	g.dev_mode = false

	var rows_before: Array = g.levels[1].rows
	g.levels[1].rows = ["ヴ行"]
	g.show_select()
	check(not g.can_go_next(), "Next is disabled for the unlocked stage with missing voice")
	_key(g, KEY_2, true)
	check(g.state == g.State.SELECT and g.level_index == 0, "number shortcut honors the same voice lock as the stage button")
	g.levels[1].rows = rows_before
	g.set_level(0); g.show_select()

	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var distinct_sounds := true
	for i in 30:
		var r := Rules.make_row_ex(["わ", "を", "お", "あ"], "わ", "", -1, rng, 3, {}, g.same_sound)
		if r.kana.size() != 3 or (r.kana.has("お") and r.kana.has("を")):
			distinct_sounds = false
	check(distinct_sounds, "same-sound pair cannot both appear as distractors")

	g.reset_run(); g.start_run()
	row = g.active_row()
	var missed_kana: String = row.kana[row.target]
	_answer(g, "miss")
	check(g.lbl_float.text == "漏答 +1.0 秒", "miss feedback describes time added to the clock")
	row = g.active_row()
	var retry_kana: String = row.kana[row.target]
	_answer(g, "wrong")
	check(g.lbl_float.text == "答錯 +2.0 秒", "wrong feedback describes time added to the clock")
	_answer(g, "wrong")
	row = g.active_row()
	check(row.retry and row.kana[row.target] == retry_kana,
		"consecutive wrong answers keep asking the same kana")
	var deferred = g.rows[-1]
	check(g.hp == 30 and deferred.kana[deferred.target] == missed_kana,
		"a missed kana is still queued when the immediate wrong-answer retry replaces its row")
	var feedback_glyphs_ok := true
	for ch in "答錯漏秒★☆":
		feedback_glyphs_ok = feedback_glyphs_ok and Assets.FONT_HUD.has_char(ch.unicode_at(0))
	check(feedback_glyphs_ok, "HUD font contains penalty feedback and star glyphs")

	g.reset_run(); g.start_run()
	var starting_props: Array = g.props.filter(func(prop): return prop.visible)
	var starting_positions: Array = starting_props.map(func(prop): return prop.position)
	g.player_dist = 300.0
	g._update_view(0.0)
	g.reset_run()
	var restarted_props: Array = g.props.filter(func(prop): return prop.visible)
	check(not starting_positions.is_empty() and restarted_props.map(func(prop): return prop.position) == starting_positions,
		"restart restores the starting roadside after the previous run moved far ahead")
	g.show_select()

func question_rotation_tests(g) -> void:
	print("question coverage")
	var saved_seed: int = g.rng_seed
	g.rng_seed = 41
	g.set_level(0); g.reset_run(); g.start_run()
	var pool_size: int = g.lvl.kana.size()
	var visits := {}
	var covers_every_cycle := true
	for i in range(pool_size * 3):
		var row = g.active_row()
		visits[row.kana[row.target]] = true
		_answer(g, "correct")
		if (i + 1) % pool_size == 0:
			covers_every_cycle = covers_every_cycle and visits.size() == pool_size
			visits.clear()
	check(covers_every_cycle, "new lesson questions cover each kana before repeating")

	g.reset_run(); g.start_run()
	var first = g.active_row()
	var displaced = g.rows[1]
	var displaced_kana: String = displaced.kana[displaced.target]
	visits[first.kana[first.target]] = true
	_answer(g, "wrong")
	_answer(g, "correct") # Immediate correction is outside the ordinary rotation.
	for i in range(pool_size - 1):
		var row = g.active_row()
		visits[row.kana[row.target]] = true
		_answer(g, "correct")
	check(visits.size() == pool_size and visits.has(displaced_kana),
		"an immediate retry returns the displaced kana to the question rotation")

	var rng := RandomNumberGenerator.new()
	rng.seed = 36
	var preferred := {"シ": ["ツ", "ソ", "ン"]}
	var has_different_trap := false
	for i in 30:
		var row := Rules.make_row_ex(["シ", "ツ", "ソ", "ン", "ア", "イ"], "シ", "", -1, rng, 3, preferred)
		if not row.kana.has("ツ") and (row.kana.has("ソ") or row.kana.has("ン")):
			has_different_trap = true
	check(has_different_trap, "katakana distractors vary among the available lookalikes")

	g.rng_seed = saved_seed
	g.show_select()

func _menu_key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	root.push_input(ev, true)
	ev = ev.duplicate()
	ev.pressed = false
	root.push_input(ev, true)

func _menu_ui_tests(g) -> void:
	print("menu UI")
	g.set_speed_mode("step", false)
	g.reset_run()
	check(g.lbl_center.text.contains("+5") and not g.lbl_center.text.contains("都不按 = 自然減速"), "ready copy describes current step mode")
	g.set_speed_mode("race", false)
	g._update_hud()
	check(not g.btn_lock.visible, "ready hides cruise lock so it cannot cover the start instructions")
	check(is_equal_approx(g.speedo_needle.rotation_degrees, -135.0), "speedometer points to start at rest")
	var previous_max: float = g.ctrl.max_speed
	g.ctrl.max_speed = 72.0 / 3.6
	g.ctrl.speed = g.ctrl.max_speed * 0.5
	g._update_hud()
	check(is_zero_approx(g.speedo_needle.rotation_degrees), "speedometer points to middle at half the configured top speed")
	g.ctrl.speed = g.ctrl.max_speed
	g._update_hud()
	check(is_equal_approx(g.speedo_needle.rotation_degrees, 135.0), "speedometer reaches its final tick at the configured top speed")
	g.ctrl.max_speed = previous_max
	g.set_speed_mode("step", false)
	g.save.set_setting("tutorial_seen", true)
	g.show_select()
	check(root.gui_get_focus_owner() in g.level_buttons and g.select_scroll.follow_focus, "level select focuses a playable stage and scroll follows keyboard focus")
	var current_scroll: ScrollContainer = g.select_scroll
	var current_focus := root.gui_get_focus_owner()
	_menu_key(KEY_ESCAPE)
	check(g.select_scroll == current_scroll and root.gui_get_focus_owner() == current_focus, "Esc in stage select leaves scroll and focus intact")
	g.save.record("1-BOSS", g.distance, 1, 30.0)
	g.show_select()
	g.btn_tab_kata.grab_focus()
	_menu_key(KEY_ENTER)
	check(g.select_tab == "kata" and root.gui_get_focus_owner() == g.btn_tab_kata, "Enter switches script tab and keeps focus on it")
	g.btn_tab_hira.pressed.emit()
	g.save.data.levels.erase("1-BOSS")
	g.btn_settings.grab_focus()
	_menu_key(KEY_ENTER)
	check(g.settings_box.visible and root.gui_get_focus_owner() == g.btn_mode_step, "Enter opens settings and focuses current mode")
	_menu_key(KEY_1)
	check(g.settings_box.visible and g.state == g.State.SELECT, "stage shortcut does not dismiss settings")
	_menu_key(KEY_ESCAPE)
	check(not g.settings_box.visible and g.select_box.visible and root.gui_get_focus_owner() == g.btn_settings, "Esc closes settings and returns focus to its entry")
	g.choose_level(0); g.start_run(); g.pause_game()
	check(root.gui_get_focus_owner() == g.btn_resume, "pause focuses Continue")
	_menu_key(KEY_TAB)
	check(root.gui_get_focus_owner() == g.btn_mode_pause_race, "Tab navigates to the visible race mode action")
	_menu_key(KEY_ENTER)
	check(g.speed_mode == "race" and g.state == g.State.PAUSED, "Enter changes mode without resuming")
	_menu_key(KEY_ESCAPE)
	check(g.state == g.State.RUNNING and root.gui_get_focus_owner() == null, "Esc resumes and releases menu focus")
	g._finish(false, "time_up")
	check(root.gui_get_focus_owner() == g.btn_retry, "results focus Retry")
	_menu_key(KEY_ENTER)
	check(g.state == g.State.FAILED, "early Enter cannot skip results")
	g.result_time = 1.0
	_menu_key(KEY_W)
	check(g.state == g.State.FAILED and g.results_box.visible, "accelerating with W cannot dismiss results")
	_menu_key(KEY_ENTER)
	check(g.state == g.State.READY, "Enter can retry after results debounce")

func tutorial_tests(g) -> void:
	print("guided tutorial")
	if not g.has_method("start_tutorial"):
		check(false, "the first menu offers a guided tutorial")
		return
	g.save.clear_all()
	g.set_level(0)
	g.set_speed_mode("race", false)
	g.show_select()
	check(root.gui_get_focus_owner() == g.btn_tutorial, "fresh save focuses the optional tutorial")
	_menu_key(KEY_ENTER)
	check(g.is_tutorial_active() and g.state == g.State.RUNNING and g.tutorial_step == 0, "Enter starts the tutorial in the real runner")
	if not g.is_tutorial_active():
		return
	check(g.lbl_tutorial.text.contains("加速") and g.lbl_tutorial.text.contains("あ"), "first exercise identifies the target and explains acceleration")
	_tap(g, 0, g.btn_accel.get_global_rect().get_center(), true)
	g._tick(0.1)
	_tap(g, 0, g.btn_accel.get_global_rect().get_center(), false)
	check(g.player_dist > 0.0, "tutorial uses the normal touch acceleration control")
	g.elapsed = 999.0
	g._tick(0.0)
	_answer(g, "wrong")
	check(g.tutorial_step == 0 and g.state == g.State.RUNNING and g.hp == g.max_hp and g.penalty == 0.0, "practice has no deadline, damage or penalty and retries a wrong answer")
	_answer(g, "correct")
	check(g.tutorial_step == 1 and g.lbl_tutorial.text.contains("換線"), "second exercise teaches changing lanes")
	_menu_key(KEY_LEFT)
	check(g.lane == 0, "tutorial uses the normal keyboard lane control")
	_answer(g, "correct")
	_answer(g, "correct")
	check(g.tutorial_step == 2 and not g.tutorial_actions.visible, "last exercise waits for the replay control")
	_menu_key(KEY_E)
	_answer(g, "correct")
	check(g.tutorial_actions.visible and root.gui_get_focus_owner() == g.btn_tutorial_continue, "three exercises lead to a focused completion screen")
	check(g.save.points() == 0 and not g.save.cleared_any("1-1") and g.logger.entries.is_empty(), "practice gives no rank, unlock, points or timed record")
	_menu_key(KEY_SPACE)
	check(g.tutorial_actions.visible, "early acceleration input cannot skip tutorial completion")
	g.result_time = 1.0
	_menu_key(KEY_ENTER)
	check(not g.is_tutorial_active() and g.state == g.State.READY and g.level_index == 0, "tutorial continues to the normal first stage")
	g.show_select()
	check(bool(g.save.get_setting("tutorial_seen", false)) and root.gui_get_focus_owner() in g.level_buttons, "returning player goes straight to stage selection")
	g.btn_tutorial.pressed.emit()
	g.pause_game()
	g.btn_quit.pressed.emit()
	check(not g.is_tutorial_active() and g.select_box.visible, "tutorial can be replayed and exited through Pause")

func layout_check(g, sz: Vector2i) -> void:
	var vr: Rect2 = g.get_viewport().get_visible_rect()
	var cx := vr.size.x * 0.5
	var tag := "%dx%d" % [sz.x, sz.y]
	var centered := true
	var inside := true
	var bad := []
	for item in [["hint", g.lbl_hint], ["notice", g.lbl_notice],
			["results", g.results_box.get_child(0)], ["select", g.select_box.get_child(0)], ["pause", g.pause_box.get_child(0)], ["settings", g.settings_box.get_child(0)],
			["speedometer", g.speedo]]:
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
	var a: Rect2 = g.btn_accel.get_global_rect(); var b: Rect2 = g.btn_brake.get_global_rect()
	var p: Rect2 = g.btn_pause.get_global_rect(); var v: Rect2 = g.btn_voice.get_global_rect()
	check(a.get_center().x > vr.size.x * 0.5 and a.end.y > vr.size.y * 0.75 and b.get_center().x < vr.size.x * 0.5 and b.end.y > vr.size.y * 0.75, "%s: 加速 bottom-right, 煞車 bottom-left" % tag)
	var h: Rect2 = g.hearts_box.get_global_rect()
	check(h.get_center().x < vr.size.x * 0.5 and not h.intersects(p) and not h.intersects(v) and not h.intersects(g.lbl_time.get_global_rect()) and not h.intersects(g.lbl_count.get_global_rect()), "%s: HP bar top-left, clear of time/count/pause %s t%s c%s p%s" % [tag, str(h), str(g.lbl_time.get_global_rect()), str(g.lbl_count.get_global_rect()), str(p)])
	var sc: Rect2 = g.select_scroll.get_global_rect()
	var inner: Control = g.select_scroll.get_child(0)
	check(sc.position.y >= -1 and sc.end.y <= vr.size.y + 1 and inner.size.y > sc.size.y, "%s: level list scrolls inside the screen (list %.0f > view %.0f)" % [tag, inner.size.y, sc.size.y])
	var tutorial_button: Rect2 = g.btn_tutorial.get_global_rect()
	check(tutorial_button.position.y >= sc.end.y - 1.0 and vr.grow(1.0).encloses(tutorial_button)
		and tutorial_button.size.y >= minf(vr.size.x, vr.size.y) * 0.11,
		"%s: stage list leaves room for the touch-sized tutorial entry after live resize" % tag)
	var lk: Rect2 = g.btn_lock.get_global_rect()
	var mn := minf(vr.size.x, vr.size.y)
	var menu_touch_sized := true
	for button in [g.btn_resume, g.btn_restart, g.btn_quit, g.btn_mode_pause_race, g.btn_mode_pause_step,
			g.btn_mode_race, g.btn_mode_step, g.btn_settings_back]:
		menu_touch_sized = menu_touch_sized and button.size.y * float(sz.y) / vr.size.y >= 44.0
	check(menu_touch_sized, "%s: pause and settings controls have at least 44 screen pixels of touch height" % tag)
	var road := Rect2(cx - mn * 0.17, mn * 0.43, mn * 0.34, vr.size.y - mn * 0.67)
	var road_clear := true
	for overlay in [g.go_box, g.judge, g.shield_box, g.combo_badge, g.lbl_notice, g.lbl_float, g.btn_lock]:
		road_clear = road_clear and not road.intersects(overlay.get_global_rect())
	check(road_clear, "%s: active stones and runner are clear of feedback overlays" % tag)
	check(lk.get_center().x > cx and lk.end.y < a.position.y and absf(lk.end.x - a.end.x) < 1.0, "%s: cruise lock sits directly above the accelerator" % tag)
	check(g.lbl_center.custom_minimum_size.x <= mn * 0.85, "%s: start instructions use a compact paper sign" % tag)
	check(a.size.x >= mn * 0.27 and b.size.x >= mn * 0.23 and p.size.x >= mn * 0.12, "%s: touch buttons scale with short side (加速 %.0f of %.0f)" % [tag, a.size.x, mn])
	check(not lk.intersects(a) and not lk.intersects(b) and not lk.intersects(p) and not lk.intersects(v) and not lk.intersects(g.lbl_speed.get_global_rect()) and not lk.intersects(g.lbl_combo.get_global_rect()), "%s: 鎖定 clear of other buttons and HUD" % tag)
	check(not a.intersects(g.lbl_speed.get_global_rect()) and not b.intersects(g.lbl_speed.get_global_rect()) and not a.intersects(g.lbl_combo.get_global_rect()) and not b.intersects(g.lbl_combo.get_global_rect()), "%s: speed/combo text clear of buttons" % tag)
	check(g.lbl_speed.position.x >= g.speedo.size.x * 0.4, "%s: speed readout stays clear of dial" % tag)
	check(p.position.y < vr.size.y * 0.2 and p.get_center().x > vr.size.x * 0.75 and not p.intersects(v) and not a.intersects(b), "%s: pause/speaker top-right, buttons don't overlap" % tag)

func safe_area_tests(g) -> void:
	print("safe area")
	var ins0: Dictionary = g.get_safe_insets()
	check(ins0.left == 0.0 and ins0.top == 0.0 and ins0.right == 0.0 and ins0.bottom == 0.0, "safe area defaults to 0 on desktop/headless")

	# Simulated iPhone Portrait (390x844 with Dynamic Island top=59, bottom=34)
	root.size = Vector2i(390, 844)
	g.safe_area_rect_override = Rect2i(0, 59, 390, 844 - 59 - 34)
	g._layout_touch()
	var insp: Dictionary = g.get_safe_insets()
	check(insp.top > 100.0 and insp.bottom > 50.0, "portrait safe insets match Dynamic Island and home bar")
	check(g.hearts_box.get_global_rect().position.y >= insp.top, "HP bar clears Dynamic Island")
	var vr_p: Rect2 = g.get_viewport().get_visible_rect()
	check(g.btn_accel.get_global_rect().end.y <= vr_p.end.y - insp.bottom, "accelerator button clears bottom home indicator")

	# Simulated iPhone Landscape (844x390 with camera notch on left=59, bottom=21)
	root.size = Vector2i(844, 390)
	g.safe_area_rect_override = Rect2i(59, 0, 844 - 59, 390 - 21)
	g._layout_touch()
	var insl: Dictionary = g.get_safe_insets()
	check(insl.left > 150.0 and insl.bottom > 50.0, "landscape safe insets match camera notch and home bar")
	check(g.btn_brake.get_global_rect().position.x >= insl.left, "brake button clears landscape camera notch")
	var vr_l: Rect2 = g.get_viewport().get_visible_rect()
	check(g.btn_brake.get_global_rect().end.y <= vr_l.end.y - insl.bottom, "brake button clears landscape home bar")

	# Reset
	g.safe_area_rect_override = Rect2i()
	root.size = Vector2i(1080, 1920)
	g._layout_touch()

func joypad_tests(g) -> void:
	print("joypad / controller")
	check(g.current_input_device == "keyboard", "default input device is keyboard")
	# InputMap actions registered
	for action in ["game_accelerate", "game_brake", "game_lane_left", "game_lane_right", "game_lock", "game_voice", "game_pause"]:
		check(InputMap.has_action(action), "InputMap registered action '%s'" % action)

	# Button A in READY starts run and accelerates
	g.set_level(0); g.reset_run()
	var ev_a := InputEventJoypadButton.new()
	ev_a.button_index = JOY_BUTTON_A; ev_a.pressed = true
	g._unhandled_input(ev_a)
	check(g.state == g.State.RUNNING and g.ctrl.is_accelerating(), "joypad A button starts run and accelerates")
	ev_a.pressed = false
	g._unhandled_input(ev_a)
	check(not g.ctrl.is_accelerating(), "joypad A button release stops accelerate")

	# Right Trigger analog accelerate
	var ev_rt := InputEventJoypadMotion.new()
	ev_rt.axis = JOY_AXIS_TRIGGER_RIGHT; ev_rt.axis_value = 1.0
	g._unhandled_input(ev_rt)
	check(g.ctrl.is_accelerating(), "joypad RT trigger accelerates")
	ev_rt.axis_value = 0.0
	g._unhandled_input(ev_rt)
	check(not g.ctrl.is_accelerating(), "joypad RT trigger release coasts")

	# Button B brakes
	g.ctrl.speed = 10.0
	var ev_b := InputEventJoypadButton.new()
	ev_b.button_index = JOY_BUTTON_B; ev_b.pressed = true
	g._unhandled_input(ev_b)
	check(g.ctrl.is_braking(), "joypad B button brakes")
	ev_b.pressed = false
	g._unhandled_input(ev_b)
	check(not g.ctrl.is_braking(), "joypad B button release releases brake")

	# Left Trigger analog brake
	g.ctrl.speed = 10.0
	var ev_lt := InputEventJoypadMotion.new()
	ev_lt.axis = JOY_AXIS_TRIGGER_LEFT; ev_lt.axis_value = 1.0
	g._unhandled_input(ev_lt)
	check(g.ctrl.is_braking(), "joypad LT trigger brakes")
	ev_lt.axis_value = 0.0
	g._unhandled_input(ev_lt)
	check(not g.ctrl.is_braking(), "joypad LT trigger release stops braking")

	# D-Pad steering
	g.lane = 1
	var ev_dl := InputEventJoypadButton.new()
	ev_dl.button_index = JOY_BUTTON_DPAD_LEFT; ev_dl.pressed = true
	g._unhandled_input(ev_dl)
	check(g.lane == 0, "joypad D-Pad Left changes lane left")
	var ev_dr := InputEventJoypadButton.new()
	ev_dr.button_index = JOY_BUTTON_DPAD_RIGHT; ev_dr.pressed = true
	g._unhandled_input(ev_dr)
	check(g.lane == 1, "joypad D-Pad Right changes lane right")

	# Left Stick analog steering
	var ev_sx := InputEventJoypadMotion.new()
	ev_sx.axis = JOY_AXIS_LEFT_X; ev_sx.axis_value = -0.7
	g._unhandled_input(ev_sx)
	check(g.lane == 0, "joypad Left Stick tilts left")
	ev_sx.axis_value = 0.0; g._unhandled_input(ev_sx)
	ev_sx.axis_value = 0.7; g._unhandled_input(ev_sx)
	check(g.lane == 1, "joypad Left Stick tilts right")

	# Button X cruise lock
	g.ctrl.speed = 10.0
	var ev_x := InputEventJoypadButton.new()
	ev_x.button_index = JOY_BUTTON_X; ev_x.pressed = true
	g._unhandled_input(ev_x)
	check(g.ctrl.locked, "joypad X button toggles cruise lock")

	# Button Start pause & resume
	var ev_st := InputEventJoypadButton.new()
	ev_st.button_index = JOY_BUTTON_START; ev_st.pressed = true
	g._unhandled_input(ev_st)
	check(g.state == g.State.PAUSED, "joypad Start button pauses")
	g._unhandled_input(ev_st)
	check(g.state == g.State.RUNNING, "joypad Start button resumes")

	# Vibration toggle & persistence
	check(g.btn_vibration != null and g.vibration_enabled, "vibration defaults to enabled")
	g.btn_vibration.pressed.emit()
	check(not g.vibration_enabled and not g.save.get_setting("vibration", true), "vibration toggles off and persists")
	g.btn_vibration.pressed.emit()
	check(g.vibration_enabled and bool(g.save.get_setting("vibration", false)), "vibration toggles back on and persists")

	# Adaptive input device detection & prompt switching
	g._set_input_device("keyboard")
	check(g.current_input_device == "keyboard", "input device resets to keyboard")
	check(g.pad_bar != null and not g.pad_bar.visible, "keyboard mode hides pad_bar")
	check(g.lbl_badge_accel.text == "W" and g.lbl_badge_brake.text == "S", "HUD badges reflect keyboard keys W / S")

	var ev_joy := InputEventJoypadButton.new(); ev_joy.button_index = JOY_BUTTON_DPAD_UP; ev_joy.pressed = true
	g._unhandled_input(ev_joy)
	check(g.current_input_device == "joypad", "joypad input switches current_input_device to joypad")
	check(g.pad_bar != null and g.pad_bar.visible, "joypad mode displays pad_bar")
	check(g.lbl_badge_accel.text == "A" and g.lbl_badge_brake.text == "B", "HUD badges reflect joypad buttons A / B")

	var ev_k := InputEventKey.new(); ev_k.keycode = KEY_SPACE; ev_k.pressed = true
	g._unhandled_input(ev_k)
	check(g.current_input_device == "keyboard", "keyboard input switches current_input_device to keyboard")
	check(g.pad_bar != null and not g.pad_bar.visible, "keyboard mode hides pad_bar")
	check(g.lbl_badge_accel.text == "W" and g.lbl_badge_brake.text == "S", "HUD badges reflect keyboard keys W / S")

	# Shoulder buttons (LB / RB) tab switching in select_box
	g.show_select()
	g.save.record("1-BOSS", "short", 3, 20.0) # ensure Katakana unlocked
	g._select_kana_tab("hira")
	var ev_rb := InputEventJoypadButton.new(); ev_rb.button_index = JOY_BUTTON_RIGHT_SHOULDER; ev_rb.pressed = true
	g._handle_joy_button(ev_rb)
	check(g.select_tab == "kata", "Right Shoulder (RB) switches to katakana tab")
	var ev_lb := InputEventJoypadButton.new(); ev_lb.button_index = JOY_BUTTON_LEFT_SHOULDER; ev_lb.pressed = true
	g._handle_joy_button(ev_lb)
	check(g.select_tab == "hira", "Left Shoulder (LB) switches to hiragana tab")

	# Focus Neighboring in Settings
	g.show_settings()
	check(g.btn_mode_race.focus_neighbor_bottom == g.btn_mode_step.get_path(), "settings focus: mode_race down -> mode_step")
	check(g.btn_lang.focus_neighbor_right == g.btn_vibration.get_path(), "settings focus: lang right -> vibration")
	check(g.btn_vibration.focus_neighbor_bottom == g.btn_settings_back.get_path(), "settings focus: vibration down -> back")
	g.hide_settings()

func i18n_tests(g) -> void:
	print("i18n localization")
	check(I18n.LOCALES == ["zh_TW", "zh_CN", "en", "ja"], "i18n supports zh_TW, zh_CN, en, ja")
	check(I18n.current_locale == "zh_TW", "default locale is Traditional Chinese (zh_TW)")
	check(g.btn_lang != null and g.btn_lang.text.contains("繁體中文"), "settings has language selector showing current locale")

	# Switch to English
	g.set_language("en")
	check(I18n.current_locale == "en", "locale switched to English")
	check(g.btn_resume.text == "Resume", "Pause menu Resume translated to English")
	check(g.btn_settings_back.text == "Back", "Settings Back translated to English")
	check(g.btn_lang.text.contains("English"), "Language button shows English")
	check(g.distance_name("short") == "Short", "Distance name translated to Short")

	# Switch to Japanese
	g.set_language("ja")
	check(I18n.current_locale == "ja", "locale switched to Japanese")
	check(g.btn_resume.text == "再開", "Pause menu Resume translated to Japanese")
	check(g.btn_settings_back.text == "戻る", "Settings Back translated to Japanese")
	check(g.btn_lang.text.contains("日本語"), "Language button shows 日本語")

	# Switch to Simplified Chinese
	g.set_language("zh_CN")
	check(I18n.current_locale == "zh_CN", "locale switched to Simplified Chinese")
	check(g.btn_resume.text == "继续", "Pause menu Resume translated to Simplified Chinese")
	check(g.btn_settings_back.text == "返回", "Settings Back translated to Simplified Chinese")
	check(g.btn_lang.text.contains("简体中文"), "Language button shows 简体中文")

	# Cycle back to Traditional Chinese
	g.set_language("zh_TW")
	check(I18n.current_locale == "zh_TW", "locale cycled back to Traditional Chinese")
	check(g.btn_resume.text == "繼續", "Pause menu Resume restored to Traditional Chinese")
	check(g.btn_settings_back.text == "返回", "Settings Back restored to Traditional Chinese")
	check(g.btn_lang.text.contains("繁體中文"), "Language button restored to 繁體中文")
	check(g.distance_name("short") == "短程", "Distance restored to 短程")
	check(str(g.save.get_setting("locale", "")) == "zh_TW", "locale persisted to save settings")

func audio_polish_tests(g) -> void:
	print("audio polish & dynamic music")
	# SFX preloads exist
	for sfx_key in ["shatter", "miss", "tick", "shift", "tap", "back", "star", "focus", "tab", "heal"]:
		check(Assets.SFX.has(sfx_key) and Assets.SFX[sfx_key] != null, "Assets.SFX preloads '%s'" % sfx_key)

	# Music preloads exist and loop
	for music_key in ["dash", "hit", "hosi", "ryu"]:
		check(Assets.MUSIC.has(music_key) and Assets.MUSIC[music_key] != null, "Assets.MUSIC preloads '%s'" % music_key)
		var m_stream = Assets.MUSIC[music_key]
		check(m_stream is AudioStreamMP3 and m_stream.loop, "Music track '%s' is looping AudioStreamMP3" % music_key)

	# Dynamic BGM resolution
	g.set_level(0) # 1-1, hira
	check(g._resolve_bgm() == Assets.MUSIC.dash, "1-1 (Hiragana) resolves to dash.mp3")

	# Find Katakana level
	var kata_idx := -1
	for idx in range(g.levels.size()):
		if g.levels[idx].get("script", "") == "kata":
			kata_idx = idx
			break
	if kata_idx >= 0:
		g.set_level(kata_idx)
		check(g._resolve_bgm() == Assets.MUSIC.hosi, "Katakana level resolves to hosi.mp3")

	# Find Boss level
	var boss_idx := -1
	for idx in range(g.levels.size()):
		if g.levels[idx].get("type", "") == "boss":
			boss_idx = idx
			break
	if boss_idx >= 0:
		g.set_level(boss_idx)
		check(g._resolve_bgm() == Assets.MUSIC.ryu, "Boss level resolves to ryu.mp3")

	# Endless Mode BGM
	g.is_endless = true
	check(g._resolve_bgm() == Assets.MUSIC.hit, "Endless mode resolves to hit.mp3")
	g.is_endless = false

	# SFX invocations
	g.sfx("focus")
	g.sfx("tab")
	g.sfx("heal")
	g.sfx("star")
	g.sfx("non_existent_sfx") # must not crash
	check(true, "All audio SFX triggers and fallback guards execute without error")

	# Reset level back to 0
	g.set_level(0)

func title_and_transition_tests(g) -> void:
	print("title screen & transitions")
	var prev_instant = g.instant_transitions
	g.instant_transitions = true
	g.show_title()
	check(g.state == g.State.TITLE, "show_title switches state to TITLE")
	check(g.title_box.visible, "title_box is visible on title screen")
	check(not g.select_box.visible and not g.results_box.visible, "select_box and results_box hidden on title")
	check(g.lbl_title_name.text.length() > 0, "title logo text populated")
	check(g.lbl_title_sub.text.length() > 0, "subtitle text populated")
	check(g.press_start_tween != null and g.press_start_tween.is_valid(), "press start CTA tween active")

	# Device prompt switching
	g._set_input_device("joypad")
	check(g.lbl_title_press.text.find("[A]") != -1, "title CTA prompt reflects joypad [A]")
	g._set_input_device("keyboard")
	check(g.lbl_title_press.text.find("[A]") == -1, "title CTA prompt reflects keyboard Space")

	# Transition behavior
	var instant_done := [false]
	g.instant_transitions = true
	g.fade_transition(func(): instant_done[0] = true, 0.2, 0.2)
	check(instant_done[0], "instant_transitions executes midpoint callback synchronously")

	# Animated fade transition start
	g.instant_transitions = false
	var async_done := [false]
	g.fade_transition(func(): async_done[0] = true, 0.05, 0.05)
	check(g.is_transitioning, "fade_transition starts tween and sets is_transitioning")
	check(g.fade_rect != null, "fade_rect canvas layer exists")

	# Clean up transition state
	g.instant_transitions = true
	g.is_transitioning = false
	if g.fade_rect != null:
		g.fade_rect.color.a = 0.0
		g.fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Transition to select and back
	g.start_from_title()
	check(g.state == g.State.SELECT, "start_from_title switches state to SELECT")
	check(g.select_box.visible and not g.title_box.visible, "select_box visible and title_box hidden")
	check(g.btn_to_title != null and g.btn_to_title.visible, "btn_to_title visible on level select")

	g.show_title()
	check(g.state == g.State.TITLE and g.title_box.visible, "returning to title restores title screen")

	# Leave game in SELECT state for layout tests
	g.show_select()
	g.instant_transitions = prev_instant

func kana_chart_and_drill_tests(g) -> void:
	print("kana chart & custom drill")
	var prev_instant = g.instant_transitions
	g.instant_transitions = true

	# 1. Chart panel open and navigation
	g.show_chart()
	check(g.chart_box.visible, "show_chart opens chart_box")
	check(g.chart_tab == "hira", "default tab is hira")
	check(g.chart_content.get_child_count() > 0, "hira chart table has kana rows")

	# 2. Tab switching & table contents
	g.chart_tab = "kata"; g._refresh_chart_ui()
	check(g.chart_content.get_child_count() > 0, "kata chart table has rows")
	g.chart_tab = "dakuon"; g._refresh_chart_ui()
	check(g.chart_content.get_child_count() > 0, "dakuon chart table has rows")
	g.chart_tab = "youon"; g._refresh_chart_ui()
	check(g.chart_content.get_child_count() > 0, "youon chart table has rows")

	# 3. Audio voice playback & fallback
	g.play_kana_voice("ka")
	check(g.voice.stream != null, "play_kana_voice sets audio stream for ka")
	g.play_kana_voice("di")
	check(g.voice.stream != null, "play_kana_voice resolves di -> ji stream")
	g.play_kana_voice("du")
	check(g.voice.stream != null, "play_kana_voice resolves du -> zu stream")

	# 4. Drill selection & counter
	g.show_chart("drill")
	check(g.chart_tab == "drill", "chart switches to drill tab")
	g._quick_select_drill("clear")
	check(g._calc_drill_pool_size() == 0, "quick select clear empties pool")
	g._quick_select_drill("all")
	check(g._calc_drill_pool_size() > 50, "quick select all selects full pool")
	g._quick_select_drill("hira")
	check(g._calc_drill_pool_size() >= 46, "quick select hira selects all hiragana")
	g._quick_select_drill("kata")
	check(g._calc_drill_pool_size() >= 46, "quick select kata selects all katakana")
	g._quick_select_drill("confuse")
	check(g._calc_drill_pool_size() >= 15, "quick select confuse selects tricky sets")

	# 5. Validation guard: cannot start with empty pool
	g._quick_select_drill("clear")
	g.start_custom_drill()
	check(not g.is_drill, "start_custom_drill refuses starting with empty pool")

	# 6. Valid drill execution
	g.drill_selected_rows["あ行"] = true
	g.drill_selected_rows["か行"] = true
	g.drill_count_mode = "short"
	g.drill_speed_mode = "race"
	g.start_custom_drill()
	check(g.is_drill, "start_custom_drill sets is_drill")
	check(g.lvl.kana.size() == 10, "drill level pool has selected 10 kana")
	check(g.state == g.State.READY, "state is READY for custom drill run")

	# 7. Run execution and row question pool verification
	g.start_run()
	check(g.state == g.State.RUNNING, "run starts in custom drill")
	var r = g.active_row()
	check(r != null, "custom drill spawns active row")
	for k in r.kana:
		check(g.lvl.kana.has(k), "all row stones belong to selected drill pool (%s)" % k)

	# 8. Results screen and clean exit
	g._finish(true)
	check(g.is_drill, "is_drill remains true on results screen")
	check(g.btn_retry.text.length() > 0 and g.btn_select.text.length() > 0, "drill results action buttons populated")

	g.is_drill = false
	g.hide_chart()
	check(not g.chart_box.visible, "hide_chart hides chart_box")
	g.show_select()
	g.instant_transitions = prev_instant

func cyber_polish_tests(g) -> void:
	print("cyber polish: hit pitch & liveries & props")
	# 1. Hit pitch calculation tests
	g.save.set_setting("hit_pitch_mode", "pentatonic")
	var p1: float = g.calc_hit_pitch(1)
	var p2: float = g.calc_hit_pitch(2)
	var p3: float = g.calc_hit_pitch(3)
	var p6: float = g.calc_hit_pitch(6)
	check(is_equal_approx(p1, 1.0), "combo 1 pitch is 1.0")
	check(p2 > p1, "combo 2 pitch climbs higher than combo 1 (got %.3f > %.3f)" % [p2, p1])
	check(p3 > p2, "combo 3 pitch climbs higher than combo 2 (got %.3f > %.3f)" % [p3, p2])
	check(p6 > p1, "combo 6 enters next octave cycle (got %.3f)" % p6)

	g.save.set_setting("hit_pitch_mode", "fixed")
	check(is_equal_approx(g.calc_hit_pitch(5), 1.0), "fixed mode returns 1.0 regardless of combo")

	g.save.set_setting("hit_pitch_mode", "random")
	var pr: float = g.calc_hit_pitch(5)
	check(pr >= 0.94 and pr <= 1.11, "random mode returns pitch between 0.95 and 1.10")

	# Restore to default pentatonic
	g.save.set_setting("hit_pitch_mode", "pentatonic")

	# 2. Settings button for hit pitch
	g.show_settings()
	check(g.btn_hit_pitch != null, "settings panel has hit pitch button")
	check(g.btn_hit_pitch.text.contains("五音") or g.btn_hit_pitch.text.contains("Pentatonic") or g.btn_hit_pitch.text.contains("音階"), "hit pitch button displays mode")
	g.btn_hit_pitch.pressed.emit()
	check(g.save.get_setting("hit_pitch_mode") == "random", "clicking hit pitch cycles to random")
	g.btn_hit_pitch.pressed.emit()
	check(g.save.get_setting("hit_pitch_mode") == "fixed", "clicking hit pitch cycles to fixed")
	g.btn_hit_pitch.pressed.emit()
	check(g.save.get_setting("hit_pitch_mode") == "pentatonic", "clicking hit pitch cycles back to pentatonic")
	g.hide_settings()

	# 3. Cyber liveries & shop expansion (8 items)
	check(g.AURAS.size() == 8, "shop has 8 cyber liveries (got %d)" % g.AURAS.size())
	for k in ["default", "cyan", "emerald", "pink", "crimson", "synthwave", "white", "gold"]:
		check(g.AURAS.has(k), "AURAS contains livery %s" % k)

	# Unlock and equip new skin
	var prev_pts: int = g.save.points()
	g.save.add_points(1000)
	check(g.save.unlock_aura("emerald", 150), "unlocks matrix emerald livery")
	check(g.save.is_aura_unlocked("emerald"), "emerald is unlocked in save")
	g.save.equip_aura("emerald")
	check(g.save.get_equipped_aura() == "emerald", "emerald is equipped in save")
	g._apply_upgrades_from_save()

	g.save.equip_aura("default")
	g.save.add_points(-g.save.points() + prev_pts)

	# 4. Background buildings and roadside cyber props
	check(g.Art.PROPS.has("house_l_cyber"), "Art.PROPS contains house_l_cyber")
	check(g.Art.PROPS.has("house_r_tower"), "Art.PROPS contains house_r_tower")
	check(g.Art.PROPS.has("cyber_hologram"), "Art.PROPS contains cyber_hologram")
	check(g.MID_PROPS_L.has("house_l_cyber"), "MID_PROPS_L includes house_l_cyber")
	check(g.MID_PROPS_R.has("house_r_tower"), "MID_PROPS_R includes house_r_tower")
	check(!g.NEAR_PROPS_L.has("cyber_hologram") and g.NEAR_PROPS_L.has("vending"), "NEAR_PROPS_L excludes opaque cyber_hologram")
	check(g.NEAR_PROPS_L.has("bench"), "NEAR_PROPS_L includes bench")
	check(g.NEAR_PROPS_L.has("shrub"), "NEAR_PROPS_L includes shrub")

	# 5. Camera height, runner transparency & gameplay improvements
	g._update_view(0.0)
	check(g.cam.position.y >= 4.0, "camera height raised to 4.1m to eliminate middle-lane occlusion")
	check(g.runner.has_method("set_opacity"), "runner sprite supports set_opacity")
	g.runner.set_opacity(0.55)
	check(g.runner._mat.get_shader_parameter("opacity") == 0.55, "runner shader receives opacity")
	g.runner.set_opacity(1.0)

	# 6. Boss shield time bonus check
	g.set_level(3); g.reset_run(); g.start_run()
	g.elapsed = 10.0
	g.shield_thresholds = [0.3]
	g.break_chain = 1
	g.boss_shield_up = true
	var b0: float = g.shield_bonus
	var clk0: float = g.clock()
	var row = g.active_row()
	g.player_dist = row.dist
	g.player_x = g.lane_x(row.target)
	g._resolve(row)
	check(g.shield_bonus == b0 + 3.0, "breaking boss shield awards +3.0s time bonus")
	check(g.clock() <= clk0 - 2.9, "shield bonus subtracts 3.0s from clock")

	# 7. Endless mode low speed stall protection
	g.start_endless()
	g.start_run()
	g.ctrl.speed = 0.0
	var hp_before: int = g.hp
	g._tick(3.1)
	check(g.hp < hp_before, "endless mode parking (0 km/h) drains HP after 2.5s")
	g.reset_run()

func retention_system_tests(g) -> void:
	print("retention systems: daily challenge, streak, mastery heatmap, weakness drill, player rank")
	var prev_instant: bool = g.instant_transitions
	g.instant_transitions = true

	# 1. Daily Challenge & Streak Save Data Logic
	var d: Dictionary = g.save.get_daily()
	check(d is Dictionary and d.has("streak") and d.has("last_date"), "save data has daily challenge structure")
	var st0: Dictionary = g.save.check_daily_status()
	check(st0.has("streak") and st0.has("completed") and st0.has("today"), "check_daily_status returns current daily status")

	var prev_pts: int = g.save.points()
	var res1: Dictionary = g.save.record_daily_clear(100)
	check(res1.first_today == true, "first daily clear of today marks first_today = true")
	check(res1.points_awarded == 100, "first daily clear awards 100 points")
	check(g.save.points() == prev_pts + 100, "player points credited +100")
	check(g.save.get_daily().streak >= 1, "daily streak is at least 1")

	# Second clear on same day should award no additional points
	var res2: Dictionary = g.save.record_daily_clear(100)
	check(res2.first_today == false, "second daily clear on same day is not first_today")
	check(res2.points_awarded == 0, "second daily clear awards 0 points")

	# Mock consecutive streak from yesterday
	var d_mock: Dictionary = g.save.get_daily()
	d_mock["last_date"] = g.save._get_yesterday_string()
	d_mock["streak"] = 5
	d_mock["today_completed"] = false
	var res3: Dictionary = g.save.record_daily_clear(100)
	check(res3.streak == 6, "clearing with yesterday as last_date increments streak from 5 to 6")

	# 2. Kana Mastery Tracking
	g.save.record_kana_stat("あ", "correct", 0.45)
	g.save.record_kana_stat("あ", "correct", 0.50)
	var st_a: Dictionary = g.save.get_kana_stat("あ")
	check(st_a.attempts == 2 and st_a.correct == 2, "record_kana_stat records attempts and correct answers for 'あ'")
	check(g.save.get_kana_tier("あ") == "mastered", "'あ' with 100% accuracy and <0.95s reaction is classified as 'mastered'")

	g.save.record_kana_stat("ぬ", "wrong", 1.8)
	g.save.record_kana_stat("ぬ", "miss", 2.2)
	var st_nu: Dictionary = g.save.get_kana_stat("ぬ")
	check(st_nu.wrong == 1 and st_nu.miss == 1, "record_kana_stat records wrong and miss for 'ぬ'")
	check(g.save.get_kana_tier("ぬ") == "weak", "'ぬ' with 0% accuracy is classified as 'weak'")

	var weakest: Array = g.save.get_weakest_kana(5)
	check(weakest.has("ぬ"), "get_weakest_kana includes weak kana 'ぬ'")

	# 3. Player Rank & Tier
	var rk: Dictionary = g.save.get_player_rank()
	check(rk.has("tier") and rk.has("title") and rk.has("badge") and rk.has("color"), "player rank contains tier, title, badge, color")
	check(rk.tier >= 1 and rk.tier <= 5, "player rank tier is valid (1..5, got %d: %s)" % [rk.tier, rk.title])

	# 4. Daily Run In-Game Flow
	g.show_select()
	check(g.btn_daily != null and is_instance_valid(g.btn_daily), "btn_daily exists in level select")
	g.start_daily_run()
	check(g.is_daily, "start_daily_run sets is_daily = true")
	check(g.level_id == "daily", "daily level_id is 'daily'")
	check(int(g.lvl.target_correct) == 20, "daily challenge requires 20 target correct")
	check(g.state == g.State.READY, "state is READY after start_daily_run")
	g.start_run()
	check(g.state == g.State.RUNNING, "daily run starts running")

	# Finish daily run & results check
	g._finish(true)
	check(g.results_box.visible, "results box shown on daily run clear")
	check(g.lbl_result_heading.text.contains("今日") or g.lbl_result_heading.text.contains("Daily") or g.lbl_result_heading.text.contains("每日"), "results heading displays Daily Challenge title")
	g.show_select()
	check(not g.is_daily, "show_select resets is_daily")

	# 5. Mastery Heatmap & Weakness Drill (弱點急行軍)
	g.show_chart("hira")
	check(g.chart_box.visible, "show_chart opens chart dialog")
	g.show_chart("drill")
	check(g.chart_tab == "drill", "chart switches to drill tab")
	g._quick_select_drill("weak")
	check(g._calc_drill_pool_size() > 0, "quick select 'weak' successfully builds targeted drill pool from weak kana")
	check(g.drill_selected_rows.get("な行", false), "targeted drill includes 'な行' for weak kana 'ぬ'")
	g.hide_chart()
	check(not g.chart_box.visible, "hide_chart hides chart")

	g.show_select()
	g.set_level(0)
	g.reset_run()
	g.instant_transitions = prev_instant


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

func _process(_delta: float) -> bool:
	if phase == "shutdown":
		# AudioServer releases stopped MP3 playbacks on its mixing thread.
		if Time.get_ticks_msec() - shutdown_msec >= 200:
			quit(1 if fails > 0 else 0)
		return false
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
		_review_tests(reg_game)
		_menu_ui_tests(reg_game)
		run_rule_tests(reg_game)
		question_rotation_tests(reg_game)
		tutorial_tests(reg_game)
		safe_area_tests(reg_game)
		joypad_tests(reg_game)
		i18n_tests(reg_game)
		audio_polish_tests(reg_game)
		title_and_transition_tests(reg_game)
		kana_chart_and_drill_tests(reg_game)
		cyber_polish_tests(reg_game)
		retention_system_tests(reg_game)
		print("layout")
		_layout_prepare(reg_game)
		phase = "layout"
		layout_wait = 0
		root.size = SIZES[0]
		return false
	if phase == "layout":
		layout_wait += 1
		if layout_wait < 3:
			return false
		layout_check(reg_game, SIZES[layout_i])
		layout_i += 1
		layout_wait = 0
		if layout_i < SIZES.size():
			root.size = SIZES[layout_i]
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
	if game.state == game.State.CLEARED or game.state == game.State.FAILED or frames > 60 * 300:
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
		game = null
		phase = "shutdown"
		shutdown_msec = Time.get_ticks_msec()
		return false
	return false
