extends RefCounted
## Builds playable level data from config "levels" + "kana_rows" + distance tables.
## Level structure follows the Kana Warrior STAGES / KATAKANA_STAGES skeleton
## (poolRows, order, boss stages, knowledge text only).

const Assets = preload("res://scripts/asset_manifest.gd")

## kana -> romaji for every row in config
static func romaji_map(cfg: Dictionary) -> Dictionary:
	var m := {}
	var rows: Dictionary = cfg.get("kana_rows", {})
	for r in rows:
		for pair in rows[r]:
			m[pair[0]] = pair[1]
	return m

static func has_voice(romaji: String) -> bool:
	return Assets.VOICE.has(romaji) and Assets.VOICE[romaji] != null

## Kana of the given rows that have a voice clip (others can't be asked by ear).
static func pool_for_rows(cfg: Dictionary, rows: Array) -> Array:
	var out: Array = []
	var R: Dictionary = cfg.get("kana_rows", {})
	for r in rows:
		for pair in R.get(r, []):
			if has_voice(pair[1]) and not out.has(pair[0]):
				out.append(pair[0])
	return out

static func missing_voice(cfg: Dictionary, rows: Array) -> Array:
	var out: Array = []
	var R: Dictionary = cfg.get("kana_rows", {})
	for r in rows:
		for pair in R.get(r, []):
			if not has_voice(pair[1]):
				out.append(pair[0])
	return out

static func count_for(cfg: Dictionary, lvl: Dictionary, dist: String) -> int:
	var ov: Dictionary = lvl.get("count_override", {})
	if ov.has(dist):
		return int(ov[dist])
	var D: Dictionary = cfg.get("distances", {}).get("count", {})
	return int(D.get(dist, D.get("short", {})).get(str(lvl.get("type", "normal")), 15))

## Provisional limits: T_dev = count x sec_per_q; clear/2-star/3-star = T_dev x multipliers (ceil).
static func limits_for(cfg: Dictionary, lvl: Dictionary, count: int) -> Dictionary:
	if lvl.has("limits"):
		return lvl.limits
	var F: Dictionary = cfg.get("limit_formula", {})
	var spq := float(F.get("sec_per_q", {}).get(str(lvl.get("type", "normal")), 1.6))
	var t := count * spq
	return {"t_dev": t, "time_limit_s": ceilf(t * float(F.get("clear", 2.0)) - 0.0001),
		"star2_s": ceilf(t * float(F.get("star2", 1.5)) - 0.0001), "star3_s": ceilf(t * float(F.get("star3", 1.15)) - 0.0001)}

## Rows learned in earlier stages of the same script (mirrors getLearnedPoolRows, excluding own rows).
static func learned_rows(levels: Array, index: int) -> Array:
	var me: Dictionary = levels[index]
	var out: Array = []
	for i in index:
		var L: Dictionary = levels[i]
		if L.get("script") != me.get("script"):
			continue
		for r in L.get("rows", []):
			if not out.has(r) and not me.get("rows", []).has(r):
				out.append(r)
	return out

## Effective level dict used by the game (adds kana pool, counts, limits ...).
static func effective(cfg: Dictionary, levels: Array, index: int, dist: String) -> Dictionary:
	var L: Dictionary = levels[index].duplicate(true)
	var rm := romaji_map(cfg)
	L["kana"] = pool_for_rows(cfg, L.get("rows", []))
	L["romaji"] = L.kana.map(func(k): return rm.get(k, ""))
	L["review_kana"] = pool_for_rows(cfg, learned_rows(levels, index)).filter(func(k): return not L.kana.has(k))
	L["missing_voice"] = missing_voice(cfg, L.get("rows", []))
	L["distance"] = dist
	L["target_correct"] = count_for(cfg, L, dist)
	var lim := limits_for(cfg, L, int(L.target_correct))
	for k in lim:
		L[k] = lim[k]
	if not L.has("wrong_penalty_s"): L["wrong_penalty_s"] = 2.0
	if not L.has("miss_penalty_s"): L["miss_penalty_s"] = 1.0
	L["voice_locked"] = L.kana.size() < 3
	return L
