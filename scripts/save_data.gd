extends RefCounted
## Simple progress save: user://save.json
## { "version": 1, "levels": { "level_01": {"cleared": true, "best_stars": 3, "best_time": 31.3} } }
## Written to a .tmp file first, then renamed (no half-written saves).

var path := "user://save.json"
var data := {"version": 1, "levels": {}}

func load_file() -> void:
	data = {"version": 1, "levels": {}}
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.get("levels") is Dictionary:
		data = parsed

func save_file() -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	return dir.rename(tmp.get_file(), path.get_file()) == OK

func get_record(id: String) -> Dictionary:
	return data.levels.get(id, {"cleared": false, "best_stars": 0, "best_time": -1.0})

## Records a clear. Returns true if stars or time improved (or first clear).
func record(id: String, stars: int, time_s: float) -> bool:
	var r: Dictionary = get_record(id).duplicate()
	var better := false
	if not r.get("cleared", false):
		better = true
	r["cleared"] = true
	if stars > int(r.get("best_stars", 0)):
		r["best_stars"] = stars
		better = true
	var bt := float(r.get("best_time", -1.0))
	if bt < 0.0 or time_s < bt:
		r["best_time"] = snappedf(time_s, 0.01)
		better = true
	data.levels[id] = r
	return better

## Level 0 is always open; level i opens when level i-1 has been cleared.
func is_unlocked(levels: Array, i: int) -> bool:
	if i <= 0:
		return true
	if i >= levels.size():
		return false
	return bool(get_record(str(levels[i - 1].get("id"))).get("cleared", false))

func clear_all() -> void:
	data = {"version": 1, "levels": {}}
