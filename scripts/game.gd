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
const LevelDB = preload("res://scripts/level_db.gd")
const Art = preload("res://scripts/art_manifest.gd")
const RunnerSprite = preload("res://scripts/runner_sprite.gd")

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
## "race" (賽車) or "step" (點放). Saved in save.json settings. Tests may force it.
var speed_mode := "race"
var force_mode := ""
var btn_lock: Panel
var btn_mode_pause: Button
var settings_box: Control
var btn_settings: Button
var btn_mode_race: Button
var btn_mode_step: Button
var btn_settings_back: Button
# HP
var hp := 100
var max_hp := 100
var base_max_hp := 100
var max_hp_bonus := 0         # hook: upgrades add max HP via set_max_hp_bonus(value)
var damage_reduction := 0.0   # hook: percent (0..90) taken off every hit
var shield := 0               # hook: a charm; each point blocks one whole hit
var wrong_damage := 35
var miss_damage := 0
var hp_delayed := 100.0       # the red "chunk" that drains after a short wait
var hp_delay_wait := 0.0
var bar_wait_s := 0.45
var bar_drain := 60.0
var fail_reason := ""     # "", "time_up", "hp_out"
var hearts_box: Control       # HP widget (heart icon + bar + number), top-left
var hp_fill: NinePatchRect
var hp_chunk: NinePatchRect
var timer_panel: NinePatchRect
var combo_badge: NinePatchRect
var speedo: Control
var speedo_needle: TextureRect
var lbl_lock_kmh: Label
var shield_box: Control
var shield_pips: HBoxContainer
var judge: TextureRect
var go_box: Control
var sel_bg: TextureRect
var res_bg: TextureRect
var res_stars: HBoxContainer
var res_badge: TextureRect
const INK := Color(0.23, 0.16, 0.33)
var lbl_hp: Label
var lbl_shield: Label
# distance / points / review / boss shield
var distance := "short"
var force_distance := ""
var review_ratio := 0.2
var lookalikes := {}
var same_sound: Array = []
var shield_thresholds: Array = []
var shield_phase := 0         # how many thresholds have been triggered
var boss_shield_up := false
var break_chain := 2
var break_progress := 0
var shields_broken := 0
var last_points := 0
var last_record := {}
var review_asked := 0
var select_tab := "hira"
var select_scroll: ScrollContainer
var btn_distance: Button
var btn_tab_hira: Button
var btn_tab_kata: Button
var lbl_points: Label
var lbl_boss: Label
var _js_visibility_cb   # keeps the JavaScriptBridge callback alive (web)

# nodes
var player: Node3D
var player_mesh: MeshInstance3D
var runner          # RunnerSprite (batch07 sheets)
var bg_layer: CanvasLayer
var sky_rect: TextureRect
var far_rect: TextureRect
var props: Array = []
var prop_rng := RandomNumberGenerator.new()   # separate: never touches the question rng
var next_prop := {"mid_l": 0.0, "mid_r": 0.0, "near_l": 0.0, "near_r": 0.0}
var road_mats: Array = []
var petals: CPUParticles2D
var fx_layer: CanvasLayer
const TRACK_TILE_M := 6.6
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
	var HPc: Dictionary = cfg.get("hp", {})
	bar_wait_s = float(HPc.get("delayed_bar_wait_s", 0.45))
	bar_drain = float(HPc.get("delayed_bar_drain_per_s", 60.0))
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
	var m: String = force_mode if force_mode != "" else str(save.get_setting("speed_mode", cfg.get("speed", {}).get("default_mode", "race")))
	set_speed_mode(m, false)
	lookalikes = cfg.get("kata_lookalikes", {})
	same_sound = cfg.get("same_sound", [])
	review_ratio = float(cfg.get("review", {}).get("ratio", 0.2))
	set_distance(force_distance if force_distance != "" else str(save.get_setting("distance", cfg.get("distances", {}).get("default", "short"))), false)
	set_level(level_index)
	reset_run()
	if not skip_select:
		show_select()

## Switch level. Effective data (kana pool, required count, limits) comes from LevelDB for the current distance.
func set_level(i: int) -> void:
	level_index = clampi(i, 0, levels.size() - 1)
	lvl = LevelDB.effective(cfg, levels, level_index, distance)
	level_id = str(lvl.get("id", "level_%02d" % (level_index + 1)))
	var H: Dictionary = cfg.get("hints", {})
	hint_first_n = int(lvl.get("romaji_first_n", H.get("romaji_first_n", 3)))
	hint_ratio = float(lvl.get("voice_only_after_progress", H.get("voice_only_after_progress", 0.5)))
	var HP: Dictionary = cfg.get("hp", {})
	base_max_hp = maxi(1, int(lvl.get("max_hp", HP.get("max_hp", 100))))
	wrong_damage = int(lvl.get("wrong_damage", HP.get("wrong_damage", 35)))
	miss_damage = int(lvl.get("miss_damage", HP.get("miss_damage", 0)))
	damage_reduction = float(HP.get("damage_reduction_pct", 0.0)) if damage_reduction == 0.0 else damage_reduction
	var BS: Dictionary = cfg.get("boss_shield", {})
	shield_thresholds = []
	var typ := str(lvl.get("type", "normal"))
	if bool(BS.get("enabled", true)) and typ != "normal":
		shield_thresholds = lvl.get("shield_thresholds", BS.get("thresholds", [0.3, 0.6]))
		break_chain = int(BS.get("break_chain", {}).get(typ, 2))

func distance_name(d := "") -> String:
	return str(cfg.get("distances", {}).get("names", {}).get(d if d != "" else distance, d))

func distance_multiplier(d := "") -> float:
	return float(cfg.get("distances", {}).get("points_multiplier", {}).get(d if d != "" else distance, 1.0))

## 短程 / 中程 / 長程. Saved as the last choice; re-derives the current level's count and limits.
func set_distance(d: String, persist := true) -> void:
	var order: Array = cfg.get("distances", {}).get("order", ["short", "mid", "long"])
	if not order.has(d):
		d = order[0]
	distance = d
	if persist:
		save.set_setting("distance", d)
		save.save_file()
	if levels.size() > 0 and lvl.size() > 0:
		set_level(level_index)
	if btn_distance != null:
		btn_distance.text = "距離：%s（點擊切換）" % distance_name()

func cycle_distance() -> void:
	var order: Array = cfg.get("distances", {}).get("order", ["short", "mid", "long"])
	set_distance(order[(order.find(distance) + 1) % order.size()])
	if state == State.SELECT:
		show_select()

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
	e.background_mode = Environment.BG_CANVAS     # sky + skyline are 2D layers behind the 3D world
	e.background_canvas_max_layer = -1
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	env.environment = e
	add_child(env)
	bg_layer = CanvasLayer.new()
	bg_layer.layer = -5
	add_child(bg_layer)
	sky_rect = TextureRect.new()
	sky_rect.texture = Art.SKY
	sky_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_px(sky_rect, 0, 0, 1, 1, 0, 0, 0, 0)
	bg_layer.add_child(sky_rect)
	far_rect = TextureRect.new()
	far_rect.texture = Art.FAR
	far_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	far_rect.stretch_mode = TextureRect.STRETCH_TILE
	far_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(far_rect)
	# ground: wide pale base + sidewalks + 3-lane track tile (UV scrolls with distance)
	var base := MeshInstance3D.new()
	var bp := PlaneMesh.new(); bp.size = Vector2(120, 400)
	base.mesh = bp
	var bmat := _mat(Color(0.86, 0.83, 0.78)); bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	base.material_override = bmat
	base.position.y = -0.02
	base.name = "Ground"
	add_child(base)
	for spec in [[0.0, lane_w * lane_count, Art.TRACK, TRACK_TILE_M], [-(lane_w * lane_count * 0.5 + 1.0), 2.0, Art.SIDEWALK, 8.0], [lane_w * lane_count * 0.5 + 1.0, 2.0, Art.SIDEWALK, 8.0]]:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(spec[1], 400)
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = spec[2]
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.uv1_scale = Vector3(1, 400.0 / float(spec[3]), 1)
		m.set_meta("tile", float(spec[3]))
		mi.material_override = m
		mi.position = Vector3(spec[0], 0.02, 0)
		base.add_child(mi)
		road_mats.append(m)
	player = Node3D.new()
	add_child(player)
	player_mesh = MeshInstance3D.new()      # kept for hit tweens; the visible body is the sprite
	player_mat = _mat(Color(1, 1, 1), true)
	player.add_child(player_mesh)
	runner = RunnerSprite.new()
	player_mesh.add_child(runner)
	var shadow := MeshInstance3D.new()
	var sq := QuadMesh.new(); sq.size = Vector2(1.3, 0.5); sq.orientation = PlaneMesh.FACE_Y
	shadow.mesh = sq
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.2, 0.15, 0.3, 0.35)
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new(); gr.set_color(0, Color(1, 1, 1, 1)); gr.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = gr
	sm.albedo_texture = gt
	shadow.material_override = sm
	shadow.position.y = 0.01
	player.add_child(shadow)
	cam = Camera3D.new()
	cam.fov = base_fov
	add_child(cam)
	prop_rng.seed = 12345
	# petals (zone 1 ambience) on a 2D layer between world and HUD
	fx_layer = CanvasLayer.new()
	fx_layer.layer = 0
	add_child(fx_layer)
	petals = CPUParticles2D.new()
	var at := AtlasTexture.new(); at.atlas = Art.VFX.petals; at.region = Rect2(0, 0, 64, 64)
	petals.texture = at
	petals.amount = 28
	petals.lifetime = 5.0
	petals.preprocess = 5.0
	petals.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	petals.direction = Vector2(0.3, 1)
	petals.spread = 30.0
	petals.gravity = Vector2(0, 40)
	petals.initial_velocity_min = 40.0
	petals.initial_velocity_max = 90.0
	petals.angular_velocity_min = -90.0
	petals.angular_velocity_max = 90.0
	petals.scale_amount_min = 0.5
	petals.scale_amount_max = 1.0
	fx_layer.add_child(petals)

## Roadside props (batch03 large + batch07 small): spawned at the far end on both sides and
## pushed toward the camera by the 3D perspective; recycled behind the camera.
const MID_PROPS := ["house_a", "house_b", "shop", "wall"]
const NEAR_PROPS := ["sakura_big", "sakura_small", "lamp", "bench", "planter", "shrub", "vending", "fence"]
const PROP_H := {"house_a": 7.5, "house_b": 7.5, "shop": 6.5, "wall": 2.2, "sakura_big": 6.0, "sakura_small": 4.6,
	"lamp": 4.2, "bench": 0.9, "planter": 0.9, "shrub": 1.4, "vending": 1.9, "fence": 1.2}
func _spawn_props() -> void:
	var far := player_dist + 140.0
	for key in next_prop:
		var mid: bool = key.begins_with("mid")
		var side := -1.0 if key.ends_with("_l") else 1.0
		while next_prop[key] < far:
			var pool: Array = MID_PROPS if mid else NEAR_PROPS
			var n: String = pool[prop_rng.randi_range(0, pool.size() - 1)]
			var sp: Sprite3D
			for q in props:
				if not q.visible:
					sp = q
					break
			if sp == null:
				sp = Sprite3D.new()
				sp.shaded = false
				sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
				sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				sp.centered = true
				add_child(sp)
				props.append(sp)
			sp.texture = Art.PROPS[n]
			var sz: Array = Art.PROP_SIZE[n]
			sp.pixel_size = float(PROP_H[n]) / float(sz[1])
			var half_w := float(sz[0]) * sp.pixel_size * 0.5
			var road := lane_w * lane_count * 0.5 + 2.0
			var x := road + 0.6 + half_w if mid else road - 0.3 + half_w * 0.5
			sp.offset = Vector2(0, float(sz[1]) * 0.5)   # bottom-centre anchor (0.5, 1.0)
			sp.position = Vector3(side * x, 0.0, -next_prop[key])
			sp.flip_h = side > 0.0 and n in ["sakura_big", "sakura_small", "lamp"]
			sp.visible = true
			next_prop[key] += (half_w * 2.0 + prop_rng.randf_range(1.5, 4.0)) if mid else prop_rng.randf_range(7.0, 12.0)
	for q in props:
		if q.visible and q.position.z > -player_dist + 9.0:
			q.visible = false

## All HUD controls are anchored to the viewport (no fixed 720-px design widths),
## so they stay correct when the window / web canvas is wider or narrower.
func _label(size: int, align := HORIZONTAL_ALIGNMENT_LEFT, font: Font = null) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font if font else Assets.FONT_HUD)
	l.add_theme_font_size_override("font_size", int(size * UI))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(l)
	return l

## Base canvas is 1080x1920 (art spec). Offsets/fonts written for the old 720-wide layout are scaled by UI.
const UI := 1.5
static func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, o_r: float, ob: float) -> void:
	_place_px(c, al, at, ar, ab, ol * UI, ot * UI, o_r * UI, ob * UI)

## Offsets in real canvas pixels (no UI scaling).
static func _place_px(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, o_r: float, ob: float) -> void:
	c.anchor_left = al; c.anchor_top = at; c.anchor_right = ar; c.anchor_bottom = ab
	c.offset_left = ol; c.offset_top = ot; c.offset_right = o_r; c.offset_bottom = ob

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", Assets.FONT_HUD)
	b.add_theme_font_size_override("font_size", int(36 * UI))
	b.custom_minimum_size = Vector2(180, 72) * UI
	b.focus_mode = Control.FOCUS_NONE
	return b

## StyleBoxTexture from art/ui (no baked text). margin = 9-slice margin in source px.
func _tex_style(name: String, margin := 0, content_l := -1.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = Art.UI[name]
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(maxf(8.0, margin * 0.5))
	if content_l >= 0.0:
		sb.content_margin_left = content_l
	return sb

## Text-less art button: normal / pressed / disabled textures; label stays a Godot label.
func _art_button(b: Button, prefix: String, margin := 0, content_l := -1.0, size := Vector2.ZERO) -> void:
	var n := _tex_style(prefix + "_normal" if Art.UI.has(prefix + "_normal") else prefix, margin, content_l)
	var pr := _tex_style(prefix + "_pressed" if Art.UI.has(prefix + "_pressed") else prefix, margin, content_l)
	var d := _tex_style(prefix + "_disabled" if Art.UI.has(prefix + "_disabled") else (prefix + "_normal" if Art.UI.has(prefix + "_normal") else prefix), margin, content_l)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("disabled", d)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, INK)
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.45))
	if size != Vector2.ZERO:
		b.custom_minimum_size = size

func _ink(l: Control) -> void:
	l.add_theme_color_override("font_color", INK)
	l.add_theme_constant_override("outline_size", 0)

func _panel_center(style := "panel_9slice") -> Array:
	var cc := CenterContainer.new()
	_place(cc, 0, 0, 1, 1, 0, 0, 0, 0)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(cc)
	var pc := PanelContainer.new()
	if style == "":
		pc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		var sb := _tex_style(style, 44)
		sb.set_content_margin_all(48)
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
	timer_panel = NinePatchRect.new()
	timer_panel.texture = Art.UI.timer_panel
	timer_panel.patch_margin_left = 24; timer_panel.patch_margin_right = 24; timer_panel.patch_margin_top = 24; timer_panel.patch_margin_bottom = 24
	timer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(timer_panel)
	_place(timer_panel, 0, 0, 0, 0, 14, 8, 274, 68)
	var ti := TextureRect.new()
	ti.texture = Art.UI.icon_timer
	ti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	timer_panel.add_child(ti); _place(ti, 0, 0.5, 0, 0.5, 10, -17, 44, 17)
	lbl_time = _label(34);  _place(lbl_time, 0, 0, 0.5, 0, 64, 10, 0, 62)
	_ink(lbl_time)
	lbl_count = _label(40); _place(lbl_count, 0, 0, 0.5, 0, 24, 70, 0, 124)
	hearts_box = Control.new()
	hearts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hearts_box)
	_place(hearts_box, 0, 0, 0, 0, 14, 136, 314, 202)     # hp_frame 500x110 aspect
	var frame := NinePatchRect.new()
	frame.texture = Art.UI.hp_frame
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hearts_box.add_child(frame); _place_px(frame, 0, 0, 1, 1, 0, 0, 0, 0)
	var heart := TextureRect.new()
	heart.texture = Art.UI.icon_heart
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hearts_box.add_child(heart); _place_px(heart, 0.05, 0.2, 0.17, 0.72, 0, 0, 0, 0)
	hp_chunk = NinePatchRect.new(); hp_chunk.texture = Art.UI.hp_lag
	hp_fill = NinePatchRect.new(); hp_fill.texture = Art.UI.hp_fill
	for cr in [hp_chunk, hp_fill]:
		cr.patch_margin_left = 20; cr.patch_margin_right = 20
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hearts_box.add_child(cr)
		_place_px(cr, 0, 0.236, 0, 0.673, 0, 0, 0, 0)
	lbl_hp = Label.new()
	lbl_hp.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_hp.add_theme_font_size_override("font_size", int(24 * UI))
	lbl_hp.add_theme_color_override("font_outline_color", INK)
	lbl_hp.add_theme_constant_override("outline_size", 8)
	lbl_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hearts_box.add_child(lbl_hp); _place_px(lbl_hp, 0.2, 0.1, 0.95, 0.8, 0, 0, 0, 0)
	lbl_shield = Label.new()
	lbl_shield.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_shield.add_theme_font_size_override("font_size", int(22 * UI))
	lbl_shield.add_theme_color_override("font_color", Color(0.35, 0.6, 0.95))
	lbl_shield.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hearts_box.add_child(lbl_shield); _place_px(lbl_shield, 1, 0, 1, 1, 6, 0, 90, 0)
	lbl_boss = _label(32, HORIZONTAL_ALIGNMENT_CENTER); _place(lbl_boss, 0, 0, 1, 0, 0, 250, 0, 300)
	lbl_boss.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	shield_box = NinePatchRect.new()
	(shield_box as NinePatchRect).texture = Art.UI.shield_counter_panel
	shield_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(shield_box)
	_place(shield_box, 0.5, 0, 0.5, 0, -100, 300, 100, 347)
	shield_pips = HBoxContainer.new()
	shield_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	shield_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_box.add_child(shield_pips); _place_px(shield_pips, 0, 0, 1, 1, 0, 0, 0, 0)
	shield_box.visible = false
	judge = TextureRect.new()
	judge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	judge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud.add_child(judge)
	_place(judge, 0.5, 0.3, 0.5, 0.3, -80, -80, 80, 80)
	judge.modulate.a = 0.0
	go_box = TextureRect.new()
	(go_box as TextureRect).texture = Art.UI.countdown_bg_go
	(go_box as TextureRect).expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	go_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(go_box)
	_place(go_box, 0.5, 0.4, 0.5, 0.4, -130, -130, 130, 130)
	var gl := Label.new()
	gl.text = "GO!"
	gl.add_theme_font_override("font", Assets.FONT_HUD)
	gl.add_theme_font_size_override("font_size", 130)
	gl.add_theme_color_override("font_outline_color", INK)
	gl.add_theme_constant_override("outline_size", 8)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	go_box.add_child(gl); _place_px(gl, 0, 0, 1, 1, 0, 0, 0, 0)
	go_box.modulate.a = 0.0
	lbl_speed = _label(28, HORIZONTAL_ALIGNMENT_CENTER); _place(lbl_speed, 0.5, 1, 0.5, 1, -115, -90, 115, -36)
	combo_badge = NinePatchRect.new()
	combo_badge.texture = Art.UI.combo_badge
	combo_badge.patch_margin_left = 40; combo_badge.patch_margin_right = 40
	combo_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(combo_badge)
	lbl_combo = _label(40, HORIZONTAL_ALIGNMENT_CENTER); _place(lbl_combo, 0.5, 1, 0.5, 1, -115, -170, 115, -100)
	_ink(lbl_combo)
	speedo = Control.new()
	speedo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(speedo)
	var spn := TextureRect.new(); spn.texture = Art.UI.speedo_panel
	spn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speedo.add_child(spn); _place_px(spn, 0, 0, 1, 1, 0, 0, 0, 0)
	speedo_needle = TextureRect.new(); speedo_needle.texture = Art.UI.speedo_needle
	speedo_needle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	speedo_needle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speedo.add_child(speedo_needle)
	lbl_speed.reparent(speedo)
	_ink(lbl_speed)
	lbl_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	btn_brake = _touch_button("煞車", 40, "btn_brake"); _place(btn_brake, 0, 1, 0, 1, 24, -244, 224, -44)
	btn_accel = _touch_button("加速", 48, "btn_accel"); _place(btn_accel, 1, 1, 1, 1, -264, -284, -24, -44)
	btn_pause = _touch_button("", 40, "btn_pause"); _place(btn_pause, 1, 0, 1, 0, -120, 16, -24, 112)
	btn_voice = _touch_button("重播", 30, "btn_secondary", 32); _place(btn_voice, 1, 0, 1, 0, -120, 124, -24, 220)
	btn_lock = _touch_button("鎖定", 34, "btn_lock"); _place(btn_lock, 1, 1, 1, 1, -200, -430, -64, -294)
	# brake / accel labels sit in the lower 30 % (icon above); lock labels on the right half (x 80-150 of 160)
	for bt in [btn_brake, btn_accel]:
		_place_px(bt.get_child(0), 0, 0.6, 1, 0.94, 0, 0, 0, 0)
	_place_px(btn_lock.get_child(0), 0.48, 0.52, 0.96, 0.9, 0, 0, 0, 0)
	lbl_lock_kmh = Label.new()
	lbl_lock_kmh.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_lock_kmh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_lock_kmh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_lock_kmh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink(lbl_lock_kmh)
	btn_lock.add_child(lbl_lock_kmh); _place_px(lbl_lock_kmh, 0.48, 0.1, 0.96, 0.55, 0, 0, 0, 0)
	for bt in [btn_lock, btn_voice]:
		_ink(bt.get_child(0))
	_layout_touch()
	# full-screen backgrounds for level select / results (batch04), shown in _update_hud
	sel_bg = TextureRect.new(); sel_bg.texture = Art.UI.select_bg
	res_bg = TextureRect.new(); res_bg.texture = Art.UI.result_bg
	for bg in [sel_bg, res_bg]:
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.visible = false
		hud.add_child(bg); _place_px(bg, 0, 0, 1, 1, 0, 0, 0, 0)
	# pause menu
	var pm := _panel_center()
	pause_box = pm[0]
	var pt := Label.new()
	pt.text = "暫停"
	pt.add_theme_font_override("font", Assets.FONT_HUD)
	pt.add_theme_font_size_override("font_size", int(52 * UI))
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(pt)
	pm[1].add_child(pt)
	btn_resume = _button("繼續"); btn_restart = _button("重來"); btn_quit = _button("回選關")
	btn_mode_pause = _button("")
	_art_button(btn_mode_pause, "seg_mode_left_on", 0, -1, Vector2(680, 130))
	# the segmented art carries two labels; the button text (kept for code/tests) is not drawn
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		btn_mode_pause.add_theme_color_override(c, Color(0, 0, 0, 0))
	for i in 2:
		var sl := Label.new()
		sl.text = ["賽車（按住）", "點放 ±5"][i]
		sl.add_theme_font_override("font", Assets.FONT_HUD)
		sl.add_theme_font_size_override("font_size", 34)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ink(sl)
		btn_mode_pause.add_child(sl); _place_px(sl, i * 0.5, 0, i * 0.5 + 0.5, 0.92, 0, 0, 0, 0)
	_art_button(btn_resume, "btn_continue", 0, 150, Vector2(680, 210))
	_art_button(btn_restart, "btn_restart", 0, 150, Vector2(680, 150))
	_art_button(btn_quit, "btn_stage_select", 0, 150, Vector2(680, 150))
	for b in [btn_mode_pause, btn_quit, btn_restart, btn_resume]:   # continue at the bottom (thumb zone)
		b.add_theme_font_size_override("font_size", 52)
		pm[1].add_child(b)
	btn_resume.pressed.connect(resume)
	btn_restart.pressed.connect(func(): reset_run())
	btn_quit.pressed.connect(show_select)
	btn_mode_pause.pressed.connect(func(): set_speed_mode("step" if speed_mode == "race" else "race"))
	pause_box.visible = false
	# settings
	var st := _panel_center()
	settings_box = st[0]
	var stl := Label.new()
	stl.text = "設定：速度模式"
	stl.add_theme_font_override("font", Assets.FONT_HUD)
	stl.add_theme_font_size_override("font_size", int(44 * UI))
	stl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(stl)
	st[1].add_child(stl)
	btn_mode_race = _button("賽車模式：按住加速／煞車，可鎖定速度")
	btn_mode_step = _button("點放模式：點一下 ±5 km/h")
	btn_settings_back = _button("返回")
	for b in [btn_mode_race, btn_mode_step, btn_settings_back]:
		b.custom_minimum_size = Vector2(560, 80) * UI
		b.add_theme_font_size_override("font_size", int(30 * UI))
		b.toggle_mode = b != btn_settings_back
		_art_button(b, "btn_primary" if b != btn_settings_back else "btn_secondary", 32)
		st[1].add_child(b)
	btn_mode_race.pressed.connect(func(): set_speed_mode("race"))
	btn_mode_step.pressed.connect(func(): set_speed_mode("step"))
	btn_settings_back.pressed.connect(func(): settings_box.visible = false; select_box.visible = true)
	settings_box.visible = false
	# results
	var r := _panel_center()
	results_box = r[0]
	lbl_result = Label.new()
	lbl_result.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_result.add_theme_font_size_override("font_size", int(28 * UI))
	lbl_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ink(lbl_result)
	res_stars = HBoxContainer.new()
	res_stars.alignment = BoxContainer.ALIGNMENT_CENTER
	res_stars.add_theme_constant_override("separation", 6)
	r[1].add_child(res_stars)
	for i in 3:
		var stx := TextureRect.new()
		stx.texture = Art.UI.star_empty_200
		stx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stx.custom_minimum_size = Vector2(150, 150)
		res_stars.add_child(stx)
	res_badge = TextureRect.new()
	res_badge.texture = Art.UI.badge_new_record
	res_badge.custom_minimum_size = Vector2(180, 70)
	res_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var nl := Label.new(); nl.text = "新紀錄"
	nl.add_theme_font_override("font", Assets.FONT_HUD); nl.add_theme_font_size_override("font_size", 34)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ink(nl)
	res_badge.add_child(nl); _place_px(nl, 0, 0, 1, 0.95, 0, 0, 0, 0)
	r[1].add_child(res_badge)
	r[1].add_child(lbl_result)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	r[1].add_child(hb)
	btn_retry = _button("重玩"); btn_next = _button("下一關"); btn_select = _button("回選關")
	_art_button(btn_retry, "btn_retry", 0, -1, Vector2(400, 200))
	_art_button(btn_next, "btn_next", 0, -1, Vector2(400, 200))
	_art_button(btn_select, "btn_small", 0, -1, Vector2(320, 80))
	btn_retry.add_theme_font_size_override("font_size", 52)
	btn_next.add_theme_font_size_override("font_size", 52)
	btn_select.add_theme_font_size_override("font_size", 38)
	btn_select.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for b in [btn_retry, btn_next]:
		hb.add_child(b)
	r[1].add_child(btn_select)
	btn_retry.pressed.connect(func(): reset_run())
	btn_next.pressed.connect(go_next_level)
	btn_select.pressed.connect(show_select)
	results_box.visible = false
	# level select
	var sp := _panel_center("")
	select_box = sp[0]
	select_list = sp[1]
	select_box.visible = false

func _touch_button(text: String, size: int, art: String, margin := 0) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_meta("art", art)
	p.set_meta("margin", margin)
	p.add_theme_stylebox_override("panel", _tex_style(art + ("_off" if art == "btn_lock" else "_normal"), margin))
	hud.add_child(p)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Assets.FONT_HUD)
	l.add_theme_font_size_override("font_size", int(size * UI))
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(l, 0, 0, 1, 1, 0, 0, 0, 0)
	p.add_child(l)
	return p

## Pressed art while held (lock: on / off). No modulate glow.
func _set_btn_lit(p: Panel, lit: bool) -> void:
	var art: String = p.get_meta("art")
	var key := (art + ("_on" if lit else "_off")) if art == "btn_lock" else (art + ("_pressed" if lit else "_normal"))
	if p.get_meta("key", "") != key:
		p.set_meta("key", key)
		p.add_theme_stylebox_override("panel", _tex_style(key, int(p.get_meta("margin"))))
	p.scale = Vector2.ONE

# ---------------------------------------------------------------- HP
## Upgrade hook: extra max HP (value). refill = also fill to the new max.
func set_max_hp_bonus(bonus: int, refill := true) -> void:
	max_hp_bonus = maxi(0, bonus)
	set_max_hp(base_max_hp + max_hp_bonus, refill)

func set_max_hp(n: int, refill := false) -> void:
	max_hp = maxi(1, n)
	hp = max_hp if refill else mini(hp, max_hp)
	hp_delayed = minf(hp_delayed, float(max_hp)) if not refill else float(hp)
	_emit_hp()

## Upgrade hook: percent of every hit that is ignored (clamped 0..90).
func set_damage_reduction(pct: float) -> void:
	damage_reduction = clampf(pct, 0.0, 90.0)

## Charm hook: each shield point blocks one whole future hit.
func add_shield(n := 1) -> void:
	shield = maxi(0, shield + n)
	_emit_hp()

## Heal hook (value), capped at max_hp.
func heal(n := 10) -> void:
	hp = mini(max_hp, hp + maxi(0, n))
	hp_delayed = maxf(hp_delayed, float(hp))
	_emit_hp()

## Damage after reduction (rounded, at least 1 if raw > 0).
func damage_after_reduction(n: int) -> int:
	if n <= 0:
		return 0
	return maxi(1, int(round(n * (1.0 - damage_reduction / 100.0))))

## Applies damage. Returns true if HP was actually lost. Ends the run at 0.
func take_damage(n := 35) -> bool:
	if n <= 0:
		return false
	if shield > 0:
		shield -= 1
		damaged.emit(0, true)
		_emit_hp()
		_hearts_fx(Color(0.6, 0.85, 1.0))
		return false
	var d := damage_after_reduction(n)
	hp = maxi(0, hp - d)
	hp_delay_wait = bar_wait_s
	damaged.emit(d, false)
	_emit_hp()
	_hearts_fx(Color(1.0, 0.25, 0.25))
	if hp <= 0 and state == State.RUNNING:
		_finish(false, "hp_out")
	return true

func _emit_hp() -> void:
	_refresh_hp_bar()
	hp_changed.emit(hp, max_hp, shield)

func _refresh_hp_bar() -> void:
	if hearts_box == null:
		return
	var W := hearts_box.size.x if hearts_box.size.x > 0.0 else 450.0
	var x0 := W * 101.0 / 500.0; var tw := W * 374.0 / 500.0      # inner track of hp_frame
	hp_fill.offset_left = x0; hp_chunk.offset_left = x0
	hp_fill.offset_right = x0 + maxf(1.0, tw * float(hp) / float(max_hp))
	hp_chunk.offset_right = x0 + maxf(1.0, tw * clampf(hp_delayed, 0.0, float(max_hp)) / float(max_hp))
	hp_fill.visible = hp > 0
	lbl_hp.text = "%d / %d" % [hp, max_hp]
	var ratio := float(hp) / float(max_hp)
	hp_fill.self_modulate = Color.WHITE if ratio > 0.5 else (Color(1.6, 1.25, 0.5) if ratio > 0.25 else Color(1.7, 0.6, 0.55))
	lbl_shield.text = ("盾%d" % shield) if shield > 0 else ""

## Flash + shake of the HP widget only (never the camera / screen).
func _hearts_fx(col: Color) -> void:
	if hearts_box == null:
		return
	hearts_box.modulate = col * 1.6
	var tw := create_tween()
	tw.tween_property(hearts_box, "modulate", Color.WHITE, 0.4)
	var sh := create_tween()
	for d in [10.0, -8.0, 6.0, -4.0, 0.0]:
		sh.tween_property(hearts_box, "position:x", 24.0 * UI + d, 0.04)

# ---------------------------------------------------------------- pause
func pause_game() -> void:
	if state != State.RUNNING:
		return
	state = State.PAUSED
	pause_count += 1
	_release_inputs()
	lbl_hint.visible = false
	voice.stream_paused = true
	music.stream_paused = true
	pause_box.visible = true

func resume() -> void:
	if state != State.PAUSED:
		return
	_release_inputs()
	pause_box.visible = false
	lbl_hint.visible = true
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

## Speed mode switch. Works mid-run (see SpeedController.set_mode) and is saved.
func set_speed_mode(m: String, persist := true) -> void:
	if m != "race" and m != "step":
		m = "race"
	speed_mode = m
	ctrl.set_mode(m)
	touches.clear()
	if persist:
		save.set_setting("speed_mode", m)
		save.save_file()
	_refresh_mode_buttons()

func mode_name(m := "") -> String:
	return "點放" if (m if m != "" else speed_mode) == "step" else "賽車"

func _refresh_mode_buttons() -> void:
	if btn_mode_pause == null:
		return
	btn_mode_pause.text = "模式：%s ⇄ %s" % [mode_name(), mode_name("race" if speed_mode == "step" else "step")]
	btn_mode_race.button_pressed = speed_mode == "race"
	btn_mode_step.button_pressed = speed_mode == "step"
	if btn_settings != null and is_instance_valid(btn_settings):
		btn_settings.text = "設定（%s模式）" % mode_name()

func show_settings() -> void:
	select_box.visible = false
	settings_box.visible = true
	_refresh_mode_buttons()

## Touch buttons scale with the short side of the (stretched) canvas so they stay
## comfortably large in portrait and landscape.
func _layout_touch() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var m := minf(vs.x, vs.y)
	var a := m * 0.28      # accel  (art 320x250 incl. shadow)
	var b := m * 0.24      # brake
	var t := m * 0.13      # pause / voice
	var g := m * 0.035     # margin
	var ah := a * 250.0 / 320.0
	var bh := b * 250.0 / 320.0
	_place_px(btn_accel, 1, 1, 1, 1, -g - a, -g - ah, -g, -g)
	_place_px(btn_brake, 0, 1, 0, 1, g, -g - bh, g + b, -g)
	# centre column between brake and accel: speedometer at the bottom, 鎖定 above it, combo above that
	var sw := m * 0.30; var sh := sw * 130.0 / 240.0
	_place_px(speedo, 0.5, 1, 0.5, 1, -sw * 0.5, -g - sh, sw * 0.5, -g)
	speedo_needle.size = Vector2(12, 44) * (sh / 130.0)
	speedo_needle.position = Vector2(sw * 60.0 / 240.0, sh * 58.0 / 130.0) - Vector2(speedo_needle.size.x * 0.5, speedo_needle.size.y * 0.9)
	speedo_needle.pivot_offset = Vector2(speedo_needle.size.x * 0.5, speedo_needle.size.y * 0.9)
	speedo_needle.rotation = deg_to_rad(-135.0 + 270.0 * clampf(ctrl.kmh() / 100.0, 0.0, 1.0))   # dial tops out at 100 km/h
	_place_px(lbl_speed, 0, 0, 1, 1, sw * 0.065, 0, -sw * 0.065, -sh * 0.08)   # symmetric (centred rect), text right of the dial
	lbl_speed.add_theme_font_size_override("font_size", maxi(12, int(sh * 0.17)))
	lbl_speed.clip_text = true
	var lw := m * 0.16; var lh := lw * 130.0 / 160.0
	_place_px(btn_lock, 0.5, 1, 0.5, 1, -lw * 0.5, -g - sh - g * 0.5 - lh, lw * 0.5, -g - sh - g * 0.5)
	var ch := m * 0.075; var cw := ch * 260.0 / 90.0
	var ctop := -g - sh - g * 0.5 - lh - g * 0.5 - ch
	_place_px(lbl_combo, 0.5, 1, 0.5, 1, -cw * 0.5, ctop, cw * 0.5, ctop + ch)
	_place_px(combo_badge, 0.5, 1, 0.5, 1, -cw * 0.5, ctop, cw * 0.5, ctop + ch)
	lbl_combo.add_theme_font_size_override("font_size", maxi(12, int(ch * 0.5)))
	combo_badge.visible = lbl_combo.text != "" and lbl_combo.visible
	_place_px(btn_pause, 1, 0, 1, 0, -g - t, g, -g, g + t * 158.0 / 148.0)
	_place_px(btn_voice, 1, 0, 1, 0, -g - t, g + t + g * 0.6, -g, g + t + g * 0.6 + t)
	for p in [btn_accel, btn_brake, btn_lock, btn_pause, btn_voice]:
		var lab: Label = p.get_child(0)
		lab.add_theme_font_size_override("font_size", int(p.size.y * (0.2 if p == btn_lock else (0.22 if p == btn_voice else 0.17))) if p.size.y > 0 else 32)
	lbl_lock_kmh.add_theme_font_size_override("font_size", maxi(10, int(lh * 0.26)))

func show_select() -> void:
	settings_box.visible = false
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
		select_list.remove_child(c)
		c.queue_free()
	level_buttons.clear()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var w := minf(560.0 * UI, vs.x - 90.0 * UI)
	var title := Label.new()
	title.text = "選關"
	title.add_theme_font_override("font", Assets.FONT_HUD)
	title.add_theme_font_size_override("font_size", int(44 * UI))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(title)
	select_list.add_child(title)
	lbl_points = Label.new()
	lbl_points.text = "總點數 %d" % save.points()
	lbl_points.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_points.add_theme_font_size_override("font_size", int(28 * UI))
	lbl_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(lbl_points)
	select_list.add_child(lbl_points)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	select_list.add_child(tabs)
	btn_tab_hira = _button("平假名"); btn_tab_kata = _button("片假名")
	var kata_open := false
	for i in levels.size():
		if levels[i].get("script") == "kata" and save.is_unlocked(levels, i):
			kata_open = true
	for b in [btn_tab_hira, btn_tab_kata]:
		b.toggle_mode = true
		_art_button(b, "tab_inactive", 32)
		b.add_theme_stylebox_override("pressed", _tex_style("tab_active", 32))
		b.add_theme_stylebox_override("hover_pressed", _tex_style("tab_active", 32))
		if b == btn_tab_kata and not kata_open:      # katakana opens after 1-BOSS
			b.add_theme_stylebox_override("normal", _tex_style("tab_locked", 32))
			b.add_theme_stylebox_override("hover", _tex_style("tab_locked", 32))
		b.custom_minimum_size = Vector2(w * 0.5 - 5, w * 0.5 * 110.0 / 470.0)
		b.add_theme_font_size_override("font_size", int(30 * UI))
		tabs.add_child(b)
	btn_tab_hira.button_pressed = select_tab == "hira"
	btn_tab_kata.button_pressed = select_tab == "kata"
	btn_tab_hira.pressed.connect(func(): select_tab = "hira"; show_select())
	btn_tab_kata.pressed.connect(func(): select_tab = "kata"; show_select())
	# distance: three art buttons; tapping the selected one cycles (btn_distance = the selected one)
	var drow := HBoxContainer.new()
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	drow.add_theme_constant_override("separation", 10)
	select_list.add_child(drow)
	for d in cfg.get("distances", {}).get("order", ["short", "mid", "long"]):
		var db := _button(distance_name(d))
		_art_button(db, "dist_selected" if d == distance else "dist_unselected", 32)
		db.custom_minimum_size = Vector2(w / 3.0 - 8, (w / 3.0) * 130.0 / 300.0)
		db.add_theme_font_size_override("font_size", int(28 * UI))
		if d == distance:
			btn_distance = db
			db.pressed.connect(cycle_distance)
		else:
			db.pressed.connect(func(): set_distance(d); show_select())
		drow.add_child(db)
	select_scroll = ScrollContainer.new()
	select_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	select_scroll.custom_minimum_size = Vector2(w, maxf(150.0, vs.y - 560.0 * UI))
	select_list.add_child(select_scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_scroll.add_child(list)
	var zone := -1
	var first_scroll_target: Control = null
	for i in levels.size():
		var L: Dictionary = levels[i]
		if str(L.get("script", "hira")) != select_tab:
			continue
		if int(L.get("zone", 0)) != zone:
			zone = int(L.get("zone", 0))
			var zl := Label.new()
			zl.text = ("第 %d 區" % zone) if zone > 0 else "最終關"
			zl.add_theme_font_override("font", Assets.FONT_HUD)
			zl.add_theme_font_size_override("font_size", int(26 * UI))
			_ink(zl)
			zl.add_theme_stylebox_override("normal", _tex_style("zone_header_%d" % clampi(zone, 1, 5) if zone > 0 else "zone_header_final", 32, 110))
			zl.custom_minimum_size = Vector2(w - 20, (w - 20) * 130.0 / 960.0)
			zl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			list.add_child(zl)
		var id := str(L.get("id"))
		var E := LevelDB.effective(cfg, levels, i, distance)
		var unlocked := save.is_unlocked(levels, i) and not bool(E.voice_locked)
		var rec: Dictionary = save.get_record(id, distance)
		var txt := "%s  %d題" % [str(L.get("name", id)), int(E.target_correct)]
		if bool(E.voice_locked):
			txt += "  缺語音"
		elif not unlocked:
			txt += "  鎖定"
		elif float(rec.get("best_time", -1.0)) >= 0.0:
			txt += "  %s %.1fs" % [_stars_text(int(rec.get("best_stars", 0))), float(rec.best_time)]
		elif bool(rec.get("cleared", false)):
			txt += "  通過"
		var b := _button(txt)
		var typ := str(L.get("type", "normal"))
		var row_art := "stage_row_locked" if not unlocked else ("stage_row_boss" if typ != "normal" else ("stage_row_cleared" if save.cleared_any(id) else "stage_row_normal"))
		var rh := (w - 20) * 180.0 / 960.0
		_art_button(b, row_art, 40, rh * 0.85)
		b.add_theme_stylebox_override("pressed", _tex_style("stage_row_selected", 40, rh * 0.85))
		b.add_theme_stylebox_override("disabled", _tex_style("stage_row_locked", 40, rh * 0.85))
		b.custom_minimum_size = Vector2(w - 20, rh)
		b.add_theme_font_size_override("font_size", int(24 * UI))
		# kana badge (left 126x126 of the row) - Zen Maru label, not baked into the art
		var badge := Label.new()
		var rws: Array = L.get("rows", [])
		badge.text = "" if not unlocked else (str(rws[0]).substr(0, 1) if rws.size() > 0 and typ == "normal" else "")
		badge.add_theme_font_override("font", Art.FONT_KANA)
		badge.add_theme_font_size_override("font_size", int(rh * 0.42))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ink(badge)
		b.add_child(badge); _place_px(badge, 0, 0, 0, 1, rh * 0.06, 0, rh * 0.78, -rh * 0.06)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not unlocked
		b.pressed.connect(choose_level.bind(i))
		b.set_meta("level_index", i)
		list.add_child(b)
		level_buttons.append(b)
		if unlocked:
			first_scroll_target = b
	btn_settings = _button("")
	_art_button(btn_settings, "btn_secondary", 32)
	btn_settings.custom_minimum_size = Vector2(w, 90)
	btn_settings.add_theme_font_size_override("font_size", int(28 * UI))
	btn_settings.pressed.connect(show_settings)
	select_list.add_child(btn_settings)
	_refresh_mode_buttons()
	select_box.visible = true
	if first_scroll_target != null:
		select_scroll.ensure_control_visible.call_deferred(first_scroll_target)

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
	hp_delayed = float(hp); hp_delay_wait = 0.0
	shield_phase = 0; boss_shield_up = false; break_progress = 0; shields_broken = 0
	last_points = 0; last_record = {}; review_asked = 0
	lbl_boss.text = ""
	_emit_hp()
	lbl_hint.text = ""; lbl_notice.text = ""
	_spawn_rows()
	state = State.READY
	results_box.visible = false
	select_box.visible = false
	settings_box.visible = false
	pause_box.visible = false
	lbl_hint.visible = true
	voice.stream_paused = false
	music.stream_paused = false
	touches.clear()
	lbl_center.text = "%s\n%s・%d 題\n%s\n\n按住「加速」加速、按住「煞車」煞車\n都不按 = 自然減速\n左右滑動換線（按著加速時也可以）\n\nPC: W/Space 加速, S 煞車, A/D 換線\nE 重播  Esc/P 暫停  F3 dev\n\nTap / Space to start" % [str(lvl.get("name", "Level 1")), distance_name(), int(lvl.target_correct), "小知識：" + str(lvl.get("knowledge", ""))]
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
	_go_pop()
	_activate_next()

## Visual-only "GO!" pop (batch04 countdown art). The run starts immediately as before.
func _go_pop() -> void:
	go_box.modulate.a = 1.0
	go_box.pivot_offset = go_box.size * 0.5
	go_box.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(go_box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(go_box, "modulate:a", 0.0, 0.15).set_delay(0.2)

## ○ / × judge art pop (0.4 s scale + fade).
func _judge(ok: bool) -> void:
	judge.texture = Art.UI.judge_ok if ok else Art.UI.judge_ng
	judge.modulate.a = 1.0
	judge.pivot_offset = judge.size * 0.5
	judge.scale = Vector2(1.3, 1.3)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(judge, "scale", Vector2.ONE, 0.15)
	tw.tween_property(judge, "modulate:a", 0.0, 0.3).set_delay(0.15)

func clock() -> float:
	return elapsed + penalty

func _spawn_rows() -> void:
	var pool: Array = lvl.get("kana", ["あ"])
	while next_row_dist < player_dist + spawn_ahead:
		var r: Dictionary
		var review: Array = lvl.get("review_kana", [])
		var is_review := false
		if requeue.size() > 0:
			var t: String = requeue.pop_front()
			r = Rules.make_row_ex(pool if pool.has(t) else review, t, "", -1, rng, lane_count, lookalikes, same_sound)
			is_review = not pool.has(t)
		elif review.size() >= 2 and rng.randf() < review_ratio:
			r = Rules.make_row_ex(review, "", last_target, -1, rng, lane_count, lookalikes, same_sound, pool)
			is_review = true
		else:
			r = Rules.make_row_ex(pool, "", last_target, -1, rng, lane_count, lookalikes, same_sound)
		last_target = r.kana[r.target]
		var node := Node3D.new()
		node.position = Vector3(0, 0, -next_row_dist)
		add_child(node)
		var stones: Array = []
		for i in r.kana.size():
			var st := _make_stone(str(r.kana[i]))
			st.position = Vector3(lane_x(i), TABLET_H * 0.5, 0)
			node.add_child(st)
			stones.append(st)
		var row := {"dist": next_row_dist, "kana": r.kana, "target": r.target, "node": node,
			"stones": stones, "resolved": false, "voice_t": -1.0, "q": 0, "hint": false, "retry": false, "review": is_review}
		_apply_row_labels(row)
		rows.append(row)
		next_row_dist += row_spacing

## Tablet art (batch01 tablet_normal, no baked text) on a quad; kana is a Label3D in Zen Maru Gothic.
## Size: ~240x270 px on a 1080x1920 canvas at the resolve distance, kana glyph >= 150 px with 8 px outline.
const TABLET_H := 1.52
func _make_stone(k: String) -> MeshInstance3D:
	var st := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(TABLET_H * 256.0 / 288.0, TABLET_H)
	st.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = Art.TABLET
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	st.material_override = m
	var lab := Label3D.new()
	lab.name = "Kana"
	lab.font = Art.FONT_KANA
	lab.font_size = 160
	lab.pixel_size = 0.0068
	lab.outline_size = 8
	lab.modulate = Color.WHITE
	lab.outline_modulate = Color(0.16, 0.11, 0.25)
	lab.position = Vector3(0, -0.02, 0.02)
	lab.text = k
	st.add_child(lab)
	var ov := MeshInstance3D.new()
	ov.name = "ShieldOv"
	var oq := QuadMesh.new(); oq.size = Vector2(TABLET_H * 340.0 / 288.0, TABLET_H * 360.0 / 288.0)
	ov.mesh = oq
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.albedo_texture = Art.TABLET_SHIELD
	om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ov.material_override = om
	ov.position.z = 0.04
	ov.visible = false
	st.add_child(ov)
	var fx := Sprite3D.new()
	fx.name = "ShieldFx"
	fx.shaded = false
	fx.texture = Art.SHIELD.loop
	fx.hframes = 8
	fx.pixel_size = TABLET_H * 1.5 / 256.0
	fx.position.z = 0.06
	fx.visible = false
	st.add_child(fx)
	return st

## Boss shield VFX: appear (8f) -> loop (8f) on the stones of rows ahead; hit (6f) / break (10f) one-shots. 24 fps.
var _shield_fx_t := 0.0
var _shield_fx_anim := ""
var _shield_was_up := false
func _shield_fx(anim: String) -> void:
	_shield_fx_anim = anim
	_shield_fx_t = 0.0

func _tick_shield_fx(dt: float) -> void:
	if not _shield_was_up and boss_shield_up:
		_shield_fx("appear")
	elif _shield_was_up and not boss_shield_up and state == State.RUNNING:
		_shield_fx("break")
	_shield_was_up = boss_shield_up
	_shield_fx_t += dt
	var frames := {"appear": 8, "loop": 8, "hit": 6, "break": 10}
	var f := int(_shield_fx_t * 24.0)
	if _shield_fx_anim != "" and _shield_fx_anim != "loop" and f >= int(frames[_shield_fx_anim]):
		_shield_fx_anim = "loop" if boss_shield_up else ""
		_shield_fx_t = 0.0; f = 0
	for r in rows:
		for st in r.stones:
			if not is_instance_valid(st): continue
			var fx: Sprite3D = st.get_node("ShieldFx")
			var on: bool = (boss_shield_up or _shield_fx_anim == "break") and not r.resolved and _shield_fx_anim != ""
			st.get_node("ShieldOv").visible = boss_shield_up and not r.resolved
			fx.visible = on
			if on:
				fx.texture = Art.SHIELD[_shield_fx_anim]
				fx.hframes = int(frames[_shield_fx_anim])
				fx.frame = (f % fx.hframes) if _shield_fx_anim == "loop" else mini(f, fx.hframes - 1)

func _apply_row_labels(row: Dictionary) -> void:
	for i in row.stones.size():
		var lab := row.stones[i].get_node("Kana") as Label3D
		lab.text = row.kana[i] if i < row.kana.size() else ""
		lab.font_size = 160 if lab.text.length() < 2 else 100

## Wrong hit: the next row becomes the same question with the correct kana in a different lane.
func _retry_in_next_row(after_row: Dictionary, kana: String, avoid_lane: int) -> void:
	var idx := rows.find(after_row)
	for j in range(idx + 1, rows.size()):
		var nxt: Dictionary = rows[j]
		if nxt.resolved or nxt.voice_t >= 0.0:
			continue
		var P: Array = lvl.get("kana", ["あ"])
		var r := Rules.make_row_ex(P if P.has(kana) else lvl.get("review_kana", P), kana, "", avoid_lane, rng, lane_count, lookalikes, same_sound)
		nxt.kana = r.kana
		nxt.target = r.target
		nxt.retry = true
		for st in nxt.stones:
			st.visible = false
		for ii in r.kana.size():
			if ii < nxt.stones.size():
				nxt.stones[ii].visible = true
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
	if r.get("review", false):
		review_asked += 1
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

var _romaji_cache := {}
func _romaji(k: String) -> String:
	if _romaji_cache.is_empty():
		_romaji_cache = LevelDB.romaji_map(cfg)
	return str(_romaji_cache.get(k, ""))

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
	var romaji := _romaji(r.kana[r.target])
	voice.stream = Assets.VOICE.get(romaji)
	if voice.stream:
		voice.play()

## Delayed red HP chunk: waits bar_wait_s after a hit, then drains to the real HP.
func _tick_hp_bar(dt: float) -> void:
	if hp_delay_wait > 0.0:
		hp_delay_wait -= dt
	elif hp_delayed > float(hp):
		hp_delayed = maxf(float(hp), hp_delayed - bar_drain * dt)

func _process(dt: float) -> void:
	_tick_hp_bar(dt)
	if state == State.RUNNING:
		_tick(dt)
	elif state == State.CLEARED or state == State.FAILED:
		result_time += dt
	_update_view(dt)
	_update_hud()

func _tick(dt: float) -> void:
	if autopilot:
		if speed_mode == "step":
			if ctrl.target < ctrl.max_speed: ctrl.tap_up()
		else:
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
		break_progress = 0
		take_damage(miss_damage)
	elif hit == r.target:
		result = "correct"
		if boss_shield_up:
			result = "shield"
			break_progress += 1
			runner.play_once("hit_shield", 8)   # last ~8 frames are already running -> back to run early
			_shield_fx("hit")
			if break_progress >= break_chain:
				boss_shield_up = false
				shields_broken += 1
				_notice("護盾擊破！")
		else:
			correct += 1
			_check_boss_shield()
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
		break_progress = 0
		take_damage(wrong_damage)
	logger.add(r.q, k, result, reaction, ctrl.kmh(), clock())
	if state == State.RUNNING:
		_activate_next()

## Boss/ultimate: at each threshold of the required count, raise a shield that needs N correct in a row.
func _check_boss_shield() -> void:
	if shield_phase >= shield_thresholds.size():
		return
	var need := int(ceil(float(shield_thresholds[shield_phase]) * float(lvl.target_correct)))
	if correct >= need and correct < int(lvl.target_correct):
		shield_phase += 1
		boss_shield_up = true
		break_progress = 0
		_notice("護盾展開！")

func _finish(cleared: bool, reason := "") -> void:
	fail_reason = "" if cleared else (reason if reason != "" else "time_up")
	state = State.CLEARED if cleared else State.FAILED
	result_time = 0.0
	ctrl.reset()
	music.stop()
	var stars := Rules.stars_for(clock(), lvl) if cleared else 0
	var new_best := false
	last_points = 0
	if cleared:
		last_record = save.record(level_id, distance, stars, clock())
		new_best = bool(last_record.better)
		last_points = Rules.points_for(bool(last_record.first_clear), int(last_record.new_stars), distance_multiplier(), cfg.get("points", {}))
		save.add_points(last_points)
		save.save_file()
		res_badge.visible = new_best
		lbl_result.text = "CLEAR!  %s\n%s  %s\n\nTime %.2f s\n(run %.2f + penalty %.1f)\nwrong %d  miss %d  combo %d\n體力 %d / %d   %s模式\n獲得點數 +%d（總點數 %d）%s\n\n小知識：%s" % [
			_stars_text(stars), str(lvl.get("name", "")), distance_name(), clock(), elapsed, penalty, wrong, missed, best_combo,
			hp, max_hp, mode_name(), last_points, save.points(), "\n新紀錄！" if new_best else "", str(lvl.get("knowledge", ""))]
		sfx("shatter", 0.8, 2.0)
	else:
		lbl_result.text = "%s\n%s  %s\n%d / %d   %s模式\n獲得點數 +0（總點數 %d）\n\n小知識：%s" % ["體力耗盡" if fail_reason == "hp_out" else "時間到",
			str(lvl.get("name", "")), distance_name(), correct, int(lvl.get("target_correct", 20)), mode_name(), save.points(), str(lvl.get("knowledge", ""))]
		sfx("back")
	if not cleared:
		res_badge.visible = false
	for i in 3:
		res_stars.get_child(i).texture = Art.UI.star_full_200 if i < stars else Art.UI.star_empty_200
	lbl_center.text = ""
	lbl_hint.text = ""
	btn_next.visible = level_index + 1 < levels.size()
	btn_next.disabled = not can_go_next()
	pause_box.visible = false
	lbl_hint.visible = true
	touches.clear()
	results_box.visible = true
	if dev_mode:
		last_saved_path = logger.save("clear" if cleared else fail_reason, elapsed, clock(), stars, hp, speed_mode, distance, last_points, int(lvl.target_correct))
		print("[dev] timing saved: ", last_saved_path)
	lbl_boss.text = ""
	print("[result] %s %s %s%s clock=%.3f elapsed=%.3f penalty=%.1f correct=%d wrong=%d miss=%d stars=%d" % [
		level_id, distance, "CLEAR" if cleared else "FAIL", "" if cleared else "(" + fail_reason + ")", clock(), elapsed, penalty, correct, wrong, missed, stars])

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
	var tw := create_tween().set_parallel(true)
	tw.tween_property(m, "emission_energy_multiplier", 0.0, dur)
	tw.tween_property(m, "albedo_color", Color.WHITE, dur)

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
	_shatter(st)
	_sparks(st.global_position)
	sfx("shatter", rng.randf_range(0.95, 1.1), 3.0)
	# player punch (scale pop) + tiny FOV punch, no camera shake
	runner.play_once("hit_correct")
	var pt := create_tween()
	pt.tween_property(player_mesh, "scale", Vector3(1.06, 0.96, 1.0), 0.05)
	pt.tween_property(player_mesh, "scale", Vector3.ONE, 0.15)
	_glow_player(Color(1.0, 0.85, 0.3), 3.0)
	var fov_punch := float(fb.get("fov_punch_deg", 4.0))
	cam.fov = base_fov + fov_punch
	_judge(true)

## tablet_shatter (8 frames, 24 fps) at the stone; the label flies away with the knockback tween.
func _shatter(st: MeshInstance3D) -> void:
	var sp := Sprite3D.new()
	sp.texture = Art.TABLET_SHATTER
	sp.hframes = 8
	sp.shaded = false
	sp.pixel_size = TABLET_H * 1.33 / 192.0
	sp.position = st.global_position
	add_child(sp)
	st.transparency = 1.0   # the tablet body becomes the shatter frames
	var tw := create_tween()
	tw.tween_property(sp, "frame", 7, 8.0 / 24.0)
	tw.tween_callback(sp.queue_free)

## Sparks (batch02 sparks_atlas) burst on the 2D fx layer at the stone's screen position.
func _sparks(at: Vector3) -> void:
	if cam == null or not cam.is_inside_tree():
		return
	var p := CPUParticles2D.new()
	var t := AtlasTexture.new(); t.atlas = Art.VFX.sparks; t.region = Rect2(0, 0, 64, 64)
	p.texture = t
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 18
	p.lifetime = 0.45
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 400.0
	p.initial_velocity_max = 900.0
	p.damping_min = 600.0; p.damping_max = 600.0
	p.angular_velocity_min = -360.0; p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.5; p.scale_amount_max = 1.0
	p.position = cam.unproject_position(at)
	fx_layer.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

func _fx_wrong(st: MeshInstance3D, right: MeshInstance3D) -> void:
	runner.play_once("hit_wrong")
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
	_float_text("-%ss" % str(lvl.get("wrong_penalty_s", 2.0)), Color(1.0, 0.35, 0.35))
	_judge(false)

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
	cam.position = Vector3(player_x * 0.4, 3.6, -player_dist + 7.0)
	cam.look_at(Vector3(player_x * 0.4, 1.2, -player_dist - 14.0))
	cam.fov = move_toward(cam.fov, base_fov + ctrl.kmh() * 0.08, 40.0 * dt)
	cam.h_offset = move_toward(cam.h_offset, 0.0, dt)
	var g := get_node("Ground") as Node3D
	g.position.z = -player_dist - 150.0
	for m in road_mats:
		m.uv1_offset.y = -fmod(player_dist, float(m.get_meta("tile")) * 100.0) / float(m.get_meta("tile"))
	_spawn_props()
	if runner != null:
		runner.position.x = 0.0
		var lean := clampf((lane_x(lane) - player_x) / lane_w, -1.0, 1.0)
		runner.rotation.z = 0.0 if runner.anim.begins_with("lane") else -lean * 0.05
		runner.tick(dt)
		if state == State.RUNNING:
			if ctrl.is_braking() and ctrl.speed > 0.2:
				if runner.anim != "brake" and not runner.is_one_shot():
					runner.play_once("brake", 0, true)
			else:
				runner.release_hold()
			runner.set_loop("idle" if ctrl.kmh() < 1.0 else ("accel" if ctrl.is_accelerating() and ctrl.speed < ctrl.max_speed - 0.01 else "run"))
		elif state != State.PAUSED:
			if runner.is_one_shot() and runner.anim == "brake":
				runner.release_hold()
			runner.set_loop("idle")
	# horizon line of the 3D camera -> place the 2D skyline on it
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var pitch := atan2(cam.position.y - 1.2, 21.0)
	var hy := vs.y * (0.5 - 0.5 * tan(pitch) / tan(deg_to_rad(cam.fov) * 0.5))
	var fh := vs.x * 420.0 / 2160.0 * 1.6
	var k := fh / 420.0
	far_rect.scale = Vector2(k, k)
	far_rect.size = Vector2(vs.x * 2.0 / k, 420.0)
	far_rect.position = Vector2(-fmod(player_x * 6.0 + 1000.0, 2160.0 * k) - vs.x * 0.2, hy - fh + 6.0)
	petals.emission_rect_extents = Vector2(vs.x * 0.6, 10)
	petals.position = Vector2(vs.x * 0.5, -20)
	_tick_shield_fx(dt)

func _update_hud() -> void:
	# keep pop-scale pivots centred even if the window was resized mid-animation
	lbl_notice.pivot_offset = lbl_notice.size * 0.5
	lbl_combo.pivot_offset = lbl_combo.size * 0.5
	var in_game := state != State.SELECT
	lbl_time.visible = in_game; lbl_count.visible = in_game; lbl_speed.visible = in_game; hearts_box.visible = in_game
	_refresh_hp_bar()
	var vw: float = get_viewport().get_visible_rect().size.x
	lbl_result.custom_minimum_size.x = minf(620.0 * UI, vw - 110.0 * UI)   # wrap long knowledge text inside the panel
	if state == State.RUNNING and boss_shield_up:
		lbl_boss.text = "護盾 連續答對 %d / %d" % [break_progress, break_chain]
	elif state == State.RUNNING and shield_thresholds.size() > 0:
		lbl_boss.text = "BOSS 護盾 %d / %d 已擊破" % [shields_broken, shield_thresholds.size()]
	else:
		lbl_boss.text = ""
	lbl_boss.visible = state == State.RUNNING
	sel_bg.visible = select_box.visible or settings_box.visible
	go_box.visible = state == State.RUNNING and clock() < 0.6
	res_bg.visible = results_box.visible and not sel_bg.visible
	shield_box.visible = state == State.RUNNING and boss_shield_up
	if shield_box.visible and shield_pips.get_child_count() != break_chain:
		for c in shield_pips.get_children(): c.free()
		for i in break_chain:
			var pip := TextureRect.new()
			pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pip.custom_minimum_size = Vector2(52, 52)
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			shield_pips.add_child(pip)
	for i in shield_pips.get_child_count():
		shield_pips.get_child(i).texture = Art.UI.shield_pip_full if i < break_progress else Art.UI.shield_pip_empty
	var playing := state == State.RUNNING or state == State.READY
	for b in [btn_accel, btn_brake, btn_pause, btn_voice]:
		b.visible = playing
	btn_lock.visible = playing and speed_mode == "race"
	speedo.visible = playing or state == State.PAUSED
	lbl_lock_kmh.text = ("%d" % roundi(ctrl.lock_kmh())) if ctrl.locked else ""
	timer_panel.visible = lbl_time.visible
	_layout_touch()
	_set_btn_lit(btn_lock, ctrl.locked)
	_set_btn_lit(btn_accel, ctrl.is_accelerating())
	_set_btn_lit(btn_brake, ctrl.is_braking())
	var limit := float(lvl.get("time_limit_s", 60.0))
	lbl_time.text = "%.1f / %d" % [clock(), int(limit)]
	lbl_count.text = "%d / %d" % [correct, int(lvl.get("target_correct", 20))]
	var mode := "BRAKE" if ctrl.is_braking() else ("ACCEL" if ctrl.is_accelerating() else "")
	if speed_mode == "step":
		lbl_speed.text = "%d → %d km/h" % [roundi(ctrl.kmh()), roundi(ctrl.target_kmh())]
	elif ctrl.locked:
		lbl_speed.text = "%d km/h  鎖定 %d" % [roundi(ctrl.kmh()), roundi(ctrl.lock_kmh())]
	else:
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
		if runner != null and not runner.is_one_shot():
			runner.play_once("lane_left" if dir < 0 else "lane_right")
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
			if state == State.RUNNING and _hit(btn_lock, ev.position):
				ctrl.toggle_lock(); return
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
		KEY_F:
			if ev.pressed and state == State.RUNNING: ctrl.toggle_lock()
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
