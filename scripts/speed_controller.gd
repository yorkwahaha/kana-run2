extends RefCounted
## Pure speed logic (no nodes) so it can be unit-tested headless.
## hold = accelerate, release = coast down, double-tap (press again within
## double_tap_window after a release) = brake while that press is held.

var max_speed := 60.0 / 3.6   # m/s
var accel_time := 3.0
var brake_time := 1.2
var coast_time := 5.0
var double_tap_window := 0.28

var speed := 0.0
var holding := false
var tap_brake := false        # brake from double-tap
var key_brake := false        # brake from keyboard (S / Down)
var _since_release := 999.0

func configure(c: Dictionary) -> void:
	max_speed = float(c.get("max_speed_kmh", 60.0)) / 3.6
	accel_time = maxf(0.05, float(c.get("accel_time_s", 3.0)))
	brake_time = maxf(0.05, float(c.get("brake_time_s", 1.2)))
	coast_time = maxf(0.05, float(c.get("coast_time_s", 5.0)))
	double_tap_window = float(c.get("double_tap_window_s", 0.28))

var _released_after_press := false   # only a real press->release can be a double-tap's first tap

## Back to rest: no pending double-tap. Call on (re)start.
func reset() -> void:
	speed = 0.0
	holding = false
	tap_brake = false
	key_brake = false
	_since_release = 999.0
	_released_after_press = false

func press() -> void:
	tap_brake = _released_after_press and _since_release <= double_tap_window
	holding = true
	_released_after_press = false

func release() -> void:
	if holding:
		_released_after_press = true
		_since_release = 0.0
	holding = false
	tap_brake = false

func is_braking() -> bool:
	return tap_brake or key_brake

func is_accelerating() -> bool:
	return holding and not is_braking()

func step(dt: float) -> void:
	_since_release += dt
	if is_braking():
		speed = maxf(0.0, speed - max_speed / brake_time * dt)
	elif holding:
		speed = minf(max_speed, speed + max_speed / accel_time * dt)
	else:
		speed = maxf(0.0, speed - max_speed / coast_time * dt)

func scale_speed(f: float) -> void:
	speed *= f

func kmh() -> float:
	return speed * 3.6
