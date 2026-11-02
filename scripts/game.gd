extends Node3D
## Kana Run 2.0 - Level 1 prototype.
## Everything (world, HUD, audio) is built in code so the scene file stays
## trivial and easy to merge. Tunables live in config/game_config.json.

const GameConfig = preload("res://scripts/game_config.gd")
const SpeedController = preload("res://scripts/speed_controller.gd")
const Rules = preload("res://scripts/rules.gd")
const DevLogger = preload("res://scripts/dev_logger.gd")
const Assets = preload("res://scripts/asset_manifest.gd")

enum State { READY, RUNNING, CLEARED, FAILED }

@export var level_id := "level_01"
## Set by tools/smoke_test.gd: steers to the right lane and holds accelerate.
var autopilot := false
var force_dev_mode := false
var rng_seed := -1

var cfg: Dictionary
var lvl: Dictionary
var state: State = State.READY
var ctrl = SpeedController.new()
var logger = DevLogger.new()
var rng := RandomNumberGenerator.new()
var dev_mode := false

# run state
var elapsed := 0.0
var penalty := 0.0
var correct := 0
var wrong := 0
var missed := 0
var player_dist := 0.0
var lane := 1
var player_x := 0.0
var rows: Array = []          # Array[Dictionary]
var next_row_dist := 0.0
var q_counter := 0
var last_target := ""
var result_time := 0.0
var last_saved_path := ""

# tunables (cached)
var lane_w := 2.2
var lane_count := 3
var lane_change_speed := 13.75
var swipe_min := 40.0
var player_w := 0.9
var stone_w := 1.2
var row_spacing := 24.0
var first_row := 30.0
var spawn_ahead := 80.0
var key_lane_needs_hold := false

# touch
var touch_id := -1
var touch_anchor := Vector2.ZERO

# nodes
var player: Node3D
var player_mesh: MeshInstance3D
var player_mat: StandardMaterial3D
var cam: Camera3D
var base_fov := 70.0
var stripes: Array = []
var voice: AudioStreamPlayer
var music: AudioStreamPlayer
var sfx_pool: Array = []
var hud: CanvasLayer
var lbl_time: Label
var lbl_count: Label
var lbl_speed: Label
var lbl_center: Label
var lbl_dev: Label
var lbl_float: Label

func _ready() -> void:
	cfg = GameConfig.load_config()
	lvl = cfg.get("levels", {}).get(level_id, {})
	ctrl.configure(cfg.get("speed", {}))
	var L: Dictionary = cfg.get("lanes", {})
	lane_count = int(L.get("count", 3))
	lane_w = float(L.get("lane_width_m", 2.2))
	lane_change_speed = lane_w / maxf(0.01, float(L.get("lane_change_time_s", 0.16)))
	swipe_min = float(L.get("swipe_min_px", 40))
	player_w = float(L.get("player_width_m", 0.9))
	stone_w = float(L.get("stone_width_m", 1.2))
	key_lane_needs_hold = bool(L.get("keyboard_lane_change_requires_hold", false))
	var T: Dictionary = cfg.get("track", {})
	row_spacing = float(T.get("row_spacing_m", 24.0))
	first_row = float(T.get("first_row_m", 30.0))
	spawn_ahead = float(T.get("spawn_ahead_m", 80.0))
	dev_mode = force_dev_mode or bool(cfg.get("dev", {}).get("timing_mode", false)) \
		or OS.get_cmdline_user_args().has("--dev")
	_build_world()
	_build_hud()
	_build_audio()
	reset_run()

# ---------------------------------------------------------------- build
func lane_x(i: int) -> float:
	return (i - (lane_count - 1) * 0.5) * lane_w

func _mat(c: Color, emit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.0
	return m

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.05, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.75)
	e.glow_enabled = true
	e.glow_intensity = 1.0
	e.glow_bloom = 0.05
	e.fog_enabled = true
	e.fog_light_color = Color(0.07, 0.05, 0.14)
	e.fog_density = 0.02
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)
	# ground strip that follows the player
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(lane_w * lane_count + 2.0, 400)
	ground.mesh = pm
	ground.material_override = _mat(Color(0.16, 0.13, 0.25))
	ground.name = "Ground"
	add_child(ground)
	# lane separator dashes (recycled)
	for k in 40:
		for s in range(lane_count + 1):
			var d := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.08, 0.02, 2.0)
			d.mesh = bm
			d.material_override = _mat(Color(0.55, 0.5, 0.85))
			d.set_meta("x", (s - lane_count * 0.5) * lane_w)
			d.set_meta("k", k)
			add_child(d)
			stripes.append(d)
	player = Node3D.new()
	add_child(player)
	player_mesh = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = player_w * 0.5
	cap.height = 1.6
	player_mesh.mesh = cap
	player_mesh.position.y = 0.8
	player_mat = _mat(Color(0.35, 0.8, 1.0), true)
	player_mesh.material_override = player_mat
	player.add_child(player_mesh)
	cam = Camera3D.new()
	cam.fov = base_fov
	add_child(cam)

func _label(size: int, pos: Vector2, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", Assets.FONT_UI)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.position = pos
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(l)
	return l

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	lbl_time = _label(44, Vector2(24, 20))
	lbl_count = _label(44, Vector2(24, 76))
	lbl_speed = _label(40, Vector2(24, 1180))
	lbl_center = _label(40, Vector2(0, 420), HORIZONTAL_ALIGNMENT_CENTER)
	lbl_center.size = Vector2(720, 400)
	lbl_center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_float = _label(64, Vector2(0, 300), HORIZONTAL_ALIGNMENT_CENTER)
	lbl_float.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_dev = _label(22, Vector2(380, 20))
	lbl_dev.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))

func _build_audio() -> void:
	voice = AudioStreamPlayer.new()
	add_child(voice)
	music = AudioStreamPlayer.new()
	var fb: Dictionary = cfg.get("feedback", {})
	music.stream = Assets.MUSIC.get(str(fb.get("music", "")))
	music.volume_db = float(fb.get("music_volume_db", -12.0))
	add_child(music)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_pool.append(p)

func sfx(name: String, pitch := 1.0, vol := 0.0) -> void:
	for p in sfx_pool:
		if not p.playing:
			p.stream = Assets.SFX.get(name)
			p.pitch_scale = pitch
			p.volume_db = vol
			p.play()
			return

# ---------------------------------------------------------------- run
func reset_run() -> void:
	for r in rows:
		if is_instance_valid(r.node):
			r.node.queue_free()
	rows.clear()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	elapsed = 0.0; penalty = 0.0; correct = 0; wrong = 0; missed = 0
	player_dist = 0.0; lane = 1; player_x = lane_x(lane); q_counter = 0; last_target = ""
	ctrl.reset()
	next_row_dist = first_row
	_spawn_rows()
	state = State.READY
	lbl_center.text = "%s\n\nHOLD = accelerate\nrelease = slow down\ndouble-tap & hold = brake\nswipe (while holding) = lane\n\nPC: Space/W hold, S brake, A/D lanes\nR = replay voice   F3 = dev timing\n\nTap / Space to start" % str(lvl.get("name", "Level 1"))
	lbl_float.text = ""
	if music.playing:
		music.stop()
	_update_view(0.0)
	_update_hud()

func start_run() -> void:
	state = State.RUNNING
	lbl_center.text = ""
	logger.start(level_id)
	if music.stream:
		music.play()
	_activate_next()

func clock() -> float:
	return elapsed + penalty

func _spawn_rows() -> void:
	while next_row_dist < player_dist + spawn_ahead:
		var r := Rules.make_row(lvl.get("kana", ["あ"]), last_target, rng, lane_count)
		last_target = r.kana[r.target]
		var node := Node3D.new()
		node.position = Vector3(0, 0, -next_row_dist)
		add_child(node)
		var stones: Array = []
		for i in r.kana.size():
			var st := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(stone_w, 1.8, 0.5)
			st.mesh = bm
			var m := _mat(Color(0.55, 0.52, 0.6), true)
			st.material_override = m
			st.position = Vector3(lane_x(i), 0.9, 0)
			var lab := Label3D.new()
			lab.text = r.kana[i]
			lab.font = Assets.FONT_KANA
			lab.font_size = 160
			lab.pixel_size = 0.006
			lab.outline_size = 24
			lab.position = Vector3(0, 0.1, 0.27)
			st.add_child(lab)
			node.add_child(st)
			stones.append(st)
		rows.append({"dist": next_row_dist, "kana": r.kana, "target": r.target, "node": node,
			"stones": stones, "resolved": false, "voice_t": -1.0, "q": 0})
		next_row_dist += row_spacing

func active_row():
	for r in rows:
		if not r.resolved:
			return r
	return null

func _activate_next() -> void:
	var r = active_row()
	if r == null or r.voice_t >= 0.0:
		return
	q_counter += 1
	r.q = q_counter
	r.voice_t = elapsed
	play_voice(r)

func play_voice(r) -> void:
	var idx: int = lvl.get("kana", []).find(r.kana[r.target])
	var romaji: String = lvl.get("romaji", [])[idx] if idx >= 0 else ""
	voice.stream = Assets.VOICE.get(romaji)
	if voice.stream:
		voice.play()

func _process(dt: float) -> void:
	if state == State.RUNNING:
		_tick(dt)
	elif state == State.CLEARED or state == State.FAILED:
		result_time += dt
	_update_view(dt)
	_update_hud()

func _tick(dt: float) -> void:
	if autopilot:
		ctrl.holding = true
		var ar = active_row()
		if ar != null:
			lane = ar.target
	ctrl.step(dt)
	elapsed += dt
	player_dist += ctrl.speed * dt
	player_x = move_toward(player_x, lane_x(lane), lane_change_speed * dt)
	_spawn_rows()
	var r = active_row()
	if r != null and player_dist >= r.dist:
		_resolve(r)
	# cleanup passed rows
	while rows.size() > 0 and rows[0].resolved and rows[0].dist < player_dist - 15.0:
		var old = rows.pop_front()
		if is_instance_valid(old.node):
			old.node.queue_free()
	if correct >= int(lvl.get("target_correct", 20)):
		_finish(true)
	elif clock() >= float(lvl.get("time_limit_s", 60.0)):
		_finish(false)

func _resolve(r) -> void:
	r.resolved = true
	var lane_xs: Array = []
	for i in r.kana.size():
		lane_xs.append(lane_x(i))
	var hit := Rules.hit_lane(player_x, lane_xs, player_w, stone_w)
	var reaction: float = elapsed - float(r.voice_t)
	var result := "miss"
	if hit == -1:
		missed += 1
		penalty += float(lvl.get("miss_penalty_s", 1.0))
		_fx_miss(r)
	elif hit == r.target:
		result = "correct"
		correct += 1
		_fx_correct(r.stones[hit])
	else:
		result = "wrong"
		wrong += 1
		penalty += float(lvl.get("wrong_penalty_s", 2.0))
		ctrl.scale_speed(float(cfg.get("speed", {}).get("wrong_hit_speed_factor", 0.5)))
		_fx_wrong(r.stones[hit], r.stones[r.target])
	logger.add(r.q, r.kana[r.target], result, reaction, ctrl.kmh(), clock())
	_activate_next()

func _finish(cleared: bool) -> void:
	state = State.CLEARED if cleared else State.FAILED
	result_time = 0.0
	ctrl.reset()
	music.stop()
	var stars := Rules.stars_for(clock(), lvl) if cleared else 0
	var star_txt := "STARS %d / 3" % stars
	if cleared:
		lbl_center.text = "CLEAR!\n%s\n\nTime %.2f s\n(run %.2f + penalty %.1f)\nwrong %d   miss %d\n\nTap / Space to retry" % [star_txt, clock(), elapsed, penalty, wrong, missed]
		sfx("shatter", 0.8, 2.0)
	else:
		lbl_center.text = "TIME UP\n%d / %d\n\nTap / Space to retry" % [correct, int(lvl.get("target_correct", 20))]
		sfx("back")
	if dev_mode:
		last_saved_path = logger.save("clear" if cleared else "fail", elapsed, clock(), stars)
		print("[dev] timing saved: ", last_saved_path)
	print("[result] %s clock=%.3f elapsed=%.3f penalty=%.1f correct=%d wrong=%d miss=%d stars=%d" % [
		"CLEAR" if cleared else "FAIL", clock(), elapsed, penalty, correct, wrong, missed, stars])

# ---------------------------------------------------------------- feedback
func _float_text(t: String, c: Color) -> void:
	lbl_float.text = t
	lbl_float.add_theme_color_override("font_color", c)
	lbl_float.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(lbl_float, "modulate:a", 0.0, 0.7).set_delay(0.25)

func _glow(st: MeshInstance3D, c: Color, energy: float, dur: float) -> void:
	var m: StandardMaterial3D = st.material_override
	m.emission = c
	m.albedo_color = c
	m.emission_energy_multiplier = energy
	var tw := create_tween()
	tw.tween_property(m, "emission_energy_multiplier", 0.0, dur)

func _fx_correct(st: MeshInstance3D) -> void:
	var fb: Dictionary = cfg.get("feedback", {})
	_glow(st, Color(1.0, 0.85, 0.3), float(fb.get("glow_strength", 4.0)), 0.5)
	# knockback: stone flies forward and tumbles away from the player
	var kb := float(fb.get("knockback_distance_m", 7.0))
	var side := signf(st.position.x) if absf(st.position.x) > 0.1 else (1.0 if rng.randf() > 0.5 else -1.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(st, "position", st.position + Vector3(side * 2.5, 2.5, -kb), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(st, "rotation", Vector3(-4.0, side * 3.0, side * 2.0), 0.45)
	tw.tween_property(st, "scale", Vector3.ONE * 0.2, 0.45).set_delay(0.15)
	_burst(st.global_position, Color(1.0, 0.85, 0.3))
	sfx("shatter", rng.randf_range(0.95, 1.1), 3.0)
	# player punch (scale pop) + tiny FOV punch, no camera shake
	var pt := create_tween()
	pt.tween_property(player_mesh, "scale", Vector3(1.25, 0.85, 1.25), 0.05)
	pt.tween_property(player_mesh, "scale", Vector3.ONE, 0.15)
	_glow_player(Color(1.0, 0.85, 0.3), 3.0)
	var fov_punch := float(fb.get("fov_punch_deg", 4.0))
	cam.fov = base_fov + fov_punch
	_float_text("○", Color(1.0, 0.9, 0.3))

func _fx_wrong(st: MeshInstance3D, right: MeshInstance3D) -> void:
	_glow(st, Color(1.0, 0.2, 0.2), 3.0, 0.6)
	_glow(right, Color(0.3, 1.0, 0.5), 1.5, 0.8)   # show which one was right
	var tw := create_tween()
	tw.tween_property(st, "position", st.position + Vector3(0, 0.3, -1.2), 0.08)
	tw.tween_property(st, "position", st.position + Vector3(0, 0, -0.8), 0.2)
	var pt := create_tween()
	pt.tween_property(player_mesh, "position:z", 0.6, 0.06)
	pt.tween_property(player_mesh, "position:z", 0.0, 0.25)
	_glow_player(Color(1.0, 0.2, 0.2), 2.5)
	sfx("miss", 1.0, 0.0)
	if bool(cfg.get("feedback", {}).get("screen_shake_on_normal_hit", false)):
		cam.h_offset = 0.15
	_float_text("-%ss  ×" % str(lvl.get("wrong_penalty_s", 2.0)), Color(1.0, 0.35, 0.35))

func _fx_miss(r) -> void:
	_glow(r.stones[r.target], Color(0.3, 1.0, 0.5), 1.5, 0.8)
	sfx("tick")
	_float_text("-%ss  MISS" % str(lvl.get("miss_penalty_s", 1.0)), Color(0.8, 0.8, 1.0))

func _glow_player(c: Color, e: float) -> void:
	player_mat.emission = c
	player_mat.emission_energy_multiplier = e
	var tw := create_tween()
	tw.tween_property(player_mat, "emission_energy_multiplier", 0.0, 0.35)

func _burst(at: Vector3, c: Color) -> void:
	var p := CPUParticles3D.new()
	add_child(p)
	p.global_position = at
	p.one_shot = true
	p.amount = 24
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector3(0, 0.5, -1)
	p.spread = 70.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0, -12, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.08; sm.height = 0.16
	p.mesh = sm
	var m := _mat(c, true)
	m.emission_energy_multiplier = 4.0
	p.material_override = m
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

# ---------------------------------------------------------------- view
func _update_view(dt: float) -> void:
	player.position = Vector3(player_x, 0, -player_dist)
	cam.position = Vector3(player_x * 0.4, 4.2, -player_dist + 7.0)
	cam.look_at(Vector3(player_x * 0.4, 0.5, -player_dist - 14.0))
	cam.fov = move_toward(cam.fov, base_fov + ctrl.kmh() * 0.08, 40.0 * dt)
	cam.h_offset = move_toward(cam.h_offset, 0.0, dt)
	var g := get_node("Ground") as Node3D
	g.position.z = -player_dist - 150.0
	for d in stripes:
		var k: int = d.get_meta("k")
		var z := -(floorf(player_dist / 5.0) * 5.0 + k * 5.0 - 10.0)
		d.position = Vector3(d.get_meta("x"), 0.01, z)

func _update_hud() -> void:
	var limit := float(lvl.get("time_limit_s", 60.0))
	lbl_time.text = "TIME %.1f / %d" % [clock(), int(limit)]
	lbl_count.text = "%d / %d" % [correct, int(lvl.get("target_correct", 20))]
	var mode := "BRAKE" if ctrl.is_braking() else ("ACCEL" if ctrl.is_accelerating() else "")
	lbl_speed.text = "%3d km/h  %s" % [roundi(ctrl.kmh()), mode]
	lbl_dev.visible = dev_mode
	if dev_mode:
		var last := ""
		if logger.entries.size() > 0:
			var e: Dictionary = logger.entries[-1]
			last = "last Q%d %s %s %.2fs" % [e.q, e.target, e.result, e.reaction_s]
		lbl_dev.text = "[DEV TIMING]\nrun %.2f  pen %.1f\ndist %.1f m\nspeed %.1f km/h\n%s\navg ok %.2fs\nW%d M%d\n%s" % [
			elapsed, penalty, player_dist, ctrl.kmh(), last, logger.avg_reaction(), wrong, missed,
			("saved: " + last_saved_path.get_file()) if last_saved_path != "" else ""]

# ---------------------------------------------------------------- input
func _primary_down() -> void:
	if state == State.READY:
		start_run()
	elif state != State.RUNNING:
		if result_time > 0.6:
			reset_run()
		return
	ctrl.press()

func _primary_up() -> void:
	ctrl.release()

func change_lane(dir: int) -> void:
	var n := clampi(lane + dir, 0, lane_count - 1)
	if n != lane:
		lane = n
		sfx("shift", 1.0, -4.0)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed and touch_id == -1:
			touch_id = ev.index
			touch_anchor = ev.position
			_primary_down()
		elif not ev.pressed and ev.index == touch_id:
			touch_id = -1
			_primary_up()
	elif ev is InputEventScreenDrag and ev.index == touch_id:
		if ctrl.holding and state == State.RUNNING:
			var dx: float = ev.position.x - touch_anchor.x
			if absf(dx) >= swipe_min:
				change_lane(1 if dx > 0 else -1)
				touch_anchor = ev.position
	elif ev is InputEventKey and not ev.echo:
		match ev.keycode:
			KEY_SPACE, KEY_W, KEY_UP:
				if ev.pressed: _primary_down()
				else: _primary_up()
			KEY_S, KEY_DOWN:
				ctrl.key_brake = ev.pressed
			KEY_A, KEY_LEFT:
				if ev.pressed and state == State.RUNNING and (ctrl.holding or not key_lane_needs_hold):
					change_lane(-1)
			KEY_D, KEY_RIGHT:
				if ev.pressed and state == State.RUNNING and (ctrl.holding or not key_lane_needs_hold):
					change_lane(1)
			KEY_R:
				if ev.pressed and state == State.RUNNING:
					var r = active_row()
					if r != null: play_voice(r)
			KEY_F3:
				if ev.pressed: dev_mode = not dev_mode
