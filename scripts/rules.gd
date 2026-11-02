extends RefCounted
## Level rules helpers (pure functions, unit-tested).

## Returns 0 (fail) .. 3 stars for a final clock (elapsed + penalties).
static func stars_for(clock_s: float, lvl: Dictionary) -> int:
	if clock_s > float(lvl.get("time_limit_s", 60.0)):
		return 0
	if clock_s <= float(lvl.get("star3_s", 32.0)):
		return 3
	if clock_s <= float(lvl.get("star2_s", 44.0)):
		return 2
	return 1

## Which stone (lane index) the player overlaps at lateral position px, or -1.
static func hit_lane(px: float, lane_xs: Array, player_w: float, stone_w: float) -> int:
	var best := -1
	var best_d := INF
	var reach := (player_w + stone_w) * 0.5
	for i in lane_xs.size():
		var d: float = absf(px - float(lane_xs[i]))
		if d < reach and d < best_d:
			best = i
			best_d = d
	return best

## Builds a row: 3 distinct kana, one is the target. Returns {kana:[..], target:int}
static func make_row(pool: Array, prev_target: String, rng: RandomNumberGenerator, lanes := 3) -> Dictionary:
	var choices := pool.duplicate()
	if choices.size() > 1 and prev_target != "":
		choices.erase(prev_target)
	var target: String = choices[rng.randi_range(0, choices.size() - 1)]
	var others := pool.duplicate()
	others.erase(target)
	# shuffle others deterministically with rng
	for i in range(others.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = others[i]; others[i] = others[j]; others[j] = t
	var row: Array = [target]
	for i in range(mini(lanes - 1, others.size())):
		row.append(others[i])
	for i in range(row.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = row[i]; row[i] = row[j]; row[j] = t
	return {"kana": row, "target": row.find(target)}
