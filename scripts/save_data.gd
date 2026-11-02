extends RefCounted
## Progress save: user://save.json  (version 2)
## { "version": 2, "points": 0,
##   "levels": { "1-1": { "short": {"cleared": true, "best_stars": 3, "best_time": 31.3}, "mid": {...} } },
##   "settings": { "speed_mode": "race", "distance": "short" } }
## v1 saves (level_01 / level_02) are migrated: only the "cleared" flag is kept
## (old L1 -> 1-1, old L2 -> 1-2 at 短程); stars/times are reset because the
## question counts changed. Written to a .tmp file first, then renamed.

const VERSION := 2
var path := "user://save.json"
var data := {"version": VERSION, "points": 0, "levels": {}, "settings": {}}
var migrated_from := 0

func load_file() -> void:
	data = {"version": VERSION, "points": 0, "levels": {}, "settings": {}}
	migrated_from = 0
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return
	if int(parsed.get("version", 1)) < 2:
		data = migrate_v1(parsed)
		migrated_from = 1
	elif parsed.get("levels") is Dictionary:
		data = parsed
		if not data.has("settings"): data["settings"] = {}
		if not data.has("points"): data["points"] = 0

static func migrate_v1(old: Dictionary) -> Dictionary:
	var d := {"version": VERSION, "points": 0, "levels": {}, "settings": old.get("settings", {}).duplicate()}
	var map := {"level_01": "1-1", "level_02": "1-2"}
	var L: Dictionary = old.get("levels", {})
	for k in map:
		if L.get(k, {}).get("cleared", false):
			d.levels[map[k]] = {"short": {"cleared": true, "best_stars": 0, "best_time": -1.0}}
	return d

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

func get_record(id: String, dist := "short") -> Dictionary:
	return data.levels.get(id, {}).get(dist, {"cleared": false, "best_stars": 0, "best_time": -1.0})

func cleared_any(id: String) -> bool:
	for dist in data.levels.get(id, {}):
		if data.levels[id][dist].get("cleared", false):
			return true
	return false

## Records a clear at a distance. Returns {better, first_clear, new_stars}.
func record(id: String, dist: String, stars: int, time_s: float) -> Dictionary:
	var r: Dictionary = get_record(id, dist).duplicate()
	var first := not bool(r.get("cleared", false))
	var new_stars := maxi(0, stars - int(r.get("best_stars", 0)))
	var better := first or new_stars > 0
	r["cleared"] = true
	r["best_stars"] = maxi(stars, int(r.get("best_stars", 0)))
	var bt := float(r.get("best_time", -1.0))
	if bt < 0.0 or time_s < bt:
		r["best_time"] = snappedf(time_s, 0.01)
		better = true
	if not data.levels.has(id):
		data.levels[id] = {}
	data.levels[id][dist] = r
	return {"better": better, "first_clear": first, "new_stars": new_stars}

func add_points(p: int) -> void:
	data["points"] = int(data.get("points", 0)) + p

func points() -> int:
	return int(data.get("points", 0))

## Unlock: first level open; a level opens when the previous one (or its unlock_after) is cleared at any distance.
func is_unlocked(levels: Array, i: int) -> bool:
	if i < 0 or i >= levels.size():
		return false
	var L: Dictionary = levels[i]
	if L.has("unlock_after"):
		return cleared_any(str(L.unlock_after))
	if i == 0:
		return true
	return cleared_any(str(levels[i - 1].get("id")))

func get_setting(key: String, default = null):
	return data.get("settings", {}).get(key, default)

func set_setting(key: String, value) -> void:
	if not data.has("settings"):
		data["settings"] = {}
	data.settings[key] = value

func clear_all() -> void:
	data = {"version": VERSION, "points": 0, "levels": {}, "settings": {}}
