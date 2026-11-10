extends RefCounted

const FONT_KANA := preload("res://art/fonts/kana_main.ttf")

## All night-road poses use the same 176 x 340 cell and planted sole.
const NIGHT_ROAD := preload("res://art/stage/night_road.png")
const NIGHT_SLATE := preload("res://art/tablet/night_slate.png")
const NIGHT_RUNNER := preload("res://art/runner/night_runner.png")
const RUNNER_CELL := Vector2(176.0, 340.0)
const RUNNER_GRID := Vector2i(4, 3)
const RUNNER_SOLE := Vector2(88.0, 334.0)
const RUNNER := {
	"run": {"start": 0, "frames": 4, "fps": 9},
	"accel": {"start": 0, "frames": 4, "fps": 12},
	"idle": {"start": 4, "frames": 1, "fps": 1},
	"lane_left": {"start": 5, "frames": 1, "fps": 5},
	"lane_right": {"start": 6, "frames": 1, "fps": 5},
	"hit_correct": {"start": 7, "frames": 1, "fps": 4},
	"hit_wrong": {"start": 8, "frames": 1, "fps": 4},
	"brake": {"start": 10, "frames": 1, "fps": 6},
	"hit_shield": {"start": 11, "frames": 1, "fps": 4},
}
