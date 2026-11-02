extends SceneTree
## Headless smoke test: runs level 1 on autopilot (always correct lane,
## always accelerating) and checks it clears. Also runs unit checks.
## Run:  Godot --headless --path . --fixed-fps 60 -s res://tools/smoke_test.gd

const SpeedController = preload("res://scripts/speed_controller.gd")
const Rules = preload("res://scripts/rules.gd")
const Assets = preload("res://scripts/asset_manifest.gd")
const SaveData = preload("res://scripts/save_data.gd")
const GameConfig = preload("res://scripts/game_config.gd")

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
	feature_tests(g)

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
	while g.correct < 10:
		var r = g.active_row()
		var k: String = r.kana[r.target]
		var n: int = seen.get(k, 0)
		if r.hint != (n < 3): hint_ok = false
		if r.hint and g.lbl_hint.text != g._romaji(k): hint_ok = false
		seen[k] = n + 1
		if g.voice_only_announced: notice_before = true
		_answer(g, "correct")
	check(hint_ok, "romaji hint shown exactly for each kana's first 3 appearances")
	check(not notice_before, "no voice-only notice before 50%")
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
	var steps := 0
	while g.correct < 20 and steps < 500:
		var p := rng.randf()
		_answer(g, "correct" if p < 0.6 else ("wrong" if p < 0.85 else "miss"))
		steps += 1
	check(g.correct >= 20 and steps < 500, "mixed correct/wrong/miss still reaches 20 correct (%d rows)" % steps)

var reg_game
var auto_level := 0
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
	game.level_index = auto_level
	game.force_dev_mode = true
	game.rng_seed = 7
	root.add_child(game)

func level_tests(g) -> void:
	print("level data")
	var lv: Array = GameConfig.levels(GameConfig.load_config())
	check(lv.size() >= 2 and lv[0].id == "level_01" and lv[1].id == "level_02", "levels loaded in order from config (%d)" % lv.size())
	check(int(lv[0].target_correct) == 20 and float(lv[0].time_limit_s) == 63.0 and float(lv[0].star2_s) == 47.0 and float(lv[0].star3_s) == 36.0, "level 1: 20 / 63 / 47 / 36 unchanged")
	check(int(lv[1].target_correct) == 30 and float(lv[1].time_limit_s) == 90.0 and float(lv[1].star2_s) == 66.0 and float(lv[1].star3_s) == 48.0, "level 2: 30 / 90 / 66 / 48")
	check("".join(lv[1].kana) == "あいうえおかきくけこ", "level 2 pool = あ行 + か行")
	var voices_ok := true
	for L in lv:
		if L.kana.size() != L.romaji.size(): voices_ok = false
		for r in L.romaji:
			if not Assets.VOICE.has(r) or Assets.VOICE[r] == null: voices_ok = false
	check(voices_ok, "every level kana has a preloaded voice clip")
	print("level 2 rules")
	g.set_level(1); g.reset_run(); g.start_run()
	check(g.level_id == "level_02" and g.hint_first_n == 3 and is_equal_approx(g.hint_ratio, 0.5), "level 2 uses hint rules (3 / 0.5)")
	var seen := {}
	var ok := true
	var pool_ok := true
	var ka_seen := false
	while g.correct < 15:
		var r = g.active_row()
		var k: String = r.kana[r.target]
		for x in r.kana:
			if not lv[1].kana.has(x): pool_ok = false
		if "かきくけこ".contains(k): ka_seen = true
		var n: int = seen.get(k, 0)
		if r.hint != (n < 3): ok = false
		seen[k] = n + 1
		_answer(g, "correct")
	check(pool_ok and ka_seen, "level 2 rows use only its 10 kana, か行 appears")
	check(ok, "level 2 hint shown for first 3 per kana")
	check(not g.active_row().hint and g.voice_only_announced, "level 2 voice-only after 15/30")
	while g.correct < 30:
		_answer(g, "correct")
	g._tick(0.0)
	check(g.state == g.State.CLEARED, "level 2 clears at 30 correct")

func save_tests() -> void:
	print("save / unlock")
	var lv: Array = GameConfig.levels(GameConfig.load_config())
	var sd = SaveData.new(); sd.path = "user://selftest_save2.json"; sd.clear_all()
	check(sd.is_unlocked(lv, 0) and not sd.is_unlocked(lv, 1), "fresh save: only level 1 open")
	check(sd.record("level_01", 2, 40.0), "first clear is recorded")
	check(sd.is_unlocked(lv, 1), "clearing level 1 unlocks level 2")
	check(not sd.record("level_01", 1, 45.0), "worse run does not count as better")
	var r: Dictionary = sd.get_record("level_01")
	check(int(r.best_stars) == 2 and is_equal_approx(float(r.best_time), 40.0), "best kept after worse run")
	check(sd.record("level_01", 3, 31.3), "better run recorded")
	check(not sd.record("level_01", 2, 35.0), "slower 2-star does not overwrite")
	check(sd.save_file(), "save written")
	var sd2 = SaveData.new(); sd2.path = sd.path; sd2.load_file()
	r = sd2.get_record("level_01")
	check(int(r.best_stars) == 3 and is_equal_approx(float(r.best_time), 31.3) and sd2.is_unlocked(lv, 1), "save reloads: 3 stars, 31.3 s, level 2 open")

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
	while g.correct < 20:
		_answer(g, "correct")
	g._tick(0.0)
	check(g.state == g.State.CLEARED and g.results_box.visible, "results panel shown on clear")
	check(g.btn_next.visible and not g.btn_next.disabled and g.btn_select.visible, "「下一關」enabled after clearing level 1")
	check(g.save.get_record("level_01").cleared, "clear saved")
	g.btn_next.pressed.emit()
	check(g.level_index == 1 and g.state == g.State.READY, "「下一關」goes to level 2")
	g.start_run()
	g.elapsed = 999.0
	g._tick(0.0)
	check(g.state == g.State.FAILED and g.results_box.visible and g.btn_next.visible == false, "last level: no 「下一關」")
	g.btn_select.pressed.emit()
	check(g.state == g.State.SELECT and not g.level_buttons[1].disabled, "「回選關」returns; level 2 now open")
	g.set_level(0)

func layout_check(g, sz: Vector2i) -> void:
	var vr: Rect2 = g.get_viewport().get_visible_rect()
	var cx := vr.size.x * 0.5
	var tag := "%dx%d" % [sz.x, sz.y]
	var centered := true
	var inside := true
	var bad := []
	for item in [["hint", g.lbl_hint], ["notice", g.lbl_notice], ["float", g.lbl_float], ["center", g.lbl_center],
			["results", g.results_box.get_child(0)], ["select", g.select_box.get_child(0)]]:
		var rc: Rect2 = item[1].get_global_rect()
		if absf(rc.get_center().x - cx) > 2.0:
			centered = false; bad.append(item[0])
	for item in [g.lbl_time, g.lbl_count, g.lbl_speed, g.lbl_combo, g.lbl_hint, g.results_box.get_child(0), g.select_box.get_child(0)]:
		var rc: Rect2 = item.get_global_rect()
		if rc.position.x < -1 or rc.position.y < -1 or rc.end.x > vr.size.x + 1 or rc.end.y > vr.size.y + 1:
			inside = false; bad.append(str(item.name) + " " + str(item.get_global_rect()))
	check(centered, "%s: centered text/panels are centered (canvas %.0fx%.0f) %s" % [tag, vr.size.x, vr.size.y, str(bad)])
	check(inside, "%s: all HUD/panels inside the screen %s" % [tag, str(bad)])
	check(g.lbl_center.get_global_rect().size.x >= vr.size.x - 60, "%s: info text spans the full width" % tag)

func _layout_prepare(g) -> void:
	g.set_level(0); g.reset_run()
	g.lbl_hint.text = "ka"; g._notice("聽音模式"); g.lbl_float.text = "○"; g.lbl_combo.text = "20 連擊"
	g.lbl_result.text = "CLEAR!\n★★★\n\nTime 31.30 s\n(run 31.30 + penalty 0.0)\nwrong 0   miss 0\nbest combo 20\n新紀錄！"
	g.results_box.visible = true
	g.show_select()
	g.results_box.visible = true

var total_frames := 0

func _process(_delta: float) -> bool:
	frames += 1
	total_frames += 1
	if total_frames > 60 * 400 or (reg_game != null and not reg_game.has_method("reset_run")):
		printerr("ABORT: game script failed to load or test ran too long")
		quit(2)
		return true
	if phase == "unit":
		regression_tests()
		level_tests(reg_game)
		save_tests()
		results_tests(reg_game)
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
		auto_level = 0
		_start_autopilot()
		frames = 0
		return false
	if frames == 3:
		game.start_run()
	if frames < 3:
		return false
	if game.state == game.State.CLEARED or game.state == game.State.FAILED or frames > 60 * 120:
		var n := auto_level + 1
		var tgt := 20 if auto_level == 0 else 30
		check(game.state == game.State.CLEARED, "autopilot clears level %d (clock %.2f s, stars %d, correct %d, wrong %d, miss %d)" % [n, game.clock(), Rules.stars_for(game.clock(), game.lvl), game.correct, game.wrong, game.missed])
		check(game.wrong == 0 and game.missed == 0, "autopilot L%d makes no mistakes" % n)
		check(game.logger.entries.size() == tgt, "dev logger recorded %d questions" % tgt)
		check(FileAccess.file_exists("user://timing/runs.csv"), "timing CSV written")
		if auto_level == 0:
			root.remove_child(game); game.free()
			auto_level = 1
			_start_autopilot()
			frames = 0
			return false
		print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
		root.remove_child(game)
		game.free()
		quit(1 if fails > 0 else 0)
		return true
	return false
