extends Node3D
## Kana Run 2.0 - Level 1 prototype.
## Everything (world, HUD, audio) is built in code so the scene file stays
## trivial and easy to merge. Tunables live in config/game_config.json.

const GameConfig = preload("res://scripts/game_config.gd")
const SpeedController = preload("res://scripts/speed_controller.gd")
const Rules = preload("res://scripts/rules.gd")
const DevLogger = preload("res://scripts/dev_logger.gd")
const Assets = preload("res://scripts/asset_manifest.gd")
const SaveData = preload("res://scripts/save_data.gd")

## HP hooks for later upgrades: (hp, max_hp, shield)
signal hp_changed(hp: int, max_hp: int, shield: int)
## Emitted when damage is taken (amount) or blocked by a shield (amount 0).
signal damaged(amount: int, blocked: bool)

enum State { SELECT, READY, RUNNING, PAUSED, CLEARED, FAILED }

var level_id := "level_01"
var level_index := 0
var levels: Array = []
var save = SaveData.new()
## Tests point this at a scratch file.
var save_path := "user://save.json"
## Tests set this to skip the level-select screen on start.
var skip_select := false
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
var combo := 0
var best_combo := 0
var appearances := {}
var voice_only_announced := false
var requeue: Array = []
var hint_first_n := 3
var hint_ratio := 0.5

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

# touch
## index -> {"role": "accel"|"brake"|"swipe", "anchor": Vector2}
var touches := {}
var pause_count := 0
# HP
var hp := 3
var max_hp := 3
var base_max_hp := 3
var max_hp_bonus := 0     # hook: upgrades add to this via set_max_hp_bonus()
var shield := 0           # hook: a charm that blocks the next damage
var miss_costs_heart := false
var wrong_damage := 1
var fail_reason := ""     # "", "time_up", "hp_out"
var hearts_box: HBoxContainer
var lbl_shield: Label
var _js_visibility_cb   # keeps the JavaScriptBridge callback alive (web)

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
var lbl_hint: Label
var lbl_combo: Label
var lbl_notice: Label
var results_box: Control
var lbl_result: Label
var btn_retry: Button
var btn_next: Button
var btn_select: Button
var select_box: Control
var select_list: VBoxContainer
var level_buttons: Array = []
var btn_accel: Panel
var btn_brake: Panel
var btn_pause: Panel
var btn_voice: Panel
var pause_box: Control
var btn_resume: Button
var btn_restart: Button
var btn_quit: Button

func _ready() -> void:
	cfg = GameConfig.load_config()
	levels = GameConfig.levels(cfg)
	save.path = save_path
	save.load_file()
	ctrl.configure(cfg.get("speed", {}))
	var L: Dictionary = cfg.get("lanes", {})
	lane_count = int(L.get("count", 3))
	lane_w = float(L.get("lane_width_m", 2.2))
	lane_change_speed = lane_w / maxf(0.01, float(L.get("lane_change_time_s", 0.16)))
	swipe_min = float(L.get("swipe_min_px", 40))
	player_w = float(L.get("player_width_m", 0.9))
	stone_w = float(L.get("stone_width_m", 1.2))
	var T: Dictionary = cfg.get("track", {})
	row_spacing = float(T.get("row_spacing_m", 24.0))
	first_row = float(T.get("first_row_m", 30.0))
	spawn_ahead = float(T.get("spawn_ahead_m", 80.0))
	dev_mode = force_dev_mode or bool(cfg.get("dev", {}).get("timing_mode", false)) \
		or OS.get_cmdline_user_args().has("--dev")
	_build_world()
	_build_hud()
	_build_audio()
	_setup_web_visibility()
	set_level(level_index)
	reset_run()
	if not skip_select:
		show_select()

## Switch level (data from config "levels" array). Per-level hint overrides allowed.
func set_level(i: int) -> void:
	level_index = clampi(i, 0, levels.size() - 1)
	lvl = levels[level_index]
	level_id = str(lvl.get("id", "level_%02d" % (level_index + 1)))
	var H: Dictionary = cfg.get("hints", {})
	hint_first_n = int(lvl.get("romaji_first_n", H.get("romaji_first_n", 3)))
	hint_ratio = float(lvl.get("voice_only_after_progress", H.get("voice_only_after_progress", 0.5)))
	var HP: Dictionary = cfg.get("hp", {})
	base_max_hp = maxi(1, int(lvl.get("max_hp", HP.get("max_hp", 3))))
	miss_costs_heart = bool(lvl.get("miss_costs_heart", HP.get("miss_costs_heart", false)))
	wrong_damage = int(lvl.get("wrong_damage", HP.get("wrong_damage", 1)))

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

## All HUD controls are anchored to the viewport (no fixed 720-px design widths),
## so they stay correct when the window / web canvas is wider or narrower.
func _label(size: int, align := HORIZONTAL_ALIGNMENT_LEFT, font: Font = null) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font if font else Assets.FONT_HUD)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(l)
	return l

static func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, o_r: float, ob: float) -> void:
	c.anchor_left = al; c.anchor_top = at; c.anchor_right = ar; c.anchor_bottom = ab
	c.offset_left = ol; c.offset_top = ot; c.offset_right = o_r; c.offset_bottom = ob

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", Assets.FONT_HUD)
	b.add_theme_font_size_override("font_size", 36)
	b.custom_minimum_size = Vector2(180, 72)
	b.focus_mode = Control.FOCUS_NONE
	return b

func _panel_center() -> Array:
	var cc := CenterContainer.new()
	_place(cc, 0, 0, 1, 1, 0, 0, 0, 0)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(cc)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.12, 0.85)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(28)
	pc.add_theme_stylebox_override("panel", sb)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(vb)
	return [cc, vb]

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	lbl_time = _label(40);  _place(lbl_time, 0, 0, 0.5, 0, 24, 10, 0, 66)
	lbl_count = _label(40); _place(lbl_count, 0, 0, 0.5, 0, 24, 70, 0, 124)
	hearts_box = HBoxContainer.new()
	hearts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hearts_box.add_theme_constant_override("separation", 6)
	hud.add_child(hearts_box)
	_place(hearts_box, 0, 0, 0, 0, 24, 136, 380, 196)
	lbl_shield = _label(34)
	lbl_shield.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	lbl_shield.reparent(hearts_box)
	lbl_speed = _label(36, HORIZONTAL_ALIGNMENT_CENTER); _place(lbl_speed, 0.5, 1, 0.5, 1, -170, -90, 170, -36)
	lbl_combo = _label(52, HORIZONTAL_ALIGNMENT_CENTER); _place(lbl_combo, 0.5, 1, 0.5, 1, -200, -170, 200, -100)
	lbl_combo.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	lbl_hint = _label(96, HORIZONTAL_ALIGNMENT_CENTER); _place(lbl_hint, 0, 0, 1, 0, 0, 130, 0, 250)
	lbl_hint.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	lbl_float = _label(64, HORIZONTAL_ALIGNMENT_CENTER); _place(lbl_float, 0, 0, 1, 0, 0, 260, 0, 340)
	lbl_notice = _label(72, HORIZONTAL_ALIGNMENT_CENTER); _place(lbl_notice, 0, 0.42, 1, 0.42, 0, -50, 0, 50)
	lbl_notice.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	lbl_center = _label(34, HORIZONTAL_ALIGNMENT_CENTER); _place(lbl_center, 0, 0, 1, 1, 20, 120, -20, -110)
	lbl_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_dev = _label(22, HORIZONTAL_ALIGNMENT_LEFT, Assets.FONT_UI); _place(lbl_dev, 1, 0, 1, 0, -340, 240, -10, 530)
	lbl_dev.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl_dev.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	# touch buttons (hit-tested by hand in _input so several fingers work at once)
	btn_brake = _touch_button("煞車", 40, Color(0.9, 0.3, 0.3)); _place(btn_brake, 0, 1, 0, 1, 24, -244, 224, -44)
	btn_accel = _touch_button("加速", 48, Color(0.3, 0.85, 0.5)); _place(btn_accel, 1, 1, 1, 1, -264, -284, -24, -44)
	btn_pause = _touch_button("II", 40, Color(0.7, 0.7, 0.9)); _place(btn_pause, 1, 0, 1, 0, -120, 16, -24, 112)
	btn_voice = _touch_button("重播", 30, Color(1.0, 0.85, 0.4)); _place(btn_voice, 1, 0, 1, 0, -120, 124, -24, 220)
	# pause menu
	var pm := _panel_center()
	pause_box = pm[0]
	var pt := Label.new()
	pt.text = "暫停"
	pt.add_theme_font_override("font", Assets.FONT_HUD)
	pt.add_theme_font_size_override("font_size", 52)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pm[1].add_child(pt)
	btn_resume = _button("繼續"); btn_restart = _button("重來"); btn_quit = _button("回選關")
	for b in [btn_resume, btn_restart, btn_quit]:
		b.custom_minimum_size = Vector2(320, 80)
		pm[1].add_child(b)
	btn_resume.pressed.connect(resume)
	btn_restart.pressed.connect(func(): reset_run())
	btn_quit.pressed.connect(show_select)
	pause_box.visible = false
	# results
	var r := _panel_center()
	results_box = r[0]
	lbl_result = Label.new()
	lbl_result.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_result.add_theme_font_size_override("font_size", 36)
	lbl_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r[1].add_child(lbl_result)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	r[1].add_child(hb)
	btn_retry = _button("重玩"); btn_next = _button("下一關"); btn_select = _button("回選關")
	for b in [btn_retry, btn_next, btn_select]:
		hb.add_child(b)
	btn_retry.pressed.connect(func(): reset_run())
	btn_next.pressed.connect(go_next_level)
	btn_select.pressed.connect(show_select)
	results_box.visible = false
	# level select
	var sp := _panel_center()
	select_box = sp[0]
	select_list = sp[1]
	select_box.visible = false

func _touch_button(text: String, size: int, col: Color) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.28)
	sb.border_color = Color(col.r, col.g, col.b, 0.9)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(120)
	p.add_theme_stylebox_override("panel", sb)
	hud.add_child(p)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Assets.FONT_HUD)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(l, 0, 0, 1, 1, 0, 0, 0, 0)
	p.add_child(l)
	return p

func _set_btn_lit(p: Panel, lit: bool) -> void:
	p.modulate = Color(1.6, 1.6, 1.6) if lit else Color.WHITE

# ---------------------------------------------------------------- HP
## Upgrade hook: extra max hearts (e.g. from an upgrade). refill = also fill to the new max.
func set_max_hp_bonus(bonus: int, refill := true) -> void:
	max_hp_bonus = maxi(0, bonus)
	set_max_hp(base_max_hp + max_hp_bonus, refill)

func set_max_hp(n: int, refill := false) -> void:
	max_hp = maxi(1, n)
	hp = max_hp if refill else mini(hp, max_hp)
	_emit_hp()

## Charm hook: each shield point blocks one future damage.
func add_shield(n := 1) -> void:
	shield = maxi(0, shield + n)
	_emit_hp()

## Heal hook (+1 heart etc.), capped at max_hp.
func heal(n := 1) -> void:
	hp = mini(max_hp, hp + maxi(0, n))
	_emit_hp()

## Applies damage. Returns true if a heart was actually lost. Ends the run at 0.
func take_damage(n := 1) -> bool:
	if n <= 0:
		return false
	if shield > 0:
		shield -= 1
		damaged.emit(0, true)
		_emit_hp()
		_hearts_fx(Color(0.6, 0.85, 1.0))
		return false
	hp = maxi(0, hp - n)
	damaged.emit(n, false)
	_emit_hp()
	_hearts_fx(Color(1.0, 0.25, 0.25))
	if hp <= 0 and state == State.RUNNING:
		_finish(false, "hp_out")
	return true

func _emit_hp() -> void:
	_rebuild_hearts()
	hp_changed.emit(hp, max_hp, shield)

func _rebuild_hearts() -> void:
	if hearts_box == null:
		return
	for c in hearts_box.get_children():
		if c != lbl_shield:
			hearts_box.remove_child(c)
			c.queue_free()
	for i in max_hp:
		var l := Label.new()
		l.text = "♥" if i < hp else "♡"
		l.add_theme_font_override("font", Assets.FONT_HUD)
		l.add_theme_font_size_override("font_size", 44)
		l.add_theme_color_override("font_color", Color(1.0, 0.35, 0.45) if i < hp else Color(0.6, 0.55, 0.65))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hearts_box.add_child(l)
	hearts_box.move_child(lbl_shield, -1)
	lbl_shield.text = ("盾×%d" % shield) if shield > 0 else ""

## Flash + shake of the heart icons only (never the camera / screen).
func _hearts_fx(col: Color) -> void:
	if hearts_box == null:
		return
	hearts_box.modulate = col * 1.6
	var tw := create_tween()
	tw.tween_property(hearts_box, "modulate", Color.WHITE, 0.4)
	var x0 := 24.0
	var sh := create_tween()
	for d in [10.0, -8.0, 6.0, -4.0, 0.0]:
		sh.tween_property(hearts_box, "offset_left", x0 + d, 0.04)
	sh.parallel().tween_property(hearts_box, "offset_right", 380.0, 0.01)

# ---------------------------------------------------------------- pause
func pause_game() -> void:
	if state != State.RUNNING:
		return
	state = State.PAUSED
	pause_count += 1
	_release_inputs()
	voice.stream_paused = true
	music.stream_paused = true
	pause_box.visible = true

func resume() -> void:
	if state != State.PAUSED:
		return
	_release_inputs()
	pause_box.visible = false
	voice.stream_paused = false
	music.stream_paused = false
	state = State.RUNNING

func _release_inputs() -> void:
	ctrl.release_all()
	touches.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if state == State.RUNNING:
			pause_game()
		else:
			_release_inputs()

func _setup_web_visibility() -> void:
	if not OS.has_feature("web"):
		return
	var doc = JavaScriptBridge.get_interface("document")
	if doc == null:
		return
	_js_visibility_cb = JavaScriptBridge.create_callback(_on_js_visibility)
	doc.addEventListener("visibilitychange", _js_visibility_cb)

func _on_js_visibility(_args) -> void:
	var doc = JavaScriptBridge.get_interface("document")
	if doc != null and doc.hidden:
		_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)

func show_select() -> void:
	pause_box.visible = false
	voice.stream_paused = false
	music.stream_paused = false
	touches.clear()
	state = State.SELECT
	ctrl.reset()
	if music.playing:
		music.stop()
	results_box.visible = false
	lbl_center.text = ""
	lbl_hint.text = ""
	for c in select_list.get_children():
		c.queue_free()
	level_buttons.clear()
	var title := Label.new()
	title.text = "選關"
	title.add_theme_font_override("font", Assets.FONT_HUD)
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	select_list.add_child(title)
	for i in levels.size():
		var L: Dictionary = levels[i]
		var id := str(L.get("id"))
		var unlocked := save.is_unlocked(levels, i)
		var rec: Dictionary = save.get_record(id)
		var txt := "%s" % str(L.get("name", id))
		if not unlocked:
			txt += "   鎖定"
		elif rec.get("best_time", -1.0) >= 0.0:
			txt += "   %s  %.1fs" % [_stars_text(int(rec.get("best_stars", 0))), float(rec.best_time)]
		var b := _button(txt)
		b.custom_minimum_size = Vector2(480, 84)
		b.disabled = not unlocked
		b.pressed.connect(choose_level.bind(i))
		select_list.add_child(b)
		level_buttons.append(b)
	select_box.visible = true

func choose_level(i: int) -> void:
	if not save.is_unlocked(levels, i):
		return
	select_box.visible = false
	set_level(i)
	reset_run()

func go_next_level() -> void:
	if can_go_next():
		choose_level(level_index + 1)

func can_go_next() -> bool:
	return level_index + 1 < levels.size() and save.is_unlocked(levels, level_index + 1)

static func _stars_text(n: int) -> String:
	var t := ""
	for i in 3:
		t += "★" if i < n else "☆"
	return t

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
	appearances.clear(); requeue.clear(); voice_only_announced = false
	_set_combo(0); best_combo = 0
	fail_reason = ""
	shield = 0
	max_hp = base_max_hp + max_hp_bonus
	hp = max_hp
	_emit_hp()
	lbl_hint.text = ""; lbl_notice.text = ""
	_spawn_rows()
	state = State.READY
	results_box.visible = false
	select_box.visible = false
	pause_box.visible = false
	voice.stream_paused = false
	music.stream_paused = false
	touches.clear()
	lbl_center.text = "%s\n\n按住「加速」加速、按住「煞車」煞車\n都不按 = 自然減速\n左右滑動換線（按著加速時也可以）\n\nPC: W/Space 加速, S 煞車, A/D 換線\nE 重播  Esc/P 暫停  F3 dev\n\nTap / Space to start" % str(lvl.get("name", "Level 1"))
	lbl_float.text = ""
	if music.playing:
		music.stop()
	_update_view(0.0)
	_update_hud()

func start_run() -> void:
	state = State.RUNNING
	select_box.visible = false
	results_box.visible = false
	lbl_center.text = ""
	logger.start(level_id)
	if music.stream:
		music.play()
	_activate_next()

func clock() -> float:
	return elapsed + penalty

func _spawn_rows() -> void:
	var pool: Array = lvl.get("kana", ["あ"])
	while next_row_dist < player_dist + spawn_ahead:
		var r: Dictionary
		if requeue.size() > 0:
			r = Rules.make_row_with_target(pool, requeue.pop_front(), -1, rng, lane_count)
		else:
			r = Rules.make_row(pool, last_target, rng, lane_count)
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
			st.material_override = _mat(Color(0.55, 0.52, 0.6), true)
			st.position = Vector3(lane_x(i), 0.9, 0)
			var lab := Label3D.new()
			lab.name = "Kana"
			lab.font = Assets.FONT_KANA
			lab.font_size = 160
			lab.pixel_size = 0.006
			lab.outline_size = 24
			lab.position = Vector3(0, 0.1, 0.27)
			st.add_child(lab)
			node.add_child(st)
			stones.append(st)
		var row := {"dist": next_row_dist, "kana": r.kana, "target": r.target, "node": node,
			"stones": stones, "resolved": false, "voice_t": -1.0, "q": 0, "hint": false, "retry": false}
		_apply_row_labels(row)
		rows.append(row)
		next_row_dist += row_spacing

func _apply_row_labels(row: Dictionary) -> void:
	for i in row.stones.size():
		(row.stones[i].get_node("Kana") as Label3D).text = row.kana[i]

## Wrong hit: the next row becomes the same question with the correct kana in a different lane.
func _retry_in_next_row(after_row: Dictionary, kana: String, avoid_lane: int) -> void:
	var idx := rows.find(after_row)
	for j in range(idx + 1, rows.size()):
		var nxt: Dictionary = rows[j]
		if nxt.resolved or nxt.voice_t >= 0.0:
			continue
		var r := Rules.make_row_with_target(lvl.get("kana", ["あ"]), kana, avoid_lane, rng, lane_count)
		nxt.kana = r.kana
		nxt.target = r.target
		nxt.retry = true
		_apply_row_labels(nxt)
		return

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
	var k: String = r.kana[r.target]
	var seen: int = appearances.get(k, 0)
	appearances[k] = seen + 1
	var progress := float(correct) / maxf(1.0, float(lvl.get("target_correct", 20)))
	r.hint = Rules.hint_visible(seen, hint_first_n, progress, hint_ratio)
	if progress >= hint_ratio and not voice_only_announced:
		voice_only_announced = true
		_notice("聽音模式")
	lbl_hint.text = _romaji(k) if r.hint else "?"
	lbl_hint.modulate.a = 1.0 if r.hint else 0.6
	play_voice(r)

func _romaji(k: String) -> String:
	var idx: int = lvl.get("kana", []).find(k)
	return lvl.get("romaji", [])[idx] if idx >= 0 else ""

func _notice(t: String) -> void:
	lbl_notice.text = t
	lbl_notice.modulate.a = 1.0
	lbl_notice.pivot_offset = lbl_notice.size * 0.5   # scale around the centre, not the left edge
	lbl_notice.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(lbl_notice, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl_notice, "modulate:a", 0.0, 0.6).set_delay(1.4)

func _set_combo(v: int) -> void:
	combo = v
	best_combo = maxi(best_combo, combo)
	lbl_combo.text = ("%d 連擊" % combo) if combo >= 2 else ""
	if combo >= 2:
		lbl_combo.pivot_offset = lbl_combo.size * 0.5
		lbl_combo.scale = Vector2(1.5, 1.5)
		var tw := create_tween()
		tw.tween_property(lbl_combo, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	if state != State.RUNNING:
		return
	if correct >= int(lvl.get("target_correct", 20)):
		_finish(true)
	elif clock() >= float(lvl.get("time_limit_s", 60.0)):
		_finish(false, "time_up")

func _resolve(r) -> void:
	r.resolved = true
	var lane_xs: Array = []
	for i in r.kana.size():
		lane_xs.append(lane_x(i))
	var hit := Rules.hit_lane(player_x, lane_xs, player_w, stone_w)
	var reaction: float = elapsed - float(r.voice_t)
	var k: String = r.kana[r.target]
	var result := "miss"
	if hit == -1:
		missed += 1
		penalty += float(lvl.get("miss_penalty_s", 1.0))
		requeue.append(k)          # comes back later (next newly spawned row)
		_set_combo(0)
		_fx_miss(r)
		if miss_costs_heart:
			take_damage(1)
	elif hit == r.target:
		result = "correct"
		correct += 1
		_set_combo(combo + 1)
		_fx_correct(r.stones[hit])
	else:
		result = "wrong"
		wrong += 1
		penalty += float(lvl.get("wrong_penalty_s", 2.0))
		ctrl.scale_speed(float(cfg.get("speed", {}).get("wrong_hit_speed_factor", 0.5)))
		_set_combo(0)
		_fx_wrong(r.stones[hit], r.stones[r.target])
		_retry_in_next_row(r, k, r.target)
		take_damage(wrong_damage)
	logger.add(r.q, k, result, reaction, ctrl.kmh(), clock())
	if state == State.RUNNING:
		_activate_next()

func _finish(cleared: bool, reason := "") -> void:
	fail_reason = "" if cleared else (reason if reason != "" else "time_up")
	state = State.CLEARED if cleared else State.FAILED
	result_time = 0.0
	ctrl.reset()
	music.stop()
	var stars := Rules.stars_for(clock(), lvl) if cleared else 0
	var new_best := false
	if cleared:
		new_best = save.record(level_id, stars, clock())
		save.save_file()
		lbl_result.text = "CLEAR!\n%s\n\nTime %.2f s\n(run %.2f + penalty %.1f)\nwrong %d   miss %d\nbest combo %d%s" % [
			_stars_text(stars), clock(), elapsed, penalty, wrong, missed, best_combo, "\n新紀錄！" if new_best else ""]
		sfx("shatter", 0.8, 2.0)
	else:
		lbl_result.text = "%s\n%d / %d" % ["體力耗盡" if fail_reason == "hp_out" else "時間到", correct, int(lvl.get("target_correct", 20))]
		sfx("back")
	lbl_center.text = ""
	lbl_hint.text = ""
	btn_next.visible = level_index + 1 < levels.size()
	btn_next.disabled = not can_go_next()
	pause_box.visible = false
	touches.clear()
	results_box.visible = true
	if dev_mode:
		last_saved_path = logger.save("clear" if cleared else fail_reason, elapsed, clock(), stars, hp)
		print("[dev] timing saved: ", last_saved_path)
	print("[result] %s %s%s clock=%.3f elapsed=%.3f penalty=%.1f correct=%d wrong=%d miss=%d stars=%d" % [
		level_id, "CLEAR" if cleared else "FAIL", "" if cleared else "(" + fail_reason + ")", clock(), elapsed, penalty, correct, wrong, missed, stars])

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
	# keep pop-scale pivots centred even if the window was resized mid-animation
	lbl_notice.pivot_offset = lbl_notice.size * 0.5
	lbl_combo.pivot_offset = lbl_combo.size * 0.5
	var in_game := state != State.SELECT
	lbl_time.visible = in_game; lbl_count.visible = in_game; lbl_speed.visible = in_game
	var playing := state == State.RUNNING or state == State.READY
	for b in [btn_accel, btn_brake, btn_pause, btn_voice]:
		b.visible = playing
	_set_btn_lit(btn_accel, ctrl.is_accelerating())
	_set_btn_lit(btn_brake, ctrl.is_braking())
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
func change_lane(dir: int) -> void:
	var n := clampi(lane + dir, 0, lane_count - 1)
	if n != lane:
		lane = n
		sfx("shift", 1.0, -4.0)

func replay_voice() -> void:
	if state == State.RUNNING:
		var r = active_row()
		if r != null:
			play_voice(r)

func _hit(c: Control, pos: Vector2) -> bool:
	return c.visible and c.get_global_rect().grow(8.0).has_point(pos)

func _accel_touch_count() -> int:
	var n := 0
	for t in touches.values():
		if t.role == "accel": n += 1
	return n

func _brake_touch_count() -> int:
	var n := 0
	for t in touches.values():
		if t.role == "brake": n += 1
	return n

## Multi-touch: each finger is tracked by index. A finger that starts on a
## button drives that button; any other finger swipes. The accelerate finger
## can also swipe sideways to change lanes while staying on the gas.
func _touch(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if state == State.RUNNING and _hit(btn_pause, ev.position):
				pause_game(); return
			if state == State.RUNNING and _hit(btn_voice, ev.position):
				replay_voice(); return
			if state == State.READY:
				start_run()
			if state != State.RUNNING:
				return
			var role := "swipe"
			if _hit(btn_accel, ev.position): role = "accel"
			elif _hit(btn_brake, ev.position): role = "brake"
			touches[ev.index] = {"role": role, "anchor": ev.position}
			if role == "accel": ctrl.press()
			elif role == "brake": ctrl.brake_press()
		else:
			if not touches.has(ev.index):
				return
			var t: Dictionary = touches[ev.index]
			touches.erase(ev.index)
			if t.role == "accel" and _accel_touch_count() == 0: ctrl.release()
			elif t.role == "brake" and _brake_touch_count() == 0: ctrl.brake_release()
	elif ev is InputEventScreenDrag:
		if state != State.RUNNING or not touches.has(ev.index):
			return
		var t: Dictionary = touches[ev.index]
		if t.role == "brake":
			return
		var dx: float = ev.position.x - t.anchor.x
		if absf(dx) >= swipe_min:
			change_lane(1 if dx > 0 else -1)
			t.anchor = ev.position

func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		if state == State.READY or state == State.RUNNING:
			_touch(ev)
			get_viewport().set_input_as_handled()

func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or ev.echo:
		return
	var in_result := state == State.CLEARED or state == State.FAILED
	match ev.keycode:
		KEY_SPACE, KEY_W, KEY_UP, KEY_ENTER:
			if ev.pressed:
				if in_result:
					if result_time > 0.4: reset_run()
				elif state == State.READY:
					start_run(); ctrl.press()
				elif state == State.RUNNING:
					ctrl.press()
			else:
				ctrl.release()
		KEY_S, KEY_DOWN:
			if ev.pressed and state == State.RUNNING: ctrl.brake_press()
			elif not ev.pressed: ctrl.brake_release()
		KEY_A, KEY_LEFT:
			if ev.pressed and state == State.RUNNING: change_lane(-1)
		KEY_D, KEY_RIGHT:
			if ev.pressed and state == State.RUNNING: change_lane(1)
		KEY_E:
			if ev.pressed: replay_voice()
		KEY_ESCAPE, KEY_P:
			if ev.pressed:
				if state == State.RUNNING: pause_game()
				elif state == State.PAUSED: resume()
				elif ev.keycode == KEY_ESCAPE: show_select()
		KEY_R:
			if ev.pressed and state == State.PAUSED: reset_run()
		KEY_Q:
			if ev.pressed and state == State.PAUSED: show_select()
		KEY_B:
			if ev.pressed and (in_result or state == State.READY): show_select()
		KEY_N:
			if ev.pressed and in_result: go_next_level()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			if ev.pressed and state == State.SELECT: choose_level(ev.keycode - KEY_1)
		KEY_F3:
			if ev.pressed: dev_mode = not dev_mode
