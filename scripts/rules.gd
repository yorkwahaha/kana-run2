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

## Row whose target is `target`, placed in any lane except avoid_lane (-1 = any).
static func make_row_with_target(pool: Array, target: String, avoid_lane: int, rng: RandomNumberGenerator, lanes := 3) -> Dictionary:
	var others := pool.duplicate()
	others.erase(target)
	for i in range(others.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = others[i]; others[i] = others[j]; others[j] = t
	var n := mini(lanes, others.size() + 1)
	var allowed: Array = []
	for i in n:
		if i != avoid_lane:
			allowed.append(i)
	if allowed.is_empty():
		allowed.append(0)
	var tl: int = allowed[rng.randi_range(0, allowed.size() - 1)]
	var row: Array = []
	var oi := 0
	for i in n:
		if i == tl:
			row.append(target)
		else:
			row.append(others[oi]); oi += 1
	return {"kana": row, "target": tl}

## Romaji hint shown for a kana's first N appearances, and only before progress reaches ratio.
static func hint_visible(seen_before: int, first_n: int, progress: float, ratio: float) -> bool:
	return seen_before < first_n and progress < ratio

## Removes from a distractor list everything that sounds like the target or is the target.
static func filter_same_sound(others: Array, target: String, same_sound: Array) -> Array:
	var bad := [target]
	for g in same_sound:
		if g.has(target):
			bad.append_array(g)
	return others.filter(func(k): return not bad.has(k))

## Builds a row with an explicit/optional target, same-sound filtering and lookalike-preferred distractors.
## lookalikes: {kana: [similar kana]} (KATA_LOOKALIKES). Returns {kana:[..], target:int}.
static func make_row_ex(pool: Array, target: String, prev_target: String, avoid_lane: int, rng: RandomNumberGenerator,
		lanes := 3, lookalikes := {}, same_sound := [], extra_pool := []) -> Dictionary:
	if target == "":
		var choices := pool.duplicate()
		if choices.size() > 1 and prev_target != "":
			choices.erase(prev_target)
		target = choices[rng.randi_range(0, choices.size() - 1)]
	var others := filter_same_sound(pool, target, same_sound)
	for i in range(others.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = others[i]; others[i] = others[j]; others[j] = t
	var look: Array = filter_same_sound(lookalikes.get(target, []), target, same_sound).filter(
		func(k): return others.has(k) or extra_pool.has(k))
	var picks: Array = []
	for k in look:
		if picks.size() < mini(1, lanes - 1):   # at most one lookalike trap per row
			picks.append(k)
	for k in others:
		if picks.size() >= lanes - 1:
			break
		if not picks.has(k):
			picks.append(k)
	var n := picks.size() + 1
	var allowed: Array = []
	for i in n:
		if i != avoid_lane:
			allowed.append(i)
	if allowed.is_empty():
		allowed.append(0)
	var tl: int = allowed[rng.randi_range(0, allowed.size() - 1)]
	for i in range(picks.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = picks[i]; picks[i] = picks[j]; picks[j] = t
	var row: Array = []
	var oi := 0
	for i in n:
		if i == tl:
			row.append(target)
		else:
			row.append(picks[oi]); oi += 1
	return {"kana": row, "target": tl}

## Points: base = first_clear (first clear at this distance) or repeat_clear, + new_star per newly earned star;
## result = round_half_up(base x distance multiplier).
static func points_for(first_clear: bool, new_stars: int, multiplier: float, pcfg: Dictionary) -> int:
	var base := (int(pcfg.get("first_clear", 10)) if first_clear else int(pcfg.get("repeat_clear", 2))) \
		+ new_stars * int(pcfg.get("new_star", 5))
	return int(floor(base * multiplier + 0.5))
