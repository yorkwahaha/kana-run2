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
	g.set_max_hp(999, true)   # this test is about re-queue termination, not HP
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

func _hearts(g) -> String:
	var t := ""
	for c in g.hearts_box.get_children():
		if c != g.lbl_shield: t += c.text
	return t

func hp_tests(g) -> void:
	print("HP")
	var cfg: Dictionary = GameConfig.load_config()
	check(int(cfg.hp.max_hp) == 3 and cfg.hp.miss_costs_heart == false, "config: 3 hearts, miss costs no heart by default")
	g.set_level(0); g.reset_run(); g.start_run()
	check(g.hp == 3 and g.max_hp == 3 and _hearts(g) == "♥♥♥", "run starts with 3 hearts")
	var got := []
	var cb := func(h, m, sh): got.append([h, m, sh])
	g.hp_changed.connect(cb)
	g.ctrl.speed = 10.0
	var p0: float = g.penalty
	_answer(g, "wrong")
	check(g.hp == 2 and _hearts(g) == "♥♥♡", "wrong hit = -1 heart")
	check(is_equal_approx(g.penalty - p0, 2.0) and is_equal_approx(g.ctrl.speed, 5.0), "wrong hit still -2 s and speed halved")
	check(got.size() >= 1 and got[-1][0] == 2, "hp_changed signal emitted")
	check(g.cam.h_offset == 0.0 and g.cam.v_offset == 0.0, "no camera/screen shake on damage")
	_answer(g, "miss")
	check(g.hp == 2, "miss costs no heart by default")
	g.elapsed = 0.0
	for i in 30: g._tick(1.0 / 60.0)
	check(g.hp == 2, "no passive HP drain")
	_answer(g, "wrong")
	check(g.hp == 1 and g.state == g.State.RUNNING, "1 heart left, still running")
	_answer(g, "wrong")
	check(g.hp == 0 and g.state == g.State.FAILED and g.fail_reason == "hp_out", "0 HP ends the run immediately (reason hp_out)")
	check(g.lbl_result.text.begins_with("體力耗盡") and g.results_box.visible, "results show 「體力耗盡」")
	check(not g.save.get_record("level_01").get("cleared", false), "hp_out is not saved as a clear")
	g.hp_changed.disconnect(cb)
	# time-up reason
	g.reset_run(); g.start_run(); g.elapsed = 999.0; g._tick(0.0)
	check(g.fail_reason == "time_up" and g.lbl_result.text.begins_with("時間到"), "time-up shows 「時間到」 (distinct reason)")
	# miss switch
	g.reset_run(); g.start_run(); g.miss_costs_heart = true
	_answer(g, "miss")
	check(g.hp == 2, "miss_costs_heart switch: miss = -1 heart")
	g.set_level(0)
	# per-level override
	var lv: Array = GameConfig.levels(cfg)
	lv[0]["max_hp"] = 5; lv[0]["miss_costs_heart"] = true
	g.levels = lv; g.set_level(0); g.reset_run()
	check(g.max_hp == 5 and g.hp == 5 and g.miss_costs_heart, "per-level max_hp / miss_costs_heart override")
	g.levels = GameConfig.levels(GameConfig.load_config()); g.set_level(0); g.reset_run(); g.start_run()
	# hooks
	g.add_shield(1)
	check(g.lbl_shield.text == "盾×1", "shield shown")
	var blocked := []
	var dcb := func(a, b): blocked.append(b)
	g.damaged.connect(dcb)
	check(not g.take_damage(1) and g.hp == 3 and g.shield == 0 and blocked == [true], "shield (charm) blocks one damage")
	g.take_damage(1)
	check(g.hp == 2 and blocked[-1] == false, "next damage goes through")
	g.damaged.disconnect(dcb)
	g.heal(1); g.heal(5)
	check(g.hp == 3, "heal +1, capped at max")
	g.set_max_hp_bonus(2)
	check(g.max_hp == 5 and g.hp == 5 and _hearts(g) == "♥♥♥♥♥", "max-HP upgrade hook (+2) refills to 5")
	g.reset_run()
	check(g.max_hp == 5, "max-HP bonus persists across restarts")
	g.set_max_hp_bonus(0); g.reset_run()
	check(g.max_hp == 3, "bonus removable")
	# dev log reason
	g.force_dev_mode = true; g.dev_mode = true
	g.start_run(); g.take_damage(3)
	var j = JSON.parse_string(FileAccess.get_file_as_string(g.last_saved_path))
	check(j is Dictionary and j.outcome == "hp_out" and int(j.hp_left) == 0, "timing log records outcome hp_out")
	g.dev_mode = false
	g.set_level(0)

func level_tests(g) -> void:
	print("level data")
	var lv: Array = GameConfig.levels(GameConfig.load_config())
	check(lv.size() >= 2 and lv[0].id == "level_01" and lv[1].id == "level_02", "levels loaded in order from config (%d)" % lv.size())
	check(int(lv[0].target_correct) == 20 and float(lv[0].time_limit_s) == 63.0 and float(lv[0].star2_s) == 47.0 and float(lv[0].star3_s) == 36.0, "level 1: 20 / 63 / 47 / 36 unchanged")
	check(int(lv[1].target_correct) == 30 and float(lv[1].time_limit_s) == 91.0 and float(lv[1].star2_s) == 68.0 and float(lv[1].star3_s) == 52.0, "level 2: 30 / 91 / 68 / 52")
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
			["results", g.results_box.get_child(0)], ["select", g.select_box.get_child(0)], ["pause", g.pause_box.get_child(0)],
			["speed", g.lbl_speed], ["combo", g.lbl_combo]]:
		var rc: Rect2 = item[1].get_global_rect()
		if absf(rc.get_center().x - cx) > 2.0:
			centered = false; bad.append(item[0])
	for item in [g.lbl_time, g.lbl_count, g.lbl_speed, g.lbl_combo, g.lbl_hint, g.results_box.get_child(0), g.select_box.get_child(0),
			g.pause_box.get_child(0), g.btn_accel, g.btn_brake, g.btn_pause, g.btn_voice, g.hearts_box]:
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
	check(h.get_center().x < vr.size.x * 0.5 and not h.intersects(p) and not h.intersects(v) and not h.intersects(g.lbl_time.get_global_rect()) and not h.intersects(g.lbl_count.get_global_rect()), "%s: hearts top-left, clear of time/count/pause %s t%s c%s p%s" % [tag, str(h), str(g.lbl_time.get_global_rect()), str(g.lbl_count.get_global_rect()), str(p)])
	check(p.position.y < vr.size.y * 0.2 and p.get_center().x > vr.size.x * 0.75 and not p.intersects(v) and not a.intersects(b), "%s: pause/speaker top-right, buttons don't overlap" % tag)

func _layout_prepare(g) -> void:
	g.set_level(0); g.reset_run()
	g.lbl_hint.text = "ka"; g._notice("聽音模式"); g.lbl_float.text = "○"; g.lbl_combo.text = "20 連擊"
	g.lbl_result.text = "CLEAR!\n★★★\n\nTime 31.30 s\n(run 31.30 + penalty 0.0)\nwrong 0   miss 0\nbest combo 20\n新紀錄！"
	g.results_box.visible = true
	g.show_select()
	g.results_box.visible = true
	g.pause_box.visible = true

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
		check(FileAccess.file_exists("user://timing/runs_v2.csv"), "timing CSV written")
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
