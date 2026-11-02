extends RefCounted
## Everything loaded at runtime MUST be preloaded here, otherwise the
## all_resources export filter silently drops it (lesson from Kana Run 1.0).
## Romaji -> voice clip for level 1 (copied from Kana Run 1.0 audio/kana/).

const VOICE := {
	"a": preload("res://audio/kana/a.mp3"),
	"i": preload("res://audio/kana/i.mp3"),
	"u": preload("res://audio/kana/u.mp3"),
	"e": preload("res://audio/kana/e.mp3"),
	"o": preload("res://audio/kana/o.mp3"),
}

const SFX := {
	"shatter": preload("res://audio/sfx/shatter.mp3"),
	"miss": preload("res://audio/sfx/miss.mp3"),
	"tick": preload("res://audio/sfx/tick.mp3"),
	"shift": preload("res://audio/sfx/shift.mp3"),
	"tap": preload("res://audio/sfx/tap.mp3"),
	"back": preload("res://audio/sfx/back.mp3"),
}

const MUSIC := {
	"res://audio/music/dash.mp3": preload("res://audio/music/dash.mp3"),
}

const FONT_KANA := preload("res://assets/fonts/bold.ttf")
const FONT_UI := preload("res://assets/fonts/ui.ttf")
const CONFIG_JSON := preload("res://config/game_config.json")
