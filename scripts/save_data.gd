extends RefCounted
## Progress save: user://save.json  (version 2)
## { "version": 2, "points": 0,
##   "levels": { "1-1": { "short": {"cleared": true, "best_stars": 3, "best_time": 31.3}, "mid": {...} } },
##   "settings": { "speed_mode": "race", "distance": "short" } }
## v1 saves (level_01 / level_02) are migrated: only the "cleared" flag is kept
## (old L1 -> 1-1, old L2 -> 1-2 at 短程); stars/times are reset because the
## question counts changed. Written to a .tmp file, retaining the previous readable .bak.

const VERSION := 2
var path := "user://save.json"
var data := {"version": VERSION, "points": 0, "levels": {}, "settings": {}, "shop": {}, "achievements": {}, "endless": {}, "daily": {}, "mastery": {}}
var unreadable := false

func load_file() -> void:
	clear_all()
	var parsed = _read_save(path)
	if not parsed is Dictionary:
		var backup := path + ".bak"
		parsed = _read_save(backup)
		if not parsed is Dictionary:
			if FileAccess.file_exists(path) or FileAccess.file_exists(backup):
				unreadable = true
				push_warning("No readable save at %s or %s; starting with default progress." % [path, backup])
			return
		if FileAccess.file_exists(path):
			push_warning("Unreadable save at %s; recovered progress from %s." % [path, backup])
	if _number(parsed.get("version", 1), VERSION) < VERSION:
		data = migrate_v1(parsed)
		return
	data = parsed
	data["settings"] = _as_dict(data.get("settings"))
	data["points"] = int(_number(data.get("points"), 0))
	data["shop"] = _as_dict(data.get("shop"))
	data["achievements"] = _as_dict(data.get("achievements"))
	data["endless"] = _as_dict(data.get("endless"))
	data["daily"] = _as_dict(data.get("daily"))
	data["mastery"] = _as_dict(data.get("mastery"))
	data["levels"] = _as_dict(data.get("levels"))
	for id in data.levels.keys():
		var distances = data.levels[id]
		if not distances is Dictionary:
			data.levels.erase(id)
			continue
		for dist in distances.keys():
			var entry = distances[dist]
			if not entry is Dictionary:
				distances.erase(dist)
				continue
			var cleared = entry.get("cleared", false)
			entry["cleared"] = cleared is bool and cleared
			entry["best_stars"] = int(_number(entry.get("best_stars"), 0))
			entry["best_time"] = _number(entry.get("best_time"), -1.0)

static func _read_save(source: String) -> Variant:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	return json.data if json.parse(file.get_as_text()) == OK else null

static func _as_dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func _number(value: Variant, fallback: float) -> float:
	return float(value) if (value is int or value is float) and is_finite(float(value)) else fallback

static func migrate_v1(old: Dictionary) -> Dictionary:
	var d := {"version": VERSION, "points": 0, "levels": {}, "settings": _as_dict(old.get("settings")).duplicate(), "shop": {}, "achievements": {}, "endless": {}, "daily": {}, "mastery": {}}
	var map := {"level_01": "1-1", "level_02": "1-2"}
	var L := _as_dict(old.get("levels"))
	for k in map:
		var cleared = _as_dict(L.get(k)).get("cleared", false)
		if cleared is bool and cleared:
			d.levels[map[k]] = {"short": {"cleared": true, "best_stars": 0, "best_time": -1.0}}
	return d

func save_file() -> bool:
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	var name := path.get_file()
	var tmp := name + ".tmp"
	var backup := name + ".bak"
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	var stored := f.store_string(JSON.stringify(data, "  "))
	f.flush()
	stored = stored and f.get_error() == OK
	f.close()
	if not stored:
		dir.remove(tmp)
		return false
	# On Windows DirAccess.rename can delete its destination even if the move fails.
	if dir.file_exists(name):
		# A corrupt primary must not replace the last readable backup.
		var keep_backup := dir.file_exists(backup) and not _read_save(path) is Dictionary \
			and _read_save(path + ".bak") is Dictionary
		var staged := dir.remove(name) if keep_backup else dir.rename(name, backup)
		if staged != OK:
			dir.remove(tmp)
			return false
	if dir.rename(tmp, name) != OK:
		if dir.file_exists(backup) and not dir.file_exists(name):
			dir.rename(backup, name)
		dir.remove(tmp)
		return false
	unreadable = false
	return true

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
	var rounded_time := snappedf(time_s, 0.01)
	if bt < 0.0 or rounded_time < snappedf(bt, 0.01):
		r["best_time"] = rounded_time
		better = true
	if not data.levels.has(id):
		data.levels[id] = {}
	data.levels[id][dist] = r
	return {"better": better, "first_clear": first, "new_stars": new_stars}

func add_points(p: int) -> void:
	data["points"] = int(data.get("points", 0)) + p

func points() -> int:
	return int(data.get("points", 0))

func get_shop() -> Dictionary:
	if not data.get("shop") is Dictionary:
		data["shop"] = {}
	var sh: Dictionary = data["shop"]
	if not sh.has("aura"): sh["aura"] = "default"
	if not sh.has("unlocked_auras") or not (sh["unlocked_auras"] is Array): sh["unlocked_auras"] = ["default"]
	if not sh.has("hp_level"): sh["hp_level"] = 0
	if not sh.has("shield_level"): sh["shield_level"] = 0
	if not sh.has("armor_level"): sh["armor_level"] = 0
	return sh

func is_aura_unlocked(aura_id: String) -> bool:
	if aura_id == "default":
		return true
	var sh := get_shop()
	return (sh.get("unlocked_auras", []) as Array).has(aura_id)

func unlock_aura(aura_id: String, cost: int) -> bool:
	if is_aura_unlocked(aura_id):
		return true
	if points() < cost:
		return false
	add_points(-cost)
	var sh := get_shop()
	var arr: Array = sh.get("unlocked_auras", [])
	if not arr.has(aura_id):
		arr.append(aura_id)
	sh["unlocked_auras"] = arr
	return true

func equip_aura(aura_id: String) -> void:
	if is_aura_unlocked(aura_id):
		var sh := get_shop()
		sh["aura"] = aura_id

func get_equipped_aura() -> String:
	return str(get_shop().get("aura", "default"))

func get_upgrade_level(upgrade_id: String) -> int:
	var sh := get_shop()
	return int(sh.get(upgrade_id, 0))

func buy_upgrade(upgrade_id: String, max_level: int, cost: int) -> bool:
	var cur: int = get_upgrade_level(upgrade_id)
	if cur >= max_level or points() < cost:
		return false
	add_points(-cost)
	var sh := get_shop()
	sh[upgrade_id] = cur + 1
	return true

func get_achievements() -> Dictionary:
	if not data.get("achievements") is Dictionary:
		data["achievements"] = {}
	return data["achievements"]

func is_achievement_unlocked(id: String) -> bool:
	var entry = get_achievements().get(id)
	if entry is bool:
		return entry
	if entry is Dictionary:
		return bool(entry.get("unlocked", false))
	return false

func is_achievement_claimed(id: String) -> bool:
	var entry = get_achievements().get(id)
	if entry is Dictionary:
		return bool(entry.get("claimed", false))
	return false

func unlock_achievement(id: String) -> bool:
	if is_achievement_unlocked(id):
		return false
	var ach := get_achievements()
	ach[id] = {
		"unlocked": true,
		"claimed": false,
		"time": Time.get_datetime_string_from_system()
	}
	return true

func claim_achievement(id: String, reward_pts: int) -> bool:
	if not is_achievement_unlocked(id) or is_achievement_claimed(id):
		return false
	var ach := get_achievements()
	var entry: Dictionary = _as_dict(ach.get(id))
	entry["claimed"] = true
	ach[id] = entry
	if reward_pts > 0:
		add_points(reward_pts)
	return true

func achievement_count() -> int:
	var count := 0
	for k in get_achievements().keys():
		if is_achievement_unlocked(str(k)):
			count += 1
	return count

func unclaimed_achievement_count() -> int:
	var count := 0
	for k in get_achievements().keys():
		if is_achievement_unlocked(str(k)) and not is_achievement_claimed(str(k)):
			count += 1
	return count

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

func get_endless() -> Dictionary:
	if not data.get("endless") is Dictionary:
		data["endless"] = {}
	var ed: Dictionary = data["endless"]
	if not ed.has("best_score"): ed["best_score"] = 0
	if not ed.has("best_distance"): ed["best_distance"] = 0.0
	if not ed.has("best_correct"): ed["best_correct"] = 0
	if not ed.has("best_combo"): ed["best_combo"] = 0
	if not ed.has("history") or not (ed["history"] is Array): ed["history"] = []
	return ed

func get_endless_best_score() -> int:
	return int(get_endless().get("best_score", 0))

func record_endless(score: int, distance_m: float, correct_cnt: int, combo_cnt: int) -> Dictionary:
	var ed := get_endless()
	var prev_best: int = int(ed.get("best_score", 0))
	var new_high: bool = score > prev_best
	if new_high:
		ed["best_score"] = score
	ed["best_distance"] = maxf(float(ed.get("best_distance", 0.0)), distance_m)
	ed["best_correct"] = maxi(int(ed.get("best_correct", 0)), correct_cnt)
	ed["best_combo"] = maxi(int(ed.get("best_combo", 0)), combo_cnt)

	var hist: Array = ed.get("history", [])
	hist.append({
		"score": score,
		"distance": snappedf(distance_m, 0.1),
		"correct": correct_cnt,
		"combo": combo_cnt,
		"time": Time.get_datetime_string_from_system()
	})
	hist.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	if hist.size() > 5:
		hist.resize(5)
	ed["history"] = hist
	return {"new_high_score": new_high, "score": score, "best_score": int(ed["best_score"])}

func clear_all() -> void:
	data = {"version": VERSION, "points": 0, "levels": {}, "settings": {}, "shop": {}, "achievements": {}, "endless": {}, "daily": {}, "mastery": {}}
	unreadable = false

# ---------------------------------------------------------------- daily challenge & streak
func get_daily() -> Dictionary:
	if not data.get("daily") is Dictionary:
		data["daily"] = {}
	var d: Dictionary = data["daily"]
	if not d.has("last_date"): d["last_date"] = ""
	if not d.has("streak"): d["streak"] = 0
	if not d.has("best_streak"): d["best_streak"] = 0
	if not d.has("today_completed"): d["today_completed"] = false
	if not d.has("today_score"): d["today_score"] = 0
	return d

func check_daily_status() -> Dictionary:
	var d := get_daily()
	var today := Time.get_date_string_from_system()
	if str(d.get("last_date", "")) != today:
		d["today_completed"] = false
		d["today_score"] = 0
	return {
		"today": today,
		"streak": int(d.get("streak", 0)),
		"best_streak": int(d.get("best_streak", 0)),
		"completed": bool(d.get("today_completed", false))
	}

func record_daily_clear(score := 100) -> Dictionary:
	var d := get_daily()
	var today := Time.get_date_string_from_system()
	var was_completed: bool = (str(d.get("last_date", "")) == today and bool(d.get("today_completed", false)))
	var is_first_today: bool = not was_completed

	if is_first_today:
		var yesterday := _get_yesterday_string()
		var last_d: String = str(d.get("last_date", ""))
		if last_d == yesterday:
			d["streak"] = int(d.get("streak", 0)) + 1
		elif last_d == today:
			pass
		else:
			d["streak"] = 1

		d["best_streak"] = maxi(int(d.get("best_streak", 0)), int(d["streak"]))
		d["last_date"] = today
		d["today_completed"] = true
		d["today_score"] = score
		add_points(100)
	return {
		"first_today": is_first_today,
		"streak": int(d.get("streak", 1)),
		"points_awarded": 100 if is_first_today else 0
	}

func _get_yesterday_string() -> String:
	var unix := Time.get_unix_time_from_system() - 86400
	var dt := Time.get_date_dict_from_unix_time(int(unix))
	return "%04d-%02d-%02d" % [int(dt.get("year", 2026)), int(dt.get("month", 1)), int(dt.get("day", 1))]

# ---------------------------------------------------------------- kana mastery tracking
func record_kana_stat(kana: String, result: String, reaction_s: float) -> void:
	if kana == "":
		return
	if not data.get("mastery") is Dictionary:
		data["mastery"] = {}
	var m: Dictionary = data["mastery"]
	var entry: Dictionary = _as_dict(m.get(kana))
	entry["attempts"] = int(entry.get("attempts", 0)) + 1
	if result == "correct" or result == "shield":
		entry["correct"] = int(entry.get("correct", 0)) + 1
		entry["total_reaction"] = float(entry.get("total_reaction", 0.0)) + maxf(0.05, reaction_s)
	elif result == "wrong":
		entry["wrong"] = int(entry.get("wrong", 0)) + 1
	elif result == "miss":
		entry["miss"] = int(entry.get("miss", 0)) + 1
	m[kana] = entry

func get_kana_stat(kana: String) -> Dictionary:
	if not data.get("mastery") is Dictionary:
		return {}
	return _as_dict(data["mastery"].get(kana))

func get_kana_tier(kana: String) -> String:
	var s := get_kana_stat(kana)
	var att := int(s.get("attempts", 0))
	if att < 2:
		return "untested"
	var cor := int(s.get("correct", 0))
	var acc := float(cor) / float(att)
	var avg_r := float(s.get("total_reaction", 0.0)) / maxf(1.0, float(cor))
	if acc >= 0.85 and avg_r < 0.95:
		return "mastered"
	elif acc < 0.65 or avg_r > 1.30:
		return "weak"
	return "learning"

func get_weakest_kana(limit := 5) -> Array:
	if not data.get("mastery") is Dictionary:
		return []
	var m: Dictionary = data["mastery"]
	var candidates: Array = []
	for k in m.keys():
		var s: Dictionary = m[k]
		var att := int(s.get("attempts", 0))
		if att >= 1:
			var cor := int(s.get("correct", 0))
			var acc := float(cor) / float(att)
			var avg_r := float(s.get("total_reaction", 0.0)) / maxf(1.0, float(cor))
			var weakness_score := (1.0 - acc) * 2.5 + avg_r
			candidates.append({"kana": k, "score": weakness_score})
	candidates.sort_custom(func(a, b): return float(a.score) > float(b.score))
	var result: Array = []
	for i in mini(limit, candidates.size()):
		result.append(str(candidates[i].kana))
	return result

# ---------------------------------------------------------------- player rank & title
func get_total_stars() -> int:
	var total := 0
	var L: Dictionary = data.get("levels", {})
	for id in L:
		var dists: Dictionary = _as_dict(L[id])
		for d in dists:
			var entry: Dictionary = _as_dict(dists[d])
			total += int(entry.get("best_stars", 0))
	return total

func get_player_rank() -> Dictionary:
	var stars := get_total_stars()
	var endless_pts := get_endless_best_score()
	var streak := int(get_daily().get("streak", 0))

	if stars >= 80 or (stars >= 50 and endless_pts >= 4000) or streak >= 30:
		return {"tier": 5, "title": "賽博假名武神", "badge": "★ 武神", "color": Color(1.0, 0.85, 0.2), "desc": "達到全五十音神速反射境界"}
	elif stars >= 55 or endless_pts >= 2200 or streak >= 14:
		return {"tier": 4, "title": "音速破碑者", "badge": "◆ 音速", "color": Color(0.35, 0.95, 1.0), "desc": "超越音障，石碑應聲粉碎"}
	elif stars >= 30 or endless_pts >= 1000 or streak >= 7:
		return {"tier": 3, "title": "澀谷極速客", "badge": "▲ 極速", "color": Color(0.9, 0.4, 1.0), "desc": "縱橫澀谷夜城的疾走高手"}
	elif stars >= 12 or endless_pts >= 400 or streak >= 3:
		return {"tier": 2, "title": "霓虹巡航者", "badge": "● 巡航", "color": Color(0.3, 0.85, 0.6), "desc": "熟練駕馭假名賽道的街頭新星"}
	else:
		return {"tier": 1, "title": "街頭新手", "badge": "■ 新手", "color": Color(0.7, 0.75, 0.85), "desc": "初入澀谷賽博賽道的挑戰者"}
