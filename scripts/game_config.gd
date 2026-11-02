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
