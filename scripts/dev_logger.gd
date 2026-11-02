extends RefCounted
## Developer timing mode: per-question reaction times + clear time.
## Writes user://timing/run_<stamp>.json and .csv, and appends a summary line
## to user://timing/runs.csv.

var entries: Array = []
var level_id := ""

func start(lvl_id: String) -> void:
	level_id = lvl_id
	entries.clear()

func add(q: int, target: String, result: String, reaction_s: float, kmh: float, clock_s: float) -> void:
	entries.append({"q": q, "target": target, "result": result,
		"reaction_s": snappedf(reaction_s, 0.001), "speed_kmh": snappedf(kmh, 0.1),
		"clock_s": snappedf(clock_s, 0.001)})

func avg_reaction(result := "correct") -> float:
	var s := 0.0; var n := 0
	for e in entries:
		if e.result == result:
			s += e.reaction_s; n += 1
	return s / n if n > 0 else 0.0

## outcome: "clear", "time_up" or "hp_out"
func save(outcome: String, elapsed_s: float, clock_s: float, stars: int, hp_left := -1) -> String:
	DirAccess.make_dir_recursive_absolute("user://timing")
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var base := "user://timing/run_%s" % stamp
	var counts := {"correct": 0, "wrong": 0, "miss": 0}
	for e in entries:
		counts[e.result] = counts.get(e.result, 0) + 1
	var summary := {"level": level_id, "outcome": outcome, "elapsed_s": snappedf(elapsed_s, 0.001),
		"clock_s": snappedf(clock_s, 0.001), "stars": stars, "hp_left": hp_left, "counts": counts,
		"avg_reaction_correct_s": snappedf(avg_reaction(), 0.001), "questions": entries}
	var f := FileAccess.open(base + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(summary, "  "))
		f.close()
	f = FileAccess.open(base + ".csv", FileAccess.WRITE)
	if f:
		f.store_line("q,target,result,reaction_s,speed_kmh,clock_s")
		for e in entries:
			f.store_line("%d,%s,%s,%.3f,%.1f,%.3f" % [e.q, e.target, e.result, e.reaction_s, e.speed_kmh, e.clock_s])
		f.close()
	var runs := "user://timing/runs_v2.csv"   # v2 adds hp_left
	var new_file := not FileAccess.file_exists(runs)
	f = FileAccess.open(runs, FileAccess.READ_WRITE if not new_file else FileAccess.WRITE)
	if f:
		if new_file:
			f.store_line("stamp,level,outcome,elapsed_s,clock_s,stars,correct,wrong,miss,avg_reaction_s,hp_left")
		f.seek_end()
		f.store_line("%s,%s,%s,%.3f,%.3f,%d,%d,%d,%d,%.3f,%d" % [stamp, level_id, outcome, elapsed_s, clock_s, stars,
			counts.correct, counts.wrong, counts.miss, avg_reaction(), hp_left])
		f.close()
	return ProjectSettings.globalize_path(base + ".json")
