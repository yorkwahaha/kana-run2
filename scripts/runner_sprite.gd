extends MeshInstance3D
## Runner made of the batch07 sprite sheets (9 actions). Each sheet has its own frame size
## (360x540 or 440x560 source px); the quad is offset by -ground_anchor so the shoe-sole
## line stays on the node origin when actions switch (no foot jump).
## Lane change sheets only lean the body; sideways motion is done by game.gd.

const Art = preload("res://scripts/art_manifest.gd")
const SHADER = preload("res://shaders/runner.gdshader")

## metres per (scaled) sheet pixel
var px := 0.0063
var anim := "idle"
var frame := 0
var _t := 0.0
var _breath_t := 0.0
var _once := false
var _return_frame := 0
var _cut_tail := 0      # frames skipped at the end of a one-shot (hit_shield ends in running already)
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
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply("idle", 0)

func def(n := "") -> Dictionary:
	return Art.RUNNER[n if n != "" else anim]

func _apply(n: String, f: int) -> void:
	var d: Dictionary = Art.RUNNER[n]
	anim = n
	frame = clampi(f, 0, int(d.frames) - 1)
	var fw := float(d.fw); var fh := float(d.fh)
	_quad.size = Vector2(fw, fh) * px
	# offset = -ground_anchor: quad centre relative to the anchor point
	_quad.center_offset = Vector3((fw * 0.5 - float(d.ax)) * px, (float(d.ay) - fh * 0.5) * px, 0.0)
	_mat.set_shader_parameter("tex", Art.RUNNER_TEX[n])
	var cols := int(d.cols); var rows := int(d.rows)
	_mat.set_shader_parameter("region", Vector4(float(frame % cols) / cols, float(frame / cols) / rows, 1.0 / cols, 1.0 / rows))

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
func play_once(n: String, cut_tail := 0, hold_last := false) -> void:
	_once = true
	_hold_last = hold_last
	_cut_tail = cut_tail
	_return_frame = int(Art.RUNNER[n].get("return_frame", 0))
	_t = 0.0
	history.append(n)
	if history.size() > 20: history.pop_front()
	_apply(n, 0)
	match n:
		"hit_wrong": flash = 0.7; _flash_decay = 0.7 / 0.3      # white flash 0.7 -> 0 in 0.3 s
		"hit_shield": flash = 0.25; _flash_decay = 0.25 / 0.25
	_mat.set_shader_parameter("flash", flash)

func release_hold() -> void:
	if _once and _hold_last:
		_finish_once()

func is_one_shot() -> bool:
	return _once

func _finish_once() -> void:
	_once = false
	_hold_last = false
	_t = 0.0
	_apply("run", _return_frame)

func tick(dt: float) -> void:
	var d: Dictionary = Art.RUNNER[anim]
	_t += dt
	var step := 1.0 / float(d.fps)
	while _t >= step:
		_t -= step
		var last := int(d.frames) - 1 - (_cut_tail if _once else 0)
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
	# idle breathing done in code: 0..3.5 px up/down, 2 s period (batch07 README)
	if anim == "idle":
		_breath_t += dt
		position.y = 3.5 * 0.75 * (0.5 - 0.5 * cos(TAU * _breath_t / 2.0)) * px   # 3.5 source px
	else:
		_breath_t = 0.0
		position.y = 0.0
