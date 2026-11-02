extends RefCounted
## Pure speed logic (no nodes) so it can be unit-tested headless.
## Two modes:
##  "race" (賽車): accel held = accelerate, brake held = brake (wins), neither =
##          natural coast-down. Cruise lock: toggle_lock() keeps the speed at the
##          time of locking; holding accel/brake overrides temporarily and on
##          release the speed returns to the locked speed along the accel/brake curves.
##  "step" (點放): each accel press = target +step, each brake press = target -step
##          (0..max). Speed chases the target along the accel/brake curves.
##          No natural coast-down.

var max_speed := 60.0 / 3.6   # m/s
var accel_time := 3.0
var brake_time := 1.2
var coast_time := 5.0

var speed := 0.0
var mode := "race"          # "race" | "step"
var locked := false         # race: cruise lock on
var lock_speed := 0.0       # m/s
var target := 0.0           # step: target speed, m/s
var step_size := 5.0 / 3.6  # m/s
var step_halves_target := true
var holding := false      # accelerate held (key or touch button)
var brake_held := false   # brake held (key or touch button)

func configure(c: Dictionary) -> void:
	max_speed = float(c.get("max_speed_kmh", 60.0)) / 3.6
	accel_time = maxf(0.05, float(c.get("accel_time_s", 3.0)))
	brake_time = maxf(0.05, float(c.get("brake_time_s", 1.2)))
	coast_time = maxf(0.05, float(c.get("coast_time_s", 5.0)))
	step_size = float(c.get("step_kmh", 5.0)) / 3.6
	step_halves_target = bool(c.get("step_wrong_halves_target", true))

## Switch mode (also mid-run). race->step: target = current speed rounded to a step.
## step->race: unlocked, keeps current speed (then coasts unless held/locked).
func set_mode(m: String) -> void:
	if m != "race" and m != "step":
		return
	if m == "step" and mode != "step":
		target = clampf(roundf(speed / step_size) * step_size, 0.0, max_speed)
	mode = m
	locked = false
	release_all()

func toggle_lock() -> void:
	if mode != "race":
		return
	locked = not locked
	lock_speed = speed

func tap_up() -> void:
	target = minf(max_speed, target + step_size)

func tap_down() -> void:
	target = maxf(0.0, target - step_size)

func target_kmh() -> float:
	return target * 3.6

func lock_kmh() -> float:
	return lock_speed * 3.6
## Back to rest (speed 0, nothing held). Call on (re)start.
func reset() -> void:
	speed = 0.0
	target = 0.0
	locked = false
	lock_speed = 0.0
	release_all()

## Let go of everything but keep current speed (pause / focus loss).
func release_all() -> void:
	holding = false
	brake_held = false

func press() -> void:
	holding = true
	if mode == "step":
		tap_up()

func release() -> void:
	holding = false

func brake_press() -> void:
	brake_held = true
	if mode == "step":
		tap_down()

func brake_release() -> void:
	brake_held = false

func is_braking() -> bool:
	if mode == "step":
		return speed > target + 0.001
	return brake_held

func is_accelerating() -> bool:
	if mode == "step":
		return speed < target - 0.001
	return holding and not brake_held

func _chase(goal: float, dt: float) -> void:
	if speed < goal:
		speed = minf(goal, speed + max_speed / accel_time * dt)
	elif speed > goal:
		speed = maxf(goal, speed - max_speed / brake_time * dt)

func step(dt: float) -> void:
	if mode == "step":
		_chase(target, dt)
		return
	if brake_held:
		speed = maxf(0.0, speed - max_speed / brake_time * dt)
	elif holding:
		speed = minf(max_speed, speed + max_speed / accel_time * dt)
	elif locked:
		_chase(lock_speed, dt)
	else:
		speed = maxf(0.0, speed - max_speed / coast_time * dt)

## Wrong hit: speed * f. In step mode the target is also scaled if configured.
## In race mode a cruise lock keeps its locked speed (speed returns to it via the accel curve).
func scale_speed(f: float) -> void:
	speed *= f
	if mode == "step" and step_halves_target:
		target = clampf(roundf(target * f / step_size) * step_size, 0.0, max_speed)

func kmh() -> float:
	return speed * 3.6
