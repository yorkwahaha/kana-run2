extends RefCounted
## Developer timing mode: per-question reaction times + clear time.
## Writes user://timing/run_<stamp>.json and .csv, and appends a summary line
## to user://timing/runs_v5.csv.

var entries: Array = []
var level_id := ""

const RUNS_FILE := "user://timing/runs_v5.csv"

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
		if e.result == result or (result == "success" and (e.result == "correct" or e.result == "shield")):
			s += e.reaction_s; n += 1
	return s / n if n > 0 else 0.0

## outcome: "clear", "time_up" or "hp_out"
func save(outcome: String, elapsed_s: float, clock_s: float, stars: int, hp_left := -1, mode := "", distance := "", points := 0, target := 0) -> String:
	DirAccess.make_dir_recursive_absolute("user://timing")
	var stamp_base := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var stamp := stamp_base
	var base := "user://timing/run_%s" % stamp
	var sequence := 0
	while FileAccess.file_exists(base + ".json") or FileAccess.file_exists(base + ".csv"):
		sequence += 1
		stamp = "%s_%d" % [stamp_base, sequence]
		base = "user://timing/run_%s" % stamp
	var counts := {"correct": 0, "wrong": 0, "miss": 0, "shield": 0}
	for e in entries:
		counts[e.result] = counts.get(e.result, 0) + 1
	var avg_correct := avg_reaction()
	var avg_success := avg_reaction("success")
	var summary := {"level": level_id, "outcome": outcome, "elapsed_s": snappedf(elapsed_s, 0.001),
		"clock_s": snappedf(clock_s, 0.001), "stars": stars, "hp_left": hp_left, "mode": mode, "distance": distance, "target_correct": target, "points": points, "counts": counts,
		"avg_reaction_correct_s": snappedf(avg_correct, 0.001), "avg_reaction_success_s": snappedf(avg_success, 0.001), "questions": entries}
	var f := FileAccess.open(base + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(summary, "  "))
		f.close()
	f = FileAccess.open(base + ".csv", FileAccess.WRITE)
	if f:
		f.store_line("q,target,result,reaction_s,speed_kmh,clock_s,mode,distance")
		for e in entries:
			f.store_line("%d,%s,%s,%.3f,%.1f,%.3f,%s,%s" % [e.q, e.target, e.result, e.reaction_s, e.speed_kmh, e.clock_s, mode, distance])
		f.close()
	var new_file := not FileAccess.file_exists(RUNS_FILE)
	f = FileAccess.open(RUNS_FILE, FileAccess.READ_WRITE if not new_file else FileAccess.WRITE)
	if f:
		if new_file:
			f.store_line("stamp,level,outcome,elapsed_s,clock_s,stars,correct,wrong,miss,avg_reaction_s,hp_left,mode,distance,target,points,shield_hits,avg_reaction_success_s")
		f.seek_end()
		f.store_line("%s,%s,%s,%.3f,%.3f,%d,%d,%d,%d,%.3f,%d,%s,%s,%d,%d,%d,%.3f" % [stamp, level_id, outcome, elapsed_s, clock_s, stars,
			counts.correct, counts.wrong, counts.miss, avg_correct, hp_left, mode, distance, target, points, counts.shield, avg_success])
		f.close()
	return ProjectSettings.globalize_path(base + ".json")
