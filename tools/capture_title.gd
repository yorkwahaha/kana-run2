extends SceneTree

const OUT_DIR := "C:/Users/York/.gemini/antigravity-cli/brain/1e908bfc-f048-451c-80ed-4337cb1cb087"
const TARGET_SZ := Vector2i(1280, 720)

var g
var screens := ["title_keyboard", "title_joypad", "title_transition"]
var current_idx := 0
var wait_frames := 0
var shutdown_msec := 0

func _initialize() -> void:
	DisplayServer.window_set_size(TARGET_SZ)
	root.size = TARGET_SZ
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = "user://screenshot_save.json"
	g.skip_title = false
	g.instant_transitions = false
	root.add_child(g)

func _process(_d: float) -> bool:
	if current_idx >= screens.size():
		if g != null:
			root.remove_child(g)
			g.free()
			g = null
			shutdown_msec = Time.get_ticks_msec()
		if Time.get_ticks_msec() - shutdown_msec >= 200:
			quit(0)
		return false

	var scr: String = screens[current_idx]
	if wait_frames == 0:
		match scr:
			"title_keyboard":
				g.show_title()
				g._set_input_device("keyboard")
			"title_joypad":
				g.show_title()
				g._set_input_device("joypad")
			"title_transition":
				g.show_title()
				g._set_input_device("joypad")
				if g.fade_rect != null:
					g.fade_rect.modulate.a = 0.68
					g.fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	wait_frames += 1
	if wait_frames >= 12:
		var img := root.get_texture().get_image()
		if img != null:
			var out_p := "%s/1280x720_%s.png" % [OUT_DIR, scr]
			img.save_png(out_p)
			print("Saved screenshot: ", out_p)
		current_idx += 1
		wait_frames = 0
		if g != null and g.fade_rect != null:
			g.fade_rect.modulate.a = 0.0
			g.fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return false
