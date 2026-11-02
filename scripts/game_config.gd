extends RefCounted
## Loads res://config/game_config.json, then merges user://game_config_override.json
## (optional, for tuning on a device without re-exporting).
## Note: the JSON is bundled into exports via scripts/asset_manifest.gd (see README).

const PATH := "res://config/game_config.json"
const OVERRIDE_PATH := "user://game_config_override.json"

static func load_config() -> Dictionary:
	var data: Dictionary = {}
	var parsed = _read_json(PATH)
	if parsed is Dictionary:
		data = parsed
	else:
		push_error("game_config.json missing or invalid")
	var o = _read_json(OVERRIDE_PATH)
	if o is Dictionary:
		_merge(data, o)
	return data

static func _read_json(p: String):
	if not FileAccess.file_exists(p):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(p))

static func _merge(a: Dictionary, b: Dictionary) -> void:
	for k in b:
		if a.has(k) and a[k] is Dictionary and b[k] is Dictionary:
			_merge(a[k], b[k])
		else:
			a[k] = b[k]

## Ordered level list. Accepts an array of {id,...} or a legacy {id: {...}} dict.
static func levels(cfg: Dictionary) -> Array:
	var L = cfg.get("levels", [])
	var out: Array = []
	if L is Array:
		for i in L.size():
			var d: Dictionary = L[i]
			if not d.has("id"):
				d["id"] = "level_%02d" % (i + 1)
			out.append(d)
	elif L is Dictionary:
		var keys: Array = L.keys()
		keys.sort()
		for k in keys:
			var d: Dictionary = L[k]
			d["id"] = k
			out.append(d)
	return out
