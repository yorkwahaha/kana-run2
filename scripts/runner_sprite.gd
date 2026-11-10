extends MeshInstance3D
## Straight-rear poses on a screen-parallel quad with a shared sole anchor.
const Art = preload("res://scripts/art_manifest.gd")
const SHADER = preload("res://shaders/runner.gdshader")

## metres per (scaled) sheet pixel
var px := 0.00545
var anim := "idle"
var frame := 0
var _t := 0.0
var _once := false
var _return_frame := 0
var _hold_last := false
var flash := 0.0
var _flash_decay := 0.0
var _mat: ShaderMaterial
var _quad: QuadMesh
var history: Array = []   # last played actions (tests)

func _init() -> void:
	_quad = QuadMesh.new()
	mesh = _quad
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("tex", Art.NIGHT_RUNNER)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply("idle", 0)

func def(n := "") -> Dictionary:
	return Art.RUNNER[n if n != "" else anim]

func set_aura(col: Color, strength: float, rim_col := Color.WHITE, rim_str := 0.0) -> void:
	if _mat != null:
		_mat.set_shader_parameter("aura_color", col)
		_mat.set_shader_parameter("aura_strength", strength)
		_mat.set_shader_parameter("rim_color", rim_col)
		_mat.set_shader_parameter("rim_strength", rim_str)

func set_opacity(op: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("opacity", op)

func _apply(n: String, f: int) -> void:
	var d: Dictionary = Art.RUNNER[n]
	anim = n
	frame = clampi(f, 0, int(d.frames) - 1)
	_quad.size = Art.RUNNER_CELL * px
	var origin: Vector2 = (Art.RUNNER_CELL * 0.5 - Art.RUNNER_SOLE) * px
	_quad.center_offset = Vector3(origin.x, -origin.y, 0.0)
	var tile := int(d.start) + frame
	var grid: Vector2i = Art.RUNNER_GRID
	@warning_ignore("integer_division")
	var row := tile / grid.x
	_mat.set_shader_parameter("region", Vector4(
		float(tile % grid.x) / grid.x, float(row) / grid.y, 1.0 / grid.x, 1.0 / grid.y))

## Foot (anchor) position of the current frame in local space: always the origin.
func anchor_local() -> Vector3:
	return Vector3.ZERO

## Looping base action (idle / run / accel). Does not interrupt a one-shot.
func set_loop(n: String) -> void:
	if _once or n == anim:
		return
	var keep := frame if (n in ["run", "accel"] and anim in ["run", "accel"]) else 0
	_t = 0.0
	_apply(n, keep % int(Art.RUNNER[n].frames))

## One-shot action, then back to the run loop at its return frame.
func play_once(n: String, hold_last := false) -> void:
	_once = true
	_hold_last = hold_last
	_return_frame = int(Art.RUNNER[n].get("return_frame", 0))
	_t = 0.0
	history.append(n)
	if history.size() > 20: history.pop_front()
	_apply(n, 0)
	match n:
		"hit_wrong": flash = 0.16; _flash_decay = 0.16 / 0.3      # white flash 0.7 -> 0 in 0.3 s
		"hit_shield": flash = 0.10; _flash_decay = 0.10 / 0.25
	_mat.set_shader_parameter("flash", flash)

func release_hold(next_anim := "run") -> void:
	if _once and _hold_last:
		_finish_once(next_anim)

func is_one_shot() -> bool:
	return _once

func reset_pose() -> void:
	flash = 0.0
	_mat.set_shader_parameter("flash", 0.0)
	_finish_once("idle")

func _finish_once(next_anim := "run") -> void:
	_once = false
	_hold_last = false
	_t = 0.0
	_apply(next_anim, posmod(_return_frame, int(Art.RUNNER.run.frames)) if next_anim == "run" else 0)

func tick(dt: float, speed_kmh := -1.0) -> void:
	var d: Dictionary = Art.RUNNER[anim]
	_t += dt
	var fps := float(d.fps)
	if (anim == "run" or anim == "accel") and speed_kmh >= 0.0:
		# Footstep matching: slow stride at low speed, powerful sprint at high speed
		var scale_factor := clampf(lerpf(0.50, 1.35, (speed_kmh - 5.0) / 55.0), 0.45, 1.45)
		fps *= scale_factor
	var step := 1.0 / fps
	while _t >= step:
		_t -= step
		var last := int(d.frames) - 1
		if frame >= last:
			if _once:
				if _hold_last:
					_t = 0.0
					break
				_finish_once()
				d = Art.RUNNER[anim]
				step = 1.0 / float(d.fps)
				continue
			_apply(anim, 0)
		else:
			_apply(anim, frame + 1)
	if flash > 0.0:
		flash = maxf(0.0, flash - _flash_decay * dt)
		_mat.set_shader_parameter("flash", flash)
