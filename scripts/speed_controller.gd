extends RefCounted
## Pure speed logic (no nodes) so it can be unit-tested headless.
## accel held = accelerate, brake held = brake (wins over accel),
## neither = natural coast-down. No double-tap logic.

var max_speed := 60.0 / 3.6   # m/s
var accel_time := 3.0
var brake_time := 1.2
var coast_time := 5.0

var speed := 0.0
var holding := false      # accelerate held (key or touch button)
var brake_held := false   # brake held (key or touch button)

func configure(c: Dictionary) -> void:
	max_speed = float(c.get("max_speed_kmh", 60.0)) / 3.6
	accel_time = maxf(0.05, float(c.get("accel_time_s", 3.0)))
	brake_time = maxf(0.05, float(c.get("brake_time_s", 1.2)))
	coast_time = maxf(0.05, float(c.get("coast_time_s", 5.0)))

## Back to rest (speed 0, nothing held). Call on (re)start.
func reset() -> void:
	speed = 0.0
	release_all()

## Let go of everything but keep current speed (pause / focus loss).
func release_all() -> void:
	holding = false
	brake_held = false

func press() -> void:
	holding = true

func release() -> void:
	holding = false

func brake_press() -> void:
	brake_held = true

func brake_release() -> void:
	brake_held = false

func is_braking() -> bool:
	return brake_held

func is_accelerating() -> bool:
	return holding and not brake_held

func step(dt: float) -> void:
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
