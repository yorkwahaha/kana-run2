extends SceneTree
## Focused regressions for the Gemini report. Uses an isolated user:// profile.
const SaveData = preload("res://scripts/save_data.gd")
const SpeedController = preload("res://scripts/speed_controller.gd")
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", message])

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for method in ClassDB.class_get_method_list("FileAccess"):
		if method.name == "store_string":
			check(method["return"].type == TYPE_BOOL, "Godot 4.7.2 store_string returns bool, not void")
	var save = SaveData.new()
	save.path = "user://report-save.json"
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(save.path + suffix)
	save.add_points(12)
	check(save.save_file(), "initial save succeeds")
	save.add_points(8)
	check(save.save_file(), "second save succeeds")
	check(FileAccess.file_exists(save.path + ".bak"), "successful save retains previous generation")
	var file := FileAccess.open(save.path, FileAccess.WRITE)
	file.store_string("broken"); file.close()
	var recovered = SaveData.new(); recovered.path = save.path; recovered.load_file()
	check(recovered.points() == 12, "corrupt primary restores previous generation")
	var c = SpeedController.new()
	c.toggle_lock()
	check(not c.locked, "stopped runner cannot lock zero speed")
	c.speed = 5.0 / 3.6; c.toggle_lock()
	check(c.locked, "cruise enables at 5 km/h")
	c.speed = 0; c.toggle_lock()
	check(not c.locked, "cruise can still be disabled while stopped")
	var g = load("res://scenes/main.tscn").instantiate()
	g.save_path = "user://report-game.json"; g.rng_seed = 7
	g.skip_title = true
	g.instant_transitions = true
	root.add_child(g)
	await process_frame
	g.set_process(false)
	g.save.clear_all(); g.set_distance("short", false); g.set_level(0); g.reset_run(); g.start_run()
	check(g.active_row().stones.all(func(st): return st.get_node("FocusFrame").visible), "active question frames all choices equally")
	g.hearts_box.position.x = 61.0
	g._hearts_fx(Color.RED)
	await create_timer(0.08).timeout
	g._hearts_fx(Color.RED)
	await create_timer(0.5).timeout
	check(absf(g.hearts_box.position.x - 61.0) < 0.1, "overlapping HP shakes restore actual layout origin")
	g.runner.play_once("hit_wrong"); g.runner._finish_once()
	check(g.runner.frame == 2, "return animation wraps 10 into eight-frame running cycle")
	var row: Dictionary = g.active_row()
	var target: String = row.kana[row.target]
	for extra in g.rows.slice(1):
		extra.node.queue_free()
	g.rows.resize(1); g.requeue.clear()
	g._retry_in_next_row(row, target, row.target)
	check(g.requeue.has(target), "retry without a future row remains queued")
	g.lane = 1; g.touches[9] = {"role": "accel", "anchor": Vector2(100, 100)}
	var drag := InputEventScreenDrag.new(); drag.index = 9; drag.position = Vector2(150, 250)
	g._touch(drag)
	check(g.lane == 1, "mostly vertical thumb drag does not switch lane")
	drag.position = Vector2(200, 110); g._touch(drag)
	check(g.lane == 2, "deliberate horizontal drag still switches lane")
	g.save.path = "user://missing-report-directory/save.json"
	g.elapsed = 30; g._finish(true)
	check(g.lbl_result.text.contains("再快 2.00 秒可達 3 星"), "result gives an exact next-star time goal")
	check(g.lbl_result_heading.text.contains("未存檔"), "failed save is visible on results")
	g.show_select()
	check(g.lbl_points.text.contains("未存檔"), "returning to menu preserves unsaved warning")
	g.select_box.visible = false; g.results_box.visible = true
	var retry = g.get("btn_save_retry")
	check(retry != null and retry.visible, "failed save offers retry")
	var awarded: int = g.save.points()
	if retry != null:
		g.save.path = "user://report-game.json"; retry.pressed.emit(); retry.pressed.emit()
		var disk = SaveData.new(); disk.path = g.save.path; disk.load_file()
		check(disk.points() == awarded and disk.cleared_any("1-1"), "save retry persists progress without awarding twice")
		check(not retry.visible and not g.lbl_result_heading.text.contains("未存檔"), "successful retry removes unsaved warning")
	g.save.clear_all(); g.set_level(3); g.reset_run(); g.start_run(); g.elapsed = 50; g._finish(true)
	var kata = g.get("btn_kata_next")
	check(kata != null and kata.visible and g.btn_next.visible, "first Boss clear offers both unlocked routes")
	if kata != null:
		kata.pressed.emit()
		check(g.lvl.get("script") == "kata" and g.state == g.State.READY, "new Katakana route opens its first stage")
		g.set_level(3); g.reset_run(); g.start_run(); g.elapsed = 50; g._finish(true)
		check(not kata.visible and g.btn_next.text == "下一關", "later Boss clears use the ordinary next-stage action")
	g.review_items = {"あ": {"choices": ["あ", "い", "う"], "wrong": 1, "missed": 0, "confused_with": "い"}}
	g._finish(false); g._open_review()
	var wrong: Button = g.review_choices.filter(func(b): return b.text != "あ")[0]
	wrong.pressed.emit()
	check(not g.lbl_review_feedback.text.contains("あ") and g.voice.playing, "first review mistake replays sound without revealing answer")
	wrong.pressed.emit()
	check(g.lbl_review_feedback.text.contains("あ"), "second review mistake supplies corrective answer")
	var key := InputEventKey.new(); key.pressed = true
	for i in g.review_choices.size():
		if g.review_choices[i].text == "あ": key.keycode = KEY_1 + i
	g._unhandled_input(key)
	check(not g.btn_review_next.disabled, "review supports keyboard 1/2/3")
	root.remove_child(g); g.free()
	# Let the audio mixing thread drain its stopped playbacks before quitting.
	await create_timer(0.2).timeout
	print("REPORT REGRESSION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
