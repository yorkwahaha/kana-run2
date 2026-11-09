extends Node3D
## Kana Run 2.0 - Level 1 prototype.
## Everything (world, HUD, audio) is built in code so the scene file stays
## trivial and easy to merge. Tunables live in config/game_config.json.

const GameConfig = preload("res://scripts/game_config.gd")
const SpeedController = preload("res://scripts/speed_controller.gd")
const Rules = preload("res://scripts/rules.gd")
const DevLogger = preload("res://scripts/dev_logger.gd")
const Assets = preload("res://scripts/asset_manifest.gd")
const SaveData = preload("res://scripts/save_data.gd")
const LevelDB = preload("res://scripts/level_db.gd")
const Art = preload("res://scripts/art_manifest.gd")
const RunnerSprite = preload("res://scripts/runner_sprite.gd")
const StoneTablet = preload("res://scripts/stone_tablet.gd")
var stone_mesh: ArrayMesh
var stone_material: ShaderMaterial

## HP hooks for later upgrades: (hp, max_hp, shield)
signal hp_changed(hp: int, max_hp: int, shield: int)
## Emitted when damage is taken (amount) or blocked by a shield (amount 0).
signal damaged(amount: int, blocked: bool)

enum State { SELECT, READY, RUNNING, PAUSED, CLEARED, FAILED, TITLE }

var level_id := "level_01"
var level_index := 0
var levels: Array = []
var save = SaveData.new()
## Tests point this at a scratch file.
var save_path := "user://save.json"
## Tests set this to skip the level-select screen on start.
var skip_select := false
## Tests set this to skip the title screen on start.
var skip_title := false
var instant_transitions := false
var is_transitioning := false
## Set by tools/smoke_test.gd: steers to the right lane and holds accelerate.
var autopilot := false
var force_dev_mode := false
var rng_seed := -1
## Safe area test/simulation override rect in physical window coordinates.
## If empty/zero, DisplayServer.get_display_safe_area() is used.
var safe_area_rect_override: Rect2i = Rect2i()
## Joypad / Gamepad analog axis and trigger tracking
var joy_axis_x_steered := false
var joy_trigger_right_held := false
var joy_trigger_left_held := false
var current_input_device: String = "keyboard"
var vibration_enabled := true
var btn_vibration: Button
var btn_hit_pitch: Button
var pad_bar: Label
var lbl_badge_accel: Label
var lbl_badge_brake: Label
var lbl_badge_lock: Label
var lbl_badge_voice: Label

var cfg: Dictionary
var lvl: Dictionary
var state: State = State.READY
var ctrl = SpeedController.new()
var logger = DevLogger.new()
var rng := RandomNumberGenerator.new()
var dev_mode := false

# run state
var elapsed := 0.0
var penalty := 0.0
var shield_bonus := 0.0
var runner_opacity := 1.0
var endless_slow_timer := 0.0
var endless_drain_tick := 0.0
var correct := 0
var wrong := 0
var missed := 0
var player_dist := 0.0
var lane := 1
var player_x := 0.0
var rows: Array = []          # Array[Dictionary]
var next_row_dist := 0.0
var q_counter := 0
var question_draws := {}
var result_time := 0.0
var progress_pending := false
var last_saved_path := ""
var combo := 0
var best_combo := 0
var appearances := {}
var voice_only_announced := false
var requeue: Array = []
var hint_first_n := 3
var hint_ratio := 0.5

# tunables (cached)
var lane_w := 2.2
var lane_count := 3
var lane_change_speed := 13.75
var swipe_min := 40.0
var player_w := 0.9
var stone_w := 1.2
var row_spacing := 24.0
var first_row := 30.0
var spawn_ahead := 80.0

# touch
## index -> {"role": "accel"|"brake"|"swipe", "anchor": Vector2}
var touches := {}
var pause_count := 0
## "race" (賽車) or "step" (點放). Saved in save.json settings. Tests may force it.
var speed_mode := "race"
var force_mode := ""
var btn_lock: Panel
var btn_mode_pause: Button
var btn_mode_pause_race: Button
var btn_mode_pause_step: Button
var settings_box: Control
var lbl_settings_mode: Label
var btn_settings: Button
var btn_mode_race: Button
var btn_mode_step: Button
var btn_vol_bgm: Button
var btn_vol_sfx: Button
var btn_vol_voice: Button
var btn_lang: Button
var btn_settings_back: Button
var rank_box: Control
var lbl_rank: Label
var shop_box: Control
var shop_scroll: ScrollContainer
var shop_list: VBoxContainer
var lbl_shop_points: Label
var btn_shop: Button
var btn_shop_back: Button
var achievements_box: Control
var achievements_scroll: ScrollContainer
var achievements_list: VBoxContainer
var lbl_achievements_count: Label
var btn_achievements: Button
var btn_achievements_back: Button
var btn_claim_all: Button = null
var is_endless := false
var is_daily := false
var btn_daily: Button
var endless_score := 0
var endless_tier := 0
var btn_endless: Button
var endless_box: Control
var endless_scroll: ScrollContainer
var endless_list: VBoxContainer
var btn_endless_start: Button
var btn_endless_back: Button
var achievement_toast: PanelContainer = null
var toast_lbl_name: Label = null
var toast_lbl_desc: Label = null
var toast_queue: Array = []
var toast_tween: Tween = null
var runner_trail: CPUParticles3D = null

const PENTATONIC_RATIOS := [1.0, 1.12246, 1.25992, 1.49831, 1.68179]

const AURAS := {
	"default": {
		"name": "經典賽博藍紫",
		"name_key": "AURA_DEFAULT_NAME",
		"desc": "原廠俐落身法",
		"desc_key": "AURA_DEFAULT_DESC",
		"cost": 0,
		"color": Color(0.48, 0.44, 0.95),
		"strength": 0.0,
		"rim_color": Color(0.48, 0.44, 0.95),
		"rim_strength": 0.0,
		"trail_color": Color(0.35, 0.65, 1.0, 0.75)
	},
	"cyan": {
		"name": "澀谷霓虹藍",
		"name_key": "AURA_CYAN_NAME",
		"desc": "疾走電光殘影",
		"desc_key": "AURA_CYAN_DESC",
		"cost": 100,
		"color": Color(0.15, 0.95, 1.0),
		"strength": 0.55,
		"rim_color": Color(0.2, 0.95, 1.0),
		"rim_strength": 0.60,
		"trail_color": Color(0.18, 0.92, 1.0, 0.85)
	},
	"emerald": {
		"name": "駭客矩陣翠綠",
		"name_key": "AURA_EMERALD_NAME",
		"desc": "超頻數據流光",
		"desc_key": "AURA_EMERALD_DESC",
		"cost": 150,
		"color": Color(0.15, 1.0, 0.45),
		"strength": 0.58,
		"rim_color": Color(0.2, 1.0, 0.5),
		"rim_strength": 0.65,
		"trail_color": Color(0.2, 0.95, 0.4, 0.85)
	},
	"pink": {
		"name": "櫻花幻粉",
		"name_key": "AURA_PINK_NAME",
		"desc": "春櫻漫天流光",
		"desc_key": "AURA_PINK_DESC",
		"cost": 200,
		"color": Color(1.0, 0.42, 0.82),
		"strength": 0.55,
		"rim_color": Color(1.0, 0.5, 0.85),
		"rim_strength": 0.60,
		"trail_color": Color(1.0, 0.45, 0.85, 0.85)
	},
	"crimson": {
		"name": "赤紅浪人鬼斬",
		"name_key": "AURA_CRIMSON_NAME",
		"desc": "熾熱業火殘影",
		"desc_key": "AURA_CRIMSON_DESC",
		"cost": 250,
		"color": Color(1.0, 0.22, 0.26),
		"strength": 0.65,
		"rim_color": Color(1.0, 0.3, 0.35),
		"rim_strength": 0.70,
		"trail_color": Color(1.0, 0.2, 0.25, 0.9)
	},
	"synthwave": {
		"name": "落日合成波",
		"name_key": "AURA_SYNTHWAVE_NAME",
		"desc": "80s 復古霓虹雙色",
		"desc_key": "AURA_SYNTHWAVE_DESC",
		"cost": 350,
		"color": Color(0.95, 0.25, 0.90),
		"strength": 0.60,
		"rim_color": Color(1.0, 0.35, 0.8),
		"rim_strength": 0.65,
		"trail_color": Color(0.85, 0.20, 0.90, 0.85)
	},
	"white": {
		"name": "納米零度純白",
		"name_key": "AURA_WHITE_NAME",
		"desc": "冷冽超導體全息裝",
		"desc_key": "AURA_WHITE_DESC",
		"cost": 450,
		"color": Color(0.90, 0.96, 1.0),
		"strength": 0.50,
		"rim_color": Color(0.8, 0.95, 1.0),
		"rim_strength": 0.60,
		"trail_color": Color(0.92, 0.98, 1.0, 0.95)
	},
	"gold": {
		"name": "黃金王者",
		"name_key": "AURA_GOLD_NAME",
		"desc": "滿星傳奇耀光",
		"desc_key": "AURA_GOLD_DESC",
		"cost": 500,
		"color": Color(1.0, 0.86, 0.22),
		"strength": 0.60,
		"rim_color": Color(1.0, 0.9, 0.35),
		"rim_strength": 0.70,
		"trail_color": Color(1.0, 0.85, 0.2, 0.9)
	}
}

const UPGRADES := {
	"hp_level": {
		"name": "強化裝甲",
		"desc": "最大生命值提升 (+20 HP/級)",
		"max_level": 2,
		"costs": [150, 300]
	},
	"shield_level": {
		"name": "防護力場",
		"desc": "開局自帶護盾抵消失誤 (1 層/級)",
		"max_level": 2,
		"costs": [250, 500]
	},
	"armor_level": {
		"name": "緩衝減震",
		"desc": "撞錯石碑扣血減少 (-15%/級)",
		"max_level": 2,
		"costs": [200, 400]
	}
}

const ACHIEVEMENTS := {
	"first_step": {
		"title": "初試身手",
		"desc": "完成任意關卡首次通關",
		"reward": 50,
	},
	"tutorial_done": {
		"title": "起跑整備",
		"desc": "完整通過新手練習",
		"reward": 30,
	},
	"combo_10": {
		"title": "連鎖節奏",
		"desc": "單局達成 10 連擊",
		"reward": 50,
	},
	"combo_30": {
		"title": "心流疾馳",
		"desc": "單局達成 30 連擊",
		"reward": 100,
	},
	"combo_50": {
		"title": "極限連鎖",
		"desc": "單局達成 50 連擊",
		"reward": 200,
	},
	"flawless": {
		"title": "完美無傷",
		"desc": "以滿生命值通關任意關卡",
		"reward": 100,
	},
	"speed_demon": {
		"title": "閃電奔馳",
		"desc": "通關時保持時速 45 km/h 以上",
		"reward": 100,
	},
	"boss_breaker": {
		"title": "護盾粉碎者",
		"desc": "擊破任一 BOSS 關卡全部護盾通關",
		"reward": 150,
	},
	"three_stars": {
		"title": "滿星榮耀",
		"desc": "任意關卡獲得 3 星評級",
		"reward": 100,
	},
	"hira_master": {
		"title": "平假名精通",
		"desc": "通關全部 21 個平假名關卡",
		"reward": 300,
	},
	"kata_pioneer": {
		"title": "片假名先鋒",
		"desc": "解鎖並首次通關片假名關卡",
		"reward": 150,
	},
	"custom_racer": {
		"title": "改裝跑者",
		"desc": "在改裝商城購買任意光芒或升級",
		"reward": 100,
	},
	"endless_runner": {
		"title": "無盡開端",
		"desc": "在無盡極限挑戰中答對 10 題以上",
		"reward": 50,
	},
	"endless_survivor": {
		"title": "極限生還者",
		"desc": "在無盡極限挑戰中答對 30 題以上",
		"reward": 100,
	},
	"endless_marathon": {
		"title": "千里疾走",
		"desc": "在無盡極限挑戰中奔馳超過 1,000 公尺",
		"reward": 150,
	}
}
# HP
var hp := 100
var max_hp := 100
var base_max_hp := 100
var max_hp_bonus := 0         # hook: upgrades add max HP via set_max_hp_bonus(value)
var damage_reduction := 0.0   # hook: percent (0..90) taken off every hit
var shield := 0               # hook: a charm; each point blocks one whole hit
var wrong_damage := 35
var miss_damage := 0
var hp_delayed := 100.0       # the red "chunk" that drains after a short wait
var hp_delay_wait := 0.0
var bar_wait_s := 0.45
var bar_drain := 60.0
var fail_reason := ""     # "", "time_up", "hp_out"
var hearts_box: Control       # HP widget (heart icon + bar + number), top-left
var hp_flash_tween: Tween
var hp_shake_tween: Tween
var hp_shake_offset := 0.0
var hp_fill: NinePatchRect
var hp_chunk: NinePatchRect
var timer_panel: NinePatchRect
var combo_badge: NinePatchRect
var speedo: Control
var speedo_needle: TextureRect
var lbl_lock_kmh: Label
var shield_box: NinePatchRect
var judge: TextureRect
var go_box: Control
var sel_bg: TextureRect
var res_bg: TextureRect
var res_stars: HBoxContainer
var res_badge: TextureRect
const INK := Color(0.96, 0.97, 1.0)
var lbl_hp: Label
var lbl_shield: Label
# distance / points / review / boss shield
var distance := "short"
var force_distance := ""
var review_ratio := 0.2
var lookalikes := {}
var same_sound: Array = []
var shield_thresholds: Array = []
var shield_phase := 0         # how many thresholds have been triggered
var boss_shield_up := false
var break_chain := 2
var break_progress := 0
var shields_broken := 0
var last_points := 0
var last_record := {}
var review_asked := 0
const TUTORIAL_ROWS := [
	{"kana": ["い", "あ", "う"], "target": 1, "prompt": "聽見「あ」，撞上中線石碑。"},
	{"kana": ["い", "う", "あ"], "target": 0, "prompt": "聽到「い」，往左換線。\n手機左右滑，鍵盤用方向鍵。"},
	{"kana": ["あ", "い", "う"], "target": 2, "prompt": "按「重播」或 E 再聽一次。\n換到對應的線，再撞上石碑。"},
]
var tutorial_step := -1
var tutorial_replayed := false
var tutorial_panel: PanelContainer
var tutorial_actions: HBoxContainer
var lbl_tutorial_title: Label
var lbl_tutorial: Label
var btn_tutorial: Button
var btn_tutorial_continue: Button
var select_tab := "hira"
var select_scroll: ScrollContainer
var btn_distance: Button
var btn_tab_hira: Button
var btn_tab_kata: Button
var lbl_points: Label
var lbl_boss: Label
var _js_visibility_cb   # keeps the JavaScriptBridge callback alive (web)

# title & transition nodes
var title_box: Control
var lbl_title_name: Label
var lbl_title_sub: Label
var lbl_title_press: Label
var btn_title_start: Button
var btn_title_settings: Button
var btn_title_quit: Button
var btn_to_title: Button
var title_logo_rect: TextureRect
var press_start_tween: Tween
var transition_layer: CanvasLayer
var fade_rect: ColorRect

# kana chart & drill nodes
var is_drill := false
var btn_chart: Button
var btn_title_chart: Button
var chart_box: Control
var chart_scroll: ScrollContainer
var chart_content: VBoxContainer
var chart_tabs_hbox: HBoxContainer
var chart_tab_buttons: Dictionary = {}
var btn_chart_back: Button
var btn_drill_start: Button
var chart_tab := "hira"
var drill_selected_rows := {}
var drill_count_mode := "short"
var drill_speed_mode := "race"
var lbl_drill_count: Label = null
var lbl_drill_warn: Label = null

const CHART_HIRA_SEION := [
	["あ行", [["あ","a"], ["い","i"], ["う","u"], ["え","e"], ["お","o"]]],
	["か行", [["か","ka"], ["き","ki"], ["く","ku"], ["け","ke"], ["こ","ko"]]],
	["さ行", [["さ","sa"], ["し","shi"], ["す","su"], ["せ","se"], ["そ","so"]]],
	["た行", [["た","ta"], ["ち","chi"], ["つ","tsu"], ["て","te"], ["と","to"]]],
	["な行", [["な","na"], ["に","ni"], ["ぬ","nu"], ["ね","ne"], ["の","no"]]],
	["は行", [["は","ha"], ["ひ","hi"], ["ふ","fu"], ["へ","he"], ["ほ","ho"]]],
	["ま行", [["ま","ma"], ["み","mi"], ["む","mu"], ["め","me"], ["も","mo"]]],
	["や行", [["や","ya"], ["",""], ["ゆ","yu"], ["",""], ["よ","yo"]]],
	["ら行", [["ら","ra"], ["り","ri"], ["る","ru"], ["れ","re"], ["ろ","ro"]]],
	["わ行", [["わ","wa"], ["",""], ["",""], ["",""], ["を","wo"]]],
	["ん",   [["ん","n"], ["",""], ["",""], ["",""], ["",""]]]
]

const CHART_KATA_SEION := [
	["ア行", [["ア","a"], ["イ","i"], ["ウ","u"], ["エ","e"], ["オ","o"]]],
	["カ行", [["カ","ka"], ["キ","ki"], ["ク","ku"], ["ケ","ke"], ["コ","ko"]]],
	["サ行", [["サ","sa"], ["シ","shi"], ["ス","su"], ["セ","se"], ["ソ","so"]]],
	["タ行", [["タ","ta"], ["チ","chi"], ["ツ","tsu"], ["テ","te"], ["ト","to"]]],
	["ナ行", [["ナ","na"], ["ニ","ni"], ["ヌ","nu"], ["ネ","ne"], ["ノ","no"]]],
	["ハ行", [["ハ","ha"], ["ヒ","hi"], ["フ","fu"], ["ヘ","he"], ["ホ","ho"]]],
	["マ行", [["マ","ma"], ["ミ","mi"], ["ム","mu"], ["メ","me"], ["モ","mo"]]],
	["ヤ行", [["ヤ","ya"], ["",""], ["ユ","yu"], ["",""], ["ヨ","yo"]]],
	["ラ行", [["ラ","ra"], ["リ","ri"], ["ル","ru"], ["レ","re"], ["ロ","ro"]]],
	["ワ行", [["ワ","wa"], ["",""], ["",""], ["",""], ["ヲ","wo"]]],
	["ン",   [["ン","n"], ["",""], ["",""], ["",""], ["",""]]]
]

const CHART_DAKUON := [
	["が行", [["が","ga"], ["ぎ","gi"], ["ぐ","gu"], ["げ","ge"], ["ご","go"]]],
	["ざ行", [["ざ","za"], ["じ","ji"], ["ず","zu"], ["ぜ","ze"], ["ぞ","zo"]]],
	["だ行", [["だ","da"], ["ぢ","di"], ["づ","du"], ["で","de"], ["ど","do"]]],
	["ば行", [["ば","ba"], ["び","bi"], ["ぶ","bu"], ["べ","be"], ["ぼ","bo"]]],
	["ぱ行", [["ぱ","pa"], ["ぴ","pi"], ["ぷ","pu"], ["ぺ","pe"], ["ぽ","po"]]],
	["ガ行", [["ガ","ga"], ["ギ","gi"], ["グ","gu"], ["ゲ","ge"], ["ゴ","go"]]],
	["ザ行", [["ザ","za"], ["ジ","ji"], ["ズ","zu"], ["ゼ","ze"], ["ゾ","zo"]]],
	["ダ行", [["ダ","da"], ["ヂ","di"], ["ヅ","du"], ["デ","de"], ["ド","do"]]],
	["バ行", [["バ","ba"], ["ビ","bi"], ["ブ","bu"], ["ベ","be"], ["ボ","bo"]]],
	["パ行", [["パ","pa"], ["ピ","pi"], ["プ","pu"], ["ペ","pe"], ["ポ","po"]]]
]

const CHART_YOUON := [
	["きゃ行", [["きゃ","kya"], ["きゅ","kyu"], ["きょ","kyo"]]],
	["しゃ行", [["しゃ","sha"], ["しゅ","shu"], ["しょ","sho"]]],
	["ちゃ行", [["ちゃ","cha"], ["ちゅ","chu"], ["ちょ","cho"]]],
	["にゃ行", [["にゃ","nya"], ["にゅ","nyu"], ["にょ","nyo"]]],
	["ひゃ行", [["ひゃ","hya"], ["ひゅ","hyu"], ["ひょ","hyo"]]],
	["みゃ行", [["みゃ","mya"], ["みゅ","myu"], ["みょ","myo"]]],
	["りゃ行", [["りゃ","rya"], ["りゅ","ryu"], ["りょ","ryo"]]],
	["ぎゃ行", [["ぎゃ","gya"], ["ぎゅ","gyu"], ["ぎょ","gyo"]]],
	["じゃ行", [["じゃ","ja"], ["じゅ","ju"], ["じょ","jo"]]],
	["びゃ行", [["びゃ","bya"], ["びゅ","byu"], ["びょ","byo"]]],
	["ぴゃ行", [["ぴゃ","pya"], ["ぴゅ","pyu"], ["ぴょ","pyo"]]],
	["キャ行", [["キャ","kya"], ["キュ","kyu"], ["キョ","kyo"]]],
	["シャ行", [["シャ","sha"], ["シュ","shu"], ["ショ","sho"]]],
	["チャ行", [["チャ","cha"], ["チュ","chu"], ["チョ","cho"]]],
	["ニャ行", [["ニャ","nya"], ["ニュ","nyu"], ["ニョ","nyo"]]],
	["ヒャ行", [["ヒャ","hya"], ["ヒュ","hyu"], ["ヒョ","hyo"]]],
	["ミャ行", [["ミャ","mya"], ["ミュ","myu"], ["ミョ","myo"]]],
	["リャ行", [["リャ","rya"], ["リュ","ryu"], ["リョ","ryo"]]],
	["ギャ行", [["ギャ","gya"], ["ギュ","gyu"], ["ギョ","gyo"]]],
	["ジャ行", [["ジャ","ja"], ["ジュ","ju"], ["ジョ","jo"]]],
	["ビャ行", [["ビャ","bya"], ["ビュ","byu"], ["ビョ","byo"]]],
	["ピャ行", [["ピャ","pya"], ["ピュ","pyu"], ["ピョ","pyo"]]]
]


# nodes
var player: Node3D
var player_mesh: MeshInstance3D
var runner          # RunnerSprite (batch07 sheets)
var bg_layer: CanvasLayer
var sky_rect: TextureRect
var far_rect: TextureRect
var props: Array = []
var prop_rng := RandomNumberGenerator.new()   # separate: never touches the question rng
var next_prop := {"near_l": 0.0, "near_r": 0.0, "mid_l": 0.0, "mid_r": 0.0, "far_l": 0.0, "far_r": 0.0}
var road_mats: Array = []
var petals: CPUParticles2D
var fx_layer: CanvasLayer
var speedlines_rect: ColorRect = null
var speedlines_mat: ShaderMaterial = null
var speedlines_intensity: float = 0.0
var hit_flash: ColorRect = null
const TRACK_TILE_M := 6.6
var player_mat: StandardMaterial3D
var cam: Camera3D
var base_fov := 70.0
var stripes: Array = []
var voice: AudioStreamPlayer
var music: AudioStreamPlayer
var sfx_pool: Array = []
var hud: CanvasLayer
var lbl_time: Label
var lbl_count: Label
var lbl_speed: Label
var lbl_center: Label
var ready_box: Control
var ready_title: Label
var ready_knowledge: Label
var lbl_dev: Label
var lbl_float: Label
var lbl_hint: Label
var lbl_combo: Label
var lbl_notice: Label
var notice_tween: Tween
var judge_tween: Tween
var float_tween: Tween
var go_tween: Tween
var combo_tween: Tween
var results_box: Control
var lbl_result_heading: Label
var lbl_result: Label
var btn_retry: Button
var btn_next: Button
var btn_save_retry: Button
var btn_kata_next: Button
var btn_select: Button
var result_body: BoxContainer
var result_actions: GridContainer
var btn_review: Button
var res_split_box: BoxContainer
var res_left_deck: VBoxContainer
var res_right_deck: VBoxContainer
var res_chip_stage: Label
var res_header_row: HBoxContainer
var res_cards_grid: GridContainer
var res_card_time: PanelContainer
var lbl_card_time_val: Label
var lbl_card_time_sub: Label
var res_card_acc: PanelContainer
var lbl_card_acc_val: Label
var lbl_card_acc_sub: Label
var res_card_combo: PanelContainer
var lbl_card_combo_val: Label
var lbl_card_combo_sub: Label
var res_card_pts: PanelContainer
var lbl_card_pts_val: Label
var lbl_card_pts_sub: Label
var res_weak_box: PanelContainer
var res_weak_tiles: HFlowContainer
var res_knowledge_box: PanelContainer
var lbl_res_knowledge: Label
var review_items := {}
var review_index := 0
var review_attempts := 0
var review_box: Control
var review_choices: Array[Button] = []
var lbl_review_progress: Label
var lbl_review_heading: Label
var lbl_review_feedback: Label
var btn_review_replay: Button
var btn_review_next: Button
var btn_review_back: Button
var select_box: Control
var select_list: VBoxContainer
var level_buttons: Array = []
var btn_accel: Panel
var btn_brake: Panel
var btn_pause: Panel
var btn_voice: Panel
var pause_box: Control
var lbl_pause_title: Label
var btn_resume: Button
var btn_restart: Button
var btn_quit: Button

func _ready() -> void:
	if not Assets.FONT_HUD.fallbacks.has(Assets.FONT_HUD_SC):
		Assets.FONT_HUD.fallbacks.append(Assets.FONT_HUD_SC)
	cfg = GameConfig.load_config()
	levels = GameConfig.levels(cfg)
	var HPc: Dictionary = cfg.get("hp", {})
	bar_wait_s = float(HPc.get("delayed_bar_wait_s", 0.45))
	bar_drain = float(HPc.get("delayed_bar_drain_per_s", 60.0))
	save.path = save_path
	save.load_file()
	ctrl.configure(cfg.get("speed", {}))
	var L: Dictionary = cfg.get("lanes", {})
	lane_count = int(L.get("count", 3))
	lane_w = float(L.get("lane_width_m", 2.2))
	lane_change_speed = lane_w / maxf(0.01, float(L.get("lane_change_time_s", 0.16)))
	swipe_min = float(L.get("swipe_min_px", 40))
	player_w = float(L.get("player_width_m", 0.9))
	stone_w = float(L.get("stone_width_m", 1.2))
	var T: Dictionary = cfg.get("track", {})
	var spacing := float(T.get("row_spacing_m", row_spacing))
	if is_finite(spacing) and spacing > 0.0:
		row_spacing = spacing
	first_row = float(T.get("first_row_m", 30.0))
	spawn_ahead = float(T.get("spawn_ahead_m", 80.0))
	dev_mode = force_dev_mode or bool(cfg.get("dev", {}).get("timing_mode", false)) \
		or OS.get_cmdline_user_args().has("--dev")
	_build_world()
	_build_hud()
	_build_tutorial_hud()
	_build_audio()
	_apply_audio_volumes()
	_setup_web_visibility()
	_setup_input_map()
	var saved_loc: String = str(save.get_setting("locale", "zh_TW"))
	set_language(saved_loc, false)
	vibration_enabled = bool(save.get_setting("vibration", true))
	_update_vibration_button()
	_update_input_prompts()
	var m: String = force_mode if force_mode != "" else str(save.get_setting("speed_mode", cfg.get("speed", {}).get("default_mode", "race")))
	set_speed_mode(m, false)
	lookalikes = cfg.get("kata_lookalikes", {})
	same_sound = cfg.get("same_sound", [])
	review_ratio = float(cfg.get("review", {}).get("ratio", 0.2))
	set_distance(force_distance if force_distance != "" else str(save.get_setting("distance", cfg.get("distances", {}).get("default", "short"))), false)
	set_level(level_index)
	reset_run()
	if not skip_select:
		if skip_title:
			show_select()
		else:
			show_title()

## Switch level. Effective data (kana pool, required count, limits) comes from LevelDB for the current distance.
func set_level(i: int) -> void:
	level_index = clampi(i, 0, levels.size() - 1)
	lvl = LevelDB.effective(cfg, levels, level_index, distance)
	level_id = str(lvl.get("id", "level_%02d" % (level_index + 1)))
	_apply_bgm()
	var H: Dictionary = cfg.get("hints", {})
	hint_first_n = int(lvl.get("romaji_first_n", H.get("romaji_first_n", 3)))
	hint_ratio = float(lvl.get("voice_only_after_progress", H.get("voice_only_after_progress", 0.5)))
	var HP: Dictionary = cfg.get("hp", {})
	base_max_hp = maxi(1, int(lvl.get("max_hp", HP.get("max_hp", 100))))
	wrong_damage = int(lvl.get("wrong_damage", HP.get("wrong_damage", 35)))
	miss_damage = int(lvl.get("miss_damage", HP.get("miss_damage", 0)))
	damage_reduction = float(HP.get("damage_reduction_pct", 0.0)) if damage_reduction == 0.0 else damage_reduction
	var BS: Dictionary = cfg.get("boss_shield", {})
	shield_thresholds = []
	var typ := str(lvl.get("type", "normal"))
	if bool(BS.get("enabled", true)) and typ != "normal":
		shield_thresholds = lvl.get("shield_thresholds", BS.get("thresholds", [0.3, 0.6]))
		break_chain = int(BS.get("break_chain", {}).get(typ, 2))

func distance_name(d := "") -> String:
	var dist_key: String = d if d != "" else distance
	if I18n.current_locale == "zh_TW":
		return str(cfg.get("distances", {}).get("names", {}).get(dist_key, dist_key))
	var map := {
		"short": I18n.t("DIST_SHORT", "短程"),
		"mid": I18n.t("DIST_MID", "中程"),
		"long": I18n.t("DIST_LONG", "長程")
	}
	return str(map.get(dist_key, cfg.get("distances", {}).get("names", {}).get(dist_key, dist_key)))

func distance_multiplier(d := "") -> float:
	return float(cfg.get("distances", {}).get("points_multiplier", {}).get(d if d != "" else distance, 1.0))

## 短程 / 中程 / 長程. Saved as the last choice; re-derives the current level's count and limits.
func set_distance(d: String, persist := true) -> void:
	var order: Array = cfg.get("distances", {}).get("order", ["short", "mid", "long"])
	if not order.has(d):
		d = order[0]
	distance = d
	if persist:
		save.set_setting("distance", d)
		_persist_progress()
	if levels.size() > 0 and lvl.size() > 0:
		set_level(level_index)

# ---------------------------------------------------------------- build
func lane_x(i: int) -> float:
	return (i - (lane_count - 1) * 0.5) * lane_w

func _mat(c: Color, emit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.0
	return m

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS     # sky + skyline are 2D layers behind the 3D world
	e.background_canvas_max_layer = -1
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	env.environment = e
	add_child(env)
	bg_layer = CanvasLayer.new()
	bg_layer.layer = -5
	add_child(bg_layer)
	sky_rect = TextureRect.new()
	sky_rect.texture = Art.SKY
	sky_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_px(sky_rect, 0, 0, 1, 1, 0, 0, 0, 0)
	bg_layer.add_child(sky_rect)
	far_rect = TextureRect.new()
	far_rect.texture = Art.FAR
	far_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	far_rect.stretch_mode = TextureRect.STRETCH_TILE
	far_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(far_rect)
	# ground: wide pale base + sidewalks + 3-lane track tile (UV scrolls with distance)
	var base := MeshInstance3D.new()
	var bp := PlaneMesh.new(); bp.size = Vector2(160, 400)
	base.mesh = bp
	var bmat := _mat(Color(0.06, 0.05, 0.12)); bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	base.material_override = bmat
	base.position.y = -0.02
	base.name = "Ground"
	add_child(base)
	for spec in [
		[0.0, lane_w * lane_count, Art.TRACK, TRACK_TILE_M, Color.WHITE],
		[-(lane_w * lane_count * 0.5 + 2.0), 4.0, Art.SIDEWALK, 8.0, Color.WHITE],
		[lane_w * lane_count * 0.5 + 2.0, 4.0, Art.SIDEWALK, 8.0, Color.WHITE],
		[-(lane_w * lane_count * 0.5 + 16.0), 24.0, Art.SIDEWALK, 8.0, Color(0.48, 0.44, 0.62)],
		[lane_w * lane_count * 0.5 + 16.0, 24.0, Art.SIDEWALK, 8.0, Color(0.48, 0.44, 0.62)]
	]:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(spec[1], 400)
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = spec[2]
		m.albedo_color = spec[4]
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.uv1_scale = Vector3(maxf(1.0, float(spec[1]) / 8.0), 400.0 / float(spec[3]), 1)
		m.set_meta("tile", float(spec[3]))
		mi.material_override = m
		mi.position = Vector3(spec[0], 0.02, 0)
		base.add_child(mi)
		road_mats.append(m)
	player = Node3D.new()
	add_child(player)
	player_mesh = MeshInstance3D.new()      # kept for hit tweens; the visible body is the sprite
	player_mat = _mat(Color(1, 1, 1), true)
	player.add_child(player_mesh)
	runner = RunnerSprite.new()
	player_mesh.add_child(runner)
	var shadow := MeshInstance3D.new()
	var sq := QuadMesh.new(); sq.size = Vector2(1.3, 0.65); sq.orientation = PlaneMesh.FACE_Y
	shadow.mesh = sq
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = Art.PIXEL_SHADOW
	sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shadow.material_override = sm
	shadow.position.y = 0.01
	player.add_child(shadow)
	runner_trail = CPUParticles3D.new()
	var trail_quad := QuadMesh.new()
	trail_quad.size = Vector2(0.16, 0.16)
	runner_trail.mesh = trail_quad
	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	trail_mat.vertex_color_use_as_albedo = false
	trail_mat.albedo_color = Color(0.35, 0.65, 1.0, 0.75)
	trail_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	runner_trail.material_override = trail_mat
	runner_trail.local_coords = false
	runner_trail.amount = 20
	runner_trail.lifetime = 0.35
	runner_trail.direction = Vector3(0, 0.3, 1.0)
	runner_trail.spread = 20.0
	runner_trail.gravity = Vector3(0, -0.5, 0)
	runner_trail.initial_velocity_min = 1.5
	runner_trail.initial_velocity_max = 3.5
	runner_trail.scale_amount_min = 0.4
	runner_trail.scale_amount_max = 1.0
	runner_trail.position = Vector3(0, 0.08, 0.2)
	runner_trail.emitting = false
	player.add_child(runner_trail)
	cam = Camera3D.new()
	cam.fov = base_fov
	add_child(cam)
	# petals (zone 1 ambience) on a 2D layer between world and HUD
	fx_layer = CanvasLayer.new()
	fx_layer.layer = 0
	add_child(fx_layer)

	speedlines_mat = ShaderMaterial.new()
	speedlines_mat.shader = preload("res://shaders/speedlines.gdshader")
	speedlines_mat.set_shader_parameter("intensity", 0.0)
	speedlines_mat.set_shader_parameter("inner_radius", 0.32)

	speedlines_rect = ColorRect.new()
	speedlines_rect.name = "SpeedLines"
	speedlines_rect.material = speedlines_mat
	speedlines_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speedlines_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_layer.add_child(speedlines_rect)

	hit_flash = ColorRect.new()
	hit_flash.name = "HitFlash"
	hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	fx_layer.add_child(hit_flash)
	petals = CPUParticles2D.new()
	var at := AtlasTexture.new(); at.atlas = Art.VFX.petals; at.region = Rect2(0, 0, 64, 64)
	petals.texture = at
	petals.amount = 28
	petals.lifetime = 5.0
	petals.preprocess = 5.0
	petals.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	petals.direction = Vector2(0.3, 1)
	petals.spread = 30.0
	petals.gravity = Vector2(0, 40)
	petals.initial_velocity_min = 40.0
	petals.initial_velocity_max = 90.0
	petals.angular_velocity_min = -90.0
	petals.angular_velocity_max = 90.0
	petals.scale_amount_min = 0.5
	petals.scale_amount_max = 1.0
	fx_layer.add_child(petals)

## Roadside props: strictly separated into dedicated left-side and right-side perspective pools
## to prevent perspective inversion and guarantee authentic Shibuya commercial streetscape.
const MID_PROPS_L := ["house_a", "shop", "house_l_record", "house_l_cyber"]
const MID_PROPS_R := ["house_b", "house_r_karaoke", "house_r_109", "house_r_tower"]
const NEAR_PROPS_L := ["vending", "lamp", "fence", "planter", "bench", "shrub"]
const NEAR_PROPS_R := ["vending", "lamp", "fence", "planter", "bench", "shrub"]
const FAR_PROPS_L := ["house_l_record", "house_a", "shop", "house_l_cyber"]
const FAR_PROPS_R := ["house_r_109", "house_r_karaoke", "house_b", "house_r_tower"]
const PROP_H := {"house_a": 8.0, "house_b": 8.0, "house_r_karaoke": 8.0, "house_r_109": 8.0, "house_l_record": 8.0, "house_l_cyber": 8.0, "house_r_tower": 8.5, "shop": 7.5, "wall": 2.2, "sakura_big": 6.0, "sakura_small": 4.6,
	"lamp": 4.2, "bench": 0.9, "planter": 0.9, "shrub": 1.4, "vending": 1.9, "fence": 1.2, "cyber_hologram": 3.4}
func _spawn_props() -> void:
	var far := player_dist + 140.0
	for key in next_prop:
		var is_far: bool = key.begins_with("far")
		var mid: bool = key.begins_with("mid")
		var is_left: bool = key.ends_with("_l")
		var side := -1.0 if is_left else 1.0
		while next_prop[key] < far:
			var pool: Array
			if is_far:
				pool = FAR_PROPS_L if is_left else FAR_PROPS_R
			elif mid:
				pool = MID_PROPS_L if is_left else MID_PROPS_R
			else:
				pool = NEAR_PROPS_L if is_left else NEAR_PROPS_R
			var n: String = pool[prop_rng.randi_range(0, pool.size() - 1)]
			var sp: Sprite3D
			for q in props:
				if not q.visible:
					sp = q
					break
			if sp == null:
				sp = Sprite3D.new()
				sp.shaded = false
				sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
				sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				sp.centered = true
				add_child(sp)
				props.append(sp)
			sp.texture = Art.PROPS[n]
			var sz: Array = Art.PROP_SIZE[n]
			var h_mult: float = 1.35 if is_far else 1.0
			sp.pixel_size = float(PROP_H[n]) * h_mult / float(sz[1])
			var half_w := float(sz[0]) * sp.pixel_size * 0.5
			var road := lane_w * lane_count * 0.5 + 2.0
			var x: float
			if is_far:
				x = road + 7.5 + half_w
				sp.modulate = Color(0.48, 0.44, 0.65, 1.0)
			elif mid:
				x = road + 0.6 + half_w
				sp.modulate = Color.WHITE
			else:
				x = road - 0.3 + half_w * 0.5
				sp.modulate = Color(1.15, 1.25, 1.35, 0.95) if n == "cyber_hologram" else Color.WHITE
			sp.offset = Vector2(0, float(sz[1]) * 0.5)   # bottom-centre anchor (0.5, 1.0)
			sp.position = Vector3(side * x, 0.0, -next_prop[key])
			sp.flip_h = false # strictly preserve Japanese kanji & neon signs from mirroring
			sp.visible = true
			if is_far:
				next_prop[key] += (half_w * 2.0 + prop_rng.randf_range(4.0, 9.0))
			elif mid:
				next_prop[key] += (half_w * 2.0 + prop_rng.randf_range(3.5, 8.0))
			else:
				next_prop[key] += prop_rng.randf_range(6.0, 11.0)
	for q in props:
		if q.visible and q.position.z > -player_dist + 9.0:
			q.visible = false

## All HUD controls are anchored to the viewport (no fixed 720-px design widths),
## so they stay correct when the window / web canvas is wider or narrower.
func _label(size: int, align := HORIZONTAL_ALIGNMENT_LEFT, font: Font = null) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font if font else Assets.FONT_HUD)
	l.add_theme_font_size_override("font_size", int(size * UI))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(l)
	return l

## Base canvas is 1080x1920 (art spec). Offsets/fonts written for the old 720-wide layout are scaled by UI.
const UI := 1.5
static func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, o_r: float, ob: float) -> void:
	_place_px(c, al, at, ar, ab, ol * UI, ot * UI, o_r * UI, ob * UI)

## Offsets in real canvas pixels (no UI scaling).
static func _place_px(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, o_r: float, ob: float) -> void:
	c.anchor_left = al; c.anchor_top = at; c.anchor_right = ar; c.anchor_bottom = ab
	c.offset_left = ol; c.offset_top = ot; c.offset_right = o_r; c.offset_bottom = ob

## Computes safe area insets {left, top, right, bottom} in canvas coordinates.
## Supports automatic OS hardware detection (iOS Dynamic Island / Android cutout)
## and manual test override via safe_area_rect_override.
func get_safe_insets() -> Dictionary:
	var safe := safe_area_rect_override
	if safe.size.x <= 0 or safe.size.y <= 0:
		safe = DisplayServer.get_display_safe_area()
	var vr: Rect2 = get_viewport().get_visible_rect()
	var win_size: Vector2i = DisplayServer.window_get_size()
	if win_size.x <= 0 or win_size.y <= 0:
		var root_w := get_tree().root if is_inside_tree() else null
		if root_w:
			win_size = root_w.size
	if safe.size.x <= 0 or safe.size.y <= 0 or win_size.x <= 0 or win_size.y <= 0:
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if safe.position.x <= 0 and safe.position.y <= 0 and safe.size.x >= win_size.x and safe.size.y >= win_size.y:
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}

	var xf_inv: Transform2D = get_viewport().get_final_transform().affine_inverse()
	var canvas_tl: Vector2 = xf_inv * Vector2(safe.position)
	var canvas_br: Vector2 = xf_inv * Vector2(safe.end)

	var in_left: float = maxf(0.0, canvas_tl.x - vr.position.x)
	var in_top: float = maxf(0.0, canvas_tl.y - vr.position.y)
	var in_right: float = maxf(0.0, vr.end.x - canvas_br.x)
	var in_bottom: float = maxf(0.0, vr.end.y - canvas_br.y)

	var max_inset_x: float = vr.size.x * 0.25
	var max_inset_y: float = vr.size.y * 0.25
	return {
		"left": clampf(in_left, 0.0, max_inset_x),
		"top": clampf(in_top, 0.0, max_inset_y),
		"right": clampf(in_right, 0.0, max_inset_x),
		"bottom": clampf(in_bottom, 0.0, max_inset_y)
	}

var last_focus_sfx_msec: int = 0

func _on_button_focus() -> void:
	var now := Time.get_ticks_msec()
	if now - last_focus_sfx_msec < 60:
		return
	last_focus_sfx_msec = now
	sfx("focus", 1.0, -10.0)

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", Assets.FONT_HUD)
	b.add_theme_font_size_override("font_size", int(36 * UI))
	b.custom_minimum_size = Vector2(180, 72) * UI
	b.pressed.connect(func(): sfx("tap", 1.0, -8.0))
	b.focus_entered.connect(_on_button_focus)
	b.mouse_entered.connect(func():
		if current_input_device == "keyboard" and not b.has_focus():
			_on_button_focus()
	)
	return b

## StyleBoxTexture from art/ui (no baked text). margin = 9-slice margin in source px.
func _tex_style(name: String, margin := 0, content_l := -1.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = Art.UI[name]
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(maxf(8.0, margin * 0.5))
	if content_l >= 0.0:
		sb.content_margin_left = content_l
	return sb

## Text-less art button: normal / pressed / disabled textures; label stays a Godot label.
func _art_button(b: Button, prefix: String, margin := 0, content_l := -1.0, size := Vector2.ZERO) -> void:
	var n := _tex_style(prefix + "_normal" if Art.UI.has(prefix + "_normal") else prefix, margin, content_l)
	var pr := _tex_style(prefix + "_pressed" if Art.UI.has(prefix + "_pressed") else prefix, margin, content_l)
	var d := _tex_style(prefix + "_disabled" if Art.UI.has(prefix + "_disabled") else (prefix + "_normal" if Art.UI.has(prefix + "_normal") else prefix), margin, content_l)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color("a64a09")
	focus.set_border_width_all(6)
	focus.set_corner_radius_all(16)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("disabled", d)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, INK)
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.78))
	if size != Vector2.ZERO:
		b.custom_minimum_size = size

func _ink(l: Control) -> void:
	l.add_theme_color_override("font_color", INK)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08, 0.95))
	l.add_theme_constant_override("outline_size", 4)

func _panel_center(style := "panel_9slice") -> Array:
	var cc := CenterContainer.new()
	_place(cc, 0, 0, 1, 1, 0, 0, 0, 0)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(cc)
	var pc := PanelContainer.new()
	if style == "":
		pc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		var sb := _tex_style(style, 44)
		sb.set_content_margin_all(48)
		pc.add_theme_stylebox_override("panel", sb)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(vb)
	return [cc, vb]

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	timer_panel = NinePatchRect.new()
	timer_panel.texture = Art.UI.timer_panel
	timer_panel.patch_margin_left = 24; timer_panel.patch_margin_right = 24; timer_panel.patch_margin_top = 24; timer_panel.patch_margin_bottom = 24
	timer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(timer_panel)
	var ti := TextureRect.new()
	ti.texture = Art.UI.icon_timer
	ti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	timer_panel.add_child(ti); _place_px(ti, 0.05, 0.16, 0.20, 0.79, 0, 0, 0, 0)
	lbl_time = _label(34)
	lbl_time.reparent(timer_panel, false)
	_place_px(lbl_time, 0.22, 0.04, 0.97, 0.9, 0, 0, 0, 0)
	_ink(lbl_time)
	lbl_count = _label(40)
	lbl_count.add_theme_color_override("font_color", INK)
	lbl_count.add_theme_color_override("font_outline_color", Color("fff8eb"))
	lbl_count.add_theme_constant_override("outline_size", 10)
	hearts_box = Control.new()
	hearts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hearts_box)
	var frame := NinePatchRect.new()
	frame.texture = Art.UI.hp_frame
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hearts_box.add_child(frame); _place_px(frame, 0, 0, 1, 1, 0, 0, 0, 0)
	var heart := TextureRect.new()
	heart.texture = Art.UI.icon_heart
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hearts_box.add_child(heart); _place_px(heart, 0.05, 0.2, 0.17, 0.72, 0, 0, 0, 0)
	hp_chunk = NinePatchRect.new(); hp_chunk.texture = Art.UI.hp_lag
	hp_fill = NinePatchRect.new(); hp_fill.texture = Art.UI.hp_fill
	var fill_material := ShaderMaterial.new()
	fill_material.shader = preload("res://shaders/hp_fill.gdshader")
	hp_fill.material = fill_material
	for cr in [hp_chunk, hp_fill]:
		cr.patch_margin_left = 20; cr.patch_margin_right = 20
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hearts_box.add_child(cr)
		_place_px(cr, 0, 0.236, 0, 0.673, 0, 0, 0, 0)
	lbl_hp = Label.new()
	lbl_hp.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_hp.add_theme_font_size_override("font_size", int(24 * UI))
	lbl_hp.add_theme_color_override("font_outline_color", Color("071329"))
	lbl_hp.add_theme_constant_override("outline_size", 3)
	var hp_plate := StyleBoxFlat.new()
	hp_plate.bg_color = Color(0.025, 0.045, 0.1, 0.82)
	hp_plate.set_corner_radius_all(10)
	lbl_hp.add_theme_stylebox_override("normal", hp_plate)
	lbl_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hearts_box.add_child(lbl_hp); _place_px(lbl_hp, 0.42, 0.1, 0.94, 0.8, 0, 0, 0, 0)
	lbl_shield = Label.new()
	lbl_shield.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_shield.add_theme_font_size_override("font_size", int(22 * UI))
	lbl_shield.add_theme_color_override("font_color", Color(0.35, 0.6, 0.95))
	lbl_shield.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hearts_box.add_child(lbl_shield); _place_px(lbl_shield, 1, 0, 1, 1, 6, 0, 90, 0)
	shield_box = NinePatchRect.new()
	shield_box.texture = Art.UI.shield_counter_panel
	shield_box.patch_margin_left = 43; shield_box.patch_margin_right = 43
	shield_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(shield_box)
	lbl_boss = _label(32, HORIZONTAL_ALIGNMENT_CENTER)
	_ink(lbl_boss)
	lbl_boss.reparent(shield_box, false)
	_place_px(lbl_boss, 0.05, 0, 0.95, 0.88, 0, 0, 0, 0)
	shield_box.visible = false
	judge = TextureRect.new()
	judge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	judge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud.add_child(judge)
	judge.modulate.a = 0.0
	go_box = TextureRect.new()
	(go_box as TextureRect).texture = Art.UI.countdown_bg_go
	(go_box as TextureRect).expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	go_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(go_box)
	var gl := Label.new()
	gl.text = "GO!"
	gl.add_theme_font_override("font", Assets.FONT_HUD)
	gl.add_theme_color_override("font_outline_color", INK)
	gl.add_theme_constant_override("outline_size", 8)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	go_box.add_child(gl); _place_px(gl, 0, 0, 1, 1, 0, 0, 0, 0)
	go_box.modulate.a = 0.0
	lbl_speed = _label(28, HORIZONTAL_ALIGNMENT_CENTER); _place(lbl_speed, 0.5, 1, 0.5, 1, -115, -90, 115, -36)
	combo_badge = NinePatchRect.new()
	combo_badge.texture = Art.UI.combo_badge
	combo_badge.patch_margin_left = 40; combo_badge.patch_margin_right = 40
	combo_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(combo_badge)
	lbl_combo = _label(40, HORIZONTAL_ALIGNMENT_CENTER)
	_ink(lbl_combo)
	lbl_combo.reparent(combo_badge, false)
	_place_px(lbl_combo, 0, 0, 1, 0.88, 0, 0, 0, 0)
	speedo = Control.new()
	speedo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(speedo)
	var spn := TextureRect.new(); spn.texture = Art.UI.speedo_panel
	spn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speedo.add_child(spn); _place_px(spn, 0, 0, 1, 1, 0, 0, 0, 0)
	speedo_needle = TextureRect.new(); speedo_needle.texture = Art.UI.speedo_needle
	speedo_needle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	speedo_needle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speedo.add_child(speedo_needle)
	lbl_speed.reparent(speedo)
	_ink(lbl_speed)
	lbl_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint = _label(96, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_hint.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	lbl_float = _label(42)
	lbl_notice = _label(42, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_notice.add_theme_color_override("font_color", INK)
	lbl_notice.add_theme_color_override("font_outline_color", Color("fff8eb"))
	lbl_notice.add_theme_constant_override("outline_size", 9)
	var ready := _panel_center()
	ready_box = ready[0]
	_place_px(ready_box, 0, 0.04, 1, 0.56, 0, 0, 0, 0)
	ready_title = _label(40, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_center = _label(31, HORIZONTAL_ALIGNMENT_CENTER)
	ready_knowledge = _label(27, HORIZONTAL_ALIGNMENT_CENTER)
	for label in [ready_title, lbl_center, ready_knowledge]:
		label.reparent(ready[1], false)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_ink(label)
	ready_title.add_theme_color_override("font_color", Color(0.1, 0.95, 1.0))
	ready_knowledge.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	ready_box.hide()
	lbl_dev = _label(22, HORIZONTAL_ALIGNMENT_LEFT, Assets.FONT_UI); _place(lbl_dev, 1, 0, 1, 0, -340, 240, -10, 530)
	lbl_dev.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl_dev.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	# touch buttons (hit-tested by hand in _input so several fingers work at once)
	btn_brake = _touch_button("煞車", 40, "btn_brake"); _place(btn_brake, 0, 1, 0, 1, 24, -244, 224, -44)
	btn_accel = _touch_button("加速", 48, "btn_accel"); _place(btn_accel, 1, 1, 1, 1, -264, -284, -24, -44)
	btn_pause = _touch_button("", 40, "btn_pause"); _place(btn_pause, 1, 0, 1, 0, -120, 16, -24, 112)
	btn_voice = _touch_button("重播", 30, "btn_secondary", 32); _place(btn_voice, 1, 0, 1, 0, -120, 124, -24, 220)
	btn_lock = _touch_button("鎖定", 34, "btn_lock"); _place(btn_lock, 1, 1, 1, 1, -200, -430, -64, -294)
	# brake / accel labels sit in the lower 30 % (icon above); lock labels on the right half (x 80-150 of 160)
	for bt in [btn_brake, btn_accel]:
		_place_px(bt.get_child(0), 0, 0.6, 1, 0.94, 0, 0, 0, 0)
	_place_px(btn_lock.get_child(0), 0.48, 0.52, 0.96, 0.9, 0, 0, 0, 0)
	lbl_lock_kmh = Label.new()
	lbl_lock_kmh.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_lock_kmh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_lock_kmh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_lock_kmh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink(lbl_lock_kmh)
	btn_lock.add_child(lbl_lock_kmh); _place_px(lbl_lock_kmh, 0.48, 0.1, 0.96, 0.55, 0, 0, 0, 0)
	for bt in [btn_lock, btn_voice]:
		_ink(bt.get_child(0))
	lbl_badge_brake = _create_pad_badge(btn_brake, "B", "S", Color(1.0, 0.35, 0.45))
	_place_px(lbl_badge_brake, 0.72, 0.06, 0.98, 0.34, 0, 0, 0, 0)
	lbl_badge_accel = _create_pad_badge(btn_accel, "A", "W", Color(0.2, 1.0, 0.6))
	_place_px(lbl_badge_accel, 0.72, 0.06, 0.98, 0.34, 0, 0, 0, 0)
	lbl_badge_voice = _create_pad_badge(btn_voice, "Y", "E", Color(1.0, 0.9, 0.2))
	_place_px(lbl_badge_voice, 0.05, 0.08, 0.45, 0.45, 0, 0, 0, 0)
	lbl_badge_lock = _create_pad_badge(btn_lock, "X", "F", Color(0.3, 0.75, 1.0))
	_place_px(lbl_badge_lock, 0.05, 0.08, 0.45, 0.45, 0, 0, 0, 0)
	pad_bar = Label.new()
	pad_bar.name = "PadBar"
	pad_bar.add_theme_font_override("font", Assets.FONT_HUD)
	pad_bar.add_theme_font_size_override("font_size", 22)
	pad_bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pad_bar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pad_bar.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0, 0.95))
	pad_bar.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.06, 0.95))
	pad_bar.add_theme_constant_override("outline_size", 6)
	pad_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad_bar.visible = false
	hud.add_child(pad_bar)
	_place(pad_bar, 0, 1, 1, 1, 0, -38, 0, -4)
	_layout_touch()
	get_viewport().size_changed.connect(_layout_touch)
	# full-screen backgrounds for level select / results (batch04), shown in _update_hud
	sel_bg = TextureRect.new(); sel_bg.texture = Art.UI.select_bg
	res_bg = TextureRect.new(); res_bg.texture = Art.UI.result_bg
	for bg in [sel_bg, res_bg]:
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.visible = false
		hud.add_child(bg); _place_px(bg, 0, 0, 1, 1, 0, 0, 0, 0)
	# pause menu
	var pm := _panel_center()
	pause_box = pm[0]
	var pt := Label.new()
	lbl_pause_title = pt
	pt.text = "暫停"
	pt.add_theme_font_override("font", Assets.FONT_HUD)
	pt.add_theme_font_size_override("font_size", int(48 * UI))
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pt.add_theme_color_override("font_color", Color(0.1, 0.95, 1.0))
	pt.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08, 0.95))
	pt.add_theme_constant_override("outline_size", 6)
	pm[1].add_child(pt)
	btn_resume = _button("繼續"); btn_restart = _button("重來"); btn_quit = _button("回選關")
	btn_mode_pause = _button("")
	btn_mode_pause.visible = false
	pm[1].add_child(btn_mode_pause) # kept for automated tests / backward compatibility

	var mode_hbox := HBoxContainer.new()
	mode_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_hbox.add_theme_constant_override("separation", 12)
	mode_hbox.custom_minimum_size = Vector2(580, 84)

	btn_mode_pause_race = Button.new()
	btn_mode_pause_race.text = "賽車 (按住)"
	btn_mode_pause_race.add_theme_font_override("font", Assets.FONT_HUD)
	btn_mode_pause_race.add_theme_font_size_override("font_size", 30)
	btn_mode_pause_race.custom_minimum_size = Vector2(284, 84)

	btn_mode_pause_step = Button.new()
	btn_mode_pause_step.text = "點放 ±5"
	btn_mode_pause_step.add_theme_font_override("font", Assets.FONT_HUD)
	btn_mode_pause_step.add_theme_font_size_override("font_size", 30)
	btn_mode_pause_step.custom_minimum_size = Vector2(284, 84)
	for button in [btn_mode_pause_race, btn_mode_pause_step]:
		button.pressed.connect(func(): sfx("tap", 1.0, -8.0))
		button.focus_entered.connect(_on_button_focus)

	var pause_mode_choices := ButtonGroup.new()
	for b in [btn_mode_pause_race, btn_mode_pause_step]:
		b.toggle_mode = true
		b.button_group = pause_mode_choices
		mode_hbox.add_child(b)

	_art_button(btn_resume, "btn_continue", 0, 130, Vector2(580, 130))
	_art_button(btn_restart, "btn_restart", 0, 110, Vector2(580, 110))
	_art_button(btn_quit, "btn_stage_select", 0, 110, Vector2(580, 110))

	pm[1].add_child(mode_hbox)
	for b in [btn_quit, btn_restart, btn_resume]:   # continue at the bottom (thumb zone)
		b.add_theme_font_size_override("font_size", 42)
		pm[1].add_child(b)
	btn_resume.pressed.connect(resume)
	btn_restart.pressed.connect(func(): reset_run())
	btn_quit.pressed.connect(show_select)
	btn_mode_pause.pressed.connect(func(): set_speed_mode("step" if speed_mode == "race" else "race"))
	btn_mode_pause_race.pressed.connect(func():
		if speed_mode != "race": set_speed_mode("race"))
	btn_mode_pause_step.pressed.connect(func():
		if speed_mode != "step": set_speed_mode("step"))
	pause_box.visible = false
	# settings
	var st := _panel_center()
	settings_box = st[0]
	st[1].add_theme_constant_override("separation", 10)

	var pc_set := settings_box.get_child(0) as PanelContainer
	if pc_set != null:
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(0.04, 0.05, 0.11, 0.95)
		psb.border_width_left = 2; psb.border_width_top = 2; psb.border_width_right = 2; psb.border_width_bottom = 2
		psb.border_color = Color(0.2, 0.85, 1.0, 0.75)
		psb.set_corner_radius_all(14)
		psb.set_content_margin_all(18)
		pc_set.add_theme_stylebox_override("panel", psb)

	lbl_settings_mode = Label.new()
	lbl_settings_mode.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_settings_mode.add_theme_font_size_override("font_size", int(36 * UI))
	lbl_settings_mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(lbl_settings_mode)
	st[1].add_child(lbl_settings_mode)

	btn_mode_race = _button("賽車模式")
	btn_mode_step = _button("點放模式")
	btn_vol_bgm = _button("")
	btn_vol_sfx = _button("")
	btn_vol_voice = _button("")
	btn_settings_back = _button("返回確認")

	# Category 1: Control Mode Card
	var mode_card := PanelContainer.new()
	var m_sb := StyleBoxFlat.new()
	m_sb.bg_color = Color(0.06, 0.08, 0.16, 0.85)
	m_sb.border_width_left = 2; m_sb.border_width_top = 2; m_sb.border_width_right = 2; m_sb.border_width_bottom = 2
	m_sb.border_color = Color(0.2, 0.75, 1.0, 0.45)
	m_sb.set_corner_radius_all(10)
	m_sb.set_content_margin_all(10)
	mode_card.add_theme_stylebox_override("panel", m_sb)
	st[1].add_child(mode_card)

	var mode_vb := VBoxContainer.new()
	mode_vb.add_theme_constant_override("separation", 6)
	mode_card.add_child(mode_vb)

	var lbl_mode_head := Label.new()
	lbl_mode_head.text = "【 操控方案 CONTROL MODE 】"
	lbl_mode_head.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_mode_head.add_theme_font_size_override("font_size", int(14 * UI))
	lbl_mode_head.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	mode_vb.add_child(lbl_mode_head)

	var mode_choices := ButtonGroup.new()
	for b in [btn_mode_race, btn_mode_step]:
		b.custom_minimum_size = Vector2(560, 72) * UI
		b.add_theme_font_size_override("font_size", int(24 * UI))
		b.toggle_mode = true
		b.button_group = mode_choices
		_art_button(b, "btn_primary", 32)
		mode_vb.add_child(b)

	# Category 2: Audio Volume Card
	var vol_card := PanelContainer.new()
	var v_sb := StyleBoxFlat.new()
	v_sb.bg_color = Color(0.06, 0.08, 0.16, 0.85)
	v_sb.border_width_left = 2; v_sb.border_width_top = 2; v_sb.border_width_right = 2; v_sb.border_width_bottom = 2
	v_sb.border_color = Color(0.3, 0.9, 0.6, 0.45)
	v_sb.set_corner_radius_all(10)
	v_sb.set_content_margin_all(10)
	vol_card.add_theme_stylebox_override("panel", v_sb)
	st[1].add_child(vol_card)

	var vol_vb := VBoxContainer.new()
	vol_vb.add_theme_constant_override("separation", 6)
	vol_card.add_child(vol_vb)

	var lbl_vol_head := Label.new()
	lbl_vol_head.text = "【 音訊音量 AUDIO VOLUME 】"
	lbl_vol_head.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_vol_head.add_theme_font_size_override("font_size", int(14 * UI))
	lbl_vol_head.add_theme_color_override("font_color", Color(0.3, 0.95, 0.6))
	vol_vb.add_child(lbl_vol_head)

	var vol_hbox := HBoxContainer.new()
	vol_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vol_hbox.add_theme_constant_override("separation", 8)
	vol_vb.add_child(vol_hbox)
	for b in [btn_vol_bgm, btn_vol_sfx, btn_vol_voice]:
		b.custom_minimum_size = Vector2(180, 72) * UI
		b.add_theme_font_size_override("font_size", int(20 * UI))
		_art_button(b, "btn_secondary", 32)
		vol_hbox.add_child(b)

	# Category 3: System Preferences Card
	var opt_card := PanelContainer.new()
	var o_sb := StyleBoxFlat.new()
	o_sb.bg_color = Color(0.06, 0.08, 0.16, 0.85)
	o_sb.border_width_left = 2; o_sb.border_width_top = 2; o_sb.border_width_right = 2; o_sb.border_width_bottom = 2
	o_sb.border_color = Color(0.85, 0.45, 1.0, 0.45)
	o_sb.set_corner_radius_all(10)
	o_sb.set_content_margin_all(10)
	opt_card.add_theme_stylebox_override("panel", o_sb)
	st[1].add_child(opt_card)

	var opt_vb := VBoxContainer.new()
	opt_vb.add_theme_constant_override("separation", 6)
	opt_card.add_child(opt_vb)

	var lbl_opt_head := Label.new()
	lbl_opt_head.text = "【 系統偏好 PREFERENCES 】"
	lbl_opt_head.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_opt_head.add_theme_font_size_override("font_size", int(14 * UI))
	lbl_opt_head.add_theme_color_override("font_color", Color(0.85, 0.5, 1.0))
	opt_vb.add_child(lbl_opt_head)

	var opt_hbox := HBoxContainer.new()
	opt_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	opt_hbox.add_theme_constant_override("separation", 8)
	opt_vb.add_child(opt_hbox)

	btn_lang = _button("語言")
	btn_lang.custom_minimum_size = Vector2(180, 72) * UI
	btn_lang.add_theme_font_size_override("font_size", int(20 * UI))
	_art_button(btn_lang, "btn_secondary", 32)
	opt_hbox.add_child(btn_lang)

	btn_vibration = _button("震動")
	btn_vibration.custom_minimum_size = Vector2(180, 72) * UI
	btn_vibration.add_theme_font_size_override("font_size", int(20 * UI))
	_art_button(btn_vibration, "btn_secondary", 32)
	opt_hbox.add_child(btn_vibration)

	btn_hit_pitch = _button("")
	btn_hit_pitch.custom_minimum_size = Vector2(180, 72) * UI
	btn_hit_pitch.add_theme_font_size_override("font_size", int(20 * UI))
	_art_button(btn_hit_pitch, "btn_secondary", 32)
	opt_hbox.add_child(btn_hit_pitch)

	btn_settings_back.custom_minimum_size = Vector2(560, 76) * UI
	btn_settings_back.add_theme_font_size_override("font_size", int(26 * UI))
	_art_button(btn_settings_back, "btn_secondary", 32)
	st[1].add_child(btn_settings_back)

	btn_mode_race.pressed.connect(func(): set_speed_mode("race"))
	btn_mode_step.pressed.connect(func(): set_speed_mode("step"))
	btn_vol_bgm.pressed.connect(func(): _cycle_vol("vol_bgm", 0.8))
	btn_vol_sfx.pressed.connect(func(): _cycle_vol("vol_sfx", 1.0))
	btn_vol_voice.pressed.connect(func(): _cycle_vol("vol_voice", 1.0))
	btn_lang.pressed.connect(func():
		var next_loc := I18n.cycle_locale()
		set_language(next_loc, true)
	)
	btn_vibration.pressed.connect(func():
		vibration_enabled = not vibration_enabled
		save.set_setting("vibration", vibration_enabled)
		_persist_progress()
		_update_vibration_button()
		if vibration_enabled:
			rumble(0.4, 0.4, 0.15)
	)
	btn_hit_pitch.pressed.connect(func():
		var modes := ["pentatonic", "random", "fixed"]
		var cur := str(save.get_setting("hit_pitch_mode", "pentatonic"))
		var next_idx := (modes.find(cur) + 1) % modes.size()
		var next_mode: String = modes[next_idx]
		save.set_setting("hit_pitch_mode", next_mode)
		_persist_progress()
		_update_hit_pitch_button()
		if next_mode == "pentatonic":
			sfx("shatter", 1.25992, 2.0)
			sfx("focus", 1.25, -2.0)
		elif next_mode == "random":
			sfx("shatter", 1.05, 2.0)
		else:
			sfx("shatter", 1.0, 2.0)
	)
	btn_settings_back.pressed.connect(hide_settings)
	_update_vol_buttons()
	_update_vibration_button()
	_update_hit_pitch_button()
	_wire_settings_focus()
	settings_box.visible = false
	_build_results()
	# level select
	var sp := _panel_center("")
	select_box = sp[0]
	select_list = sp[1]
	select_box.visible = false
	get_viewport().size_changed.connect(_layout_select_scroll)
	_build_shop()
	_build_achievements()
	_build_endless()
	_build_chart()
	_build_achievement_toast()
	_build_title()
	_build_transitions()
	_layout_menus()
	get_viewport().size_changed.connect(_layout_menus)

func _layout_menus() -> void:
	var view := get_viewport().get_visible_rect().size
	var short_side := minf(view.x, view.y)
	var height := short_side * 0.115
	lbl_pause_title.add_theme_font_size_override("font_size", roundi(short_side * 0.075))
	for button in [btn_resume, btn_restart, btn_quit]:
		button.custom_minimum_size = Vector2(short_side * 0.7, height)
		button.add_theme_font_size_override("font_size", roundi(short_side * 0.045))
	btn_resume.custom_minimum_size.y = short_side * 0.14
	for button in [btn_mode_pause_race, btn_mode_pause_step]:
		button.custom_minimum_size = Vector2(short_side * 0.34, height)
		button.add_theme_font_size_override("font_size", roundi(short_side * 0.042))
	lbl_settings_mode.add_theme_font_size_override("font_size", roundi(short_side * 0.06))
	for button in [btn_mode_race, btn_mode_step, btn_settings_back]:
		button.custom_minimum_size = Vector2(short_side * 0.88, height)
		button.add_theme_font_size_override("font_size", roundi(short_side * 0.042))
	var opt_w := (short_side * 0.88 - 16.0) / 3.0
	for button in [btn_lang, btn_vibration, btn_hit_pitch]:
		if button != null and is_instance_valid(button):
			button.custom_minimum_size = Vector2(opt_w, height)
			button.add_theme_font_size_override("font_size", roundi(short_side * 0.026))
	for button in [btn_vol_bgm, btn_vol_sfx, btn_vol_voice]:
		button.custom_minimum_size = Vector2(short_side * 0.28, height)
		button.add_theme_font_size_override("font_size", roundi(short_side * 0.034))
	if title_box != null and is_instance_valid(title_box) and title_box.get_child_count() > 0:
		var tb_panel := title_box.get_child(0) as PanelContainer
		if tb_panel != null:
			tb_panel.custom_minimum_size = Vector2(minf(560.0 * UI, short_side * 0.9), 0)
		if lbl_title_name != null:
			lbl_title_name.add_theme_font_size_override("font_size", roundi(short_side * 0.075))
		if lbl_title_sub != null:
			lbl_title_sub.add_theme_font_size_override("font_size", roundi(short_side * 0.035))
		if lbl_title_press != null:
			lbl_title_press.add_theme_font_size_override("font_size", roundi(short_side * 0.032))
		if btn_title_start != null:
			btn_title_start.custom_minimum_size = Vector2(short_side * 0.8, height)
			btn_title_start.add_theme_font_size_override("font_size", roundi(short_side * 0.045))
		var sub_w := (short_side * 0.8 - 10.0) * 0.5
		if btn_title_settings != null:
			btn_title_settings.custom_minimum_size = Vector2(sub_w, height * 0.9)
			btn_title_settings.add_theme_font_size_override("font_size", roundi(short_side * 0.038))
		if btn_title_quit != null:
			btn_title_quit.custom_minimum_size = Vector2(sub_w, height * 0.9)
			btn_title_quit.add_theme_font_size_override("font_size", roundi(short_side * 0.038))

func _result_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", Assets.FONT_HUD)
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ink(label)
	return label

func _make_cyber_stat_card(title_text: String, icon_accent: Color) -> Array:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.12, 0.92)
	sb.border_width_left = 3
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = icon_accent * 0.85
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	pc.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	pc.add_child(vb)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_override("font", Assets.FONT_HUD)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", icon_accent)
	vb.add_child(title)

	var val := Label.new()
	val.add_theme_font_override("font", Assets.FONT_HUD)
	val.add_theme_font_size_override("font_size", 24)
	val.add_theme_color_override("font_color", Color(1.0, 0.98, 0.95))
	vb.add_child(val)

	var sub := Label.new()
	sub.add_theme_font_override("font", Assets.FONT_HUD)
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.72, 0.80, 0.90))
	vb.add_child(sub)

	return [pc, val, sub]

func _build_results() -> void:
	var r := _panel_center()
	results_box = r[0]
	var res_root: VBoxContainer = r[1]
	res_root.add_theme_constant_override("separation", 10)

	var pc_main := results_box.get_child(0) as PanelContainer
	if pc_main != null:
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(0.04, 0.05, 0.11, 0.95)
		psb.border_width_left = 2; psb.border_width_top = 2; psb.border_width_right = 2; psb.border_width_bottom = 2
		psb.border_color = Color(0.2, 0.85, 1.0, 0.75)
		psb.set_corner_radius_all(14)
		psb.set_content_margin_all(20)
		pc_main.add_theme_stylebox_override("panel", psb)

	# Split container: HBox in landscape (side-by-side decks), VBox in portrait (stacked)
	res_split_box = BoxContainer.new()
	res_split_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_split_box.add_theme_constant_override("separation", 20)
	res_root.add_child(res_split_box)

	# Left Hero Deck: Stage, Heading, Giant Rank Emblem, Stars, Record badge
	res_left_deck = VBoxContainer.new()
	res_left_deck.alignment = BoxContainer.ALIGNMENT_CENTER
	res_left_deck.add_theme_constant_override("separation", 12)
	res_split_box.add_child(res_left_deck)

	res_chip_stage = Label.new()
	res_chip_stage.add_theme_font_override("font", Assets.FONT_HUD)
	res_chip_stage.add_theme_font_size_override("font_size", 16)
	res_chip_stage.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	var chip_sb := StyleBoxFlat.new()
	chip_sb.bg_color = Color(0.08, 0.12, 0.22, 0.85)
	chip_sb.border_width_left = 1; chip_sb.border_width_top = 1; chip_sb.border_width_right = 1; chip_sb.border_width_bottom = 1
	chip_sb.border_color = Color(0.2, 0.85, 1.0, 0.6)
	chip_sb.set_corner_radius_all(8)
	chip_sb.set_content_margin_all(6)
	res_chip_stage.add_theme_stylebox_override("normal", chip_sb)
	res_chip_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_left_deck.add_child(res_chip_stage)

	lbl_result_heading = Label.new()
	lbl_result_heading.text = ""
	lbl_result_heading.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_result_heading.add_theme_font_size_override("font_size", 44)
	lbl_result_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_result_heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_result_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	_ink(lbl_result_heading)
	res_left_deck.add_child(lbl_result_heading)

	rank_box = PanelContainer.new()
	var rank_style := StyleBoxFlat.new()
	rank_style.bg_color = Color(0.05, 0.06, 0.14, 0.95)
	rank_style.border_width_left = 2; rank_style.border_width_top = 2; rank_style.border_width_right = 2; rank_style.border_width_bottom = 2
	rank_style.border_color = Color(0.18, 0.88, 1.0)
	rank_style.set_corner_radius_all(14)
	rank_style.set_content_margin_all(8)
	rank_box.add_theme_stylebox_override("panel", rank_style)
	rank_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rank_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var rk_vb := VBoxContainer.new()
	rk_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	rk_vb.add_theme_constant_override("separation", 2)
	rank_box.add_child(rk_vb)

	var lbl_rk_title := Label.new()
	lbl_rk_title.text = "◆ 評級 GRADE ◆"
	lbl_rk_title.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_rk_title.add_theme_font_size_override("font_size", 13)
	lbl_rk_title.add_theme_color_override("font_color", Color(0.5, 0.82, 1.0))
	lbl_rk_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rk_vb.add_child(lbl_rk_title)

	lbl_rank = Label.new()
	lbl_rank.text = "S"
	lbl_rank.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_rank.add_theme_font_size_override("font_size", 54)
	lbl_rank.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08, 0.95))
	lbl_rank.add_theme_constant_override("outline_size", 8)
	lbl_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rk_vb.add_child(lbl_rank)

	res_left_deck.add_child(rank_box)

	res_stars = HBoxContainer.new()
	res_stars.alignment = BoxContainer.ALIGNMENT_CENTER
	res_stars.add_theme_constant_override("separation", 8)
	res_left_deck.add_child(res_stars)
	for i in 3:
		var stx := TextureRect.new()
		stx.texture = Art.UI.star_empty_200
		stx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stx.custom_minimum_size = Vector2(48, 48)
		res_stars.add_child(stx)

	res_badge = TextureRect.new()
	res_badge.texture = Art.UI.badge_new_record
	res_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	res_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	res_badge.custom_minimum_size = Vector2(130, 44)
	res_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	res_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var nl := Label.new(); nl.text = "新紀錄"
	nl.add_theme_font_override("font", Assets.FONT_HUD); nl.add_theme_font_size_override("font_size", 18)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ink(nl)
	res_badge.add_child(nl); _place_px(nl, 0, 0, 1, 0.95, 0, 0, 0, 0)
	res_left_deck.add_child(res_badge)

	# Right Telemetry Deck: 4 Stat Cards, Weak Kana, Knowledge, Action Buttons
	res_right_deck = VBoxContainer.new()
	res_right_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_right_deck.add_theme_constant_override("separation", 10)
	res_split_box.add_child(res_right_deck)

	res_cards_grid = GridContainer.new()
	res_cards_grid.columns = 2
	res_cards_grid.add_theme_constant_override("h_separation", 10)
	res_cards_grid.add_theme_constant_override("v_separation", 8)
	res_cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_right_deck.add_child(res_cards_grid)

	var c_time := _make_cyber_stat_card("◎ 結算用時", Color(0.2, 0.85, 1.0))
	res_card_time = c_time[0]; lbl_card_time_val = c_time[1]; lbl_card_time_sub = c_time[2]
	res_cards_grid.add_child(res_card_time)

	var c_acc := _make_cyber_stat_card("★ 命中答對", Color(0.3, 0.95, 0.6))
	res_card_acc = c_acc[0]; lbl_card_acc_val = c_acc[1]; lbl_card_acc_sub = c_acc[2]
	res_cards_grid.add_child(res_card_acc)

	var c_combo := _make_cyber_stat_card("▲ 疾走表現", Color(1.0, 0.75, 0.2))
	res_card_combo = c_combo[0]; lbl_card_combo_val = c_combo[1]; lbl_card_combo_sub = c_combo[2]
	res_cards_grid.add_child(res_card_combo)

	var c_pts := _make_cyber_stat_card("◆ 獲得點數", Color(0.85, 0.45, 1.0))
	res_card_pts = c_pts[0]; lbl_card_pts_val = c_pts[1]; lbl_card_pts_sub = c_pts[2]
	res_cards_grid.add_child(res_card_pts)

	res_weak_box = PanelContainer.new()
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(0.08, 0.05, 0.10, 0.85)
	wsb.border_width_left = 1; wsb.border_width_top = 1; wsb.border_width_right = 1; wsb.border_width_bottom = 1
	wsb.border_color = Color(1.0, 0.4, 0.3, 0.6)
	wsb.set_corner_radius_all(8)
	wsb.set_content_margin_all(8)
	res_weak_box.add_theme_stylebox_override("panel", wsb)
	res_weak_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_right_deck.add_child(res_weak_box)

	var weak_vb := HBoxContainer.new()
	weak_vb.alignment = BoxContainer.ALIGNMENT_BEGIN
	weak_vb.add_theme_constant_override("separation", 10)
	res_weak_box.add_child(weak_vb)

	var lbl_weak_title := Label.new()
	lbl_weak_title.text = "▲ 待強化假名："
	lbl_weak_title.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_weak_title.add_theme_font_size_override("font_size", 14)
	lbl_weak_title.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	lbl_weak_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weak_vb.add_child(lbl_weak_title)

	res_weak_tiles = HFlowContainer.new()
	res_weak_tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_weak_tiles.add_theme_constant_override("h_separation", 8)
	res_weak_tiles.add_theme_constant_override("v_separation", 6)
	weak_vb.add_child(res_weak_tiles)

	res_knowledge_box = PanelContainer.new()
	var knsb := StyleBoxFlat.new()
	knsb.bg_color = Color(0.05, 0.08, 0.16, 0.85)
	knsb.border_width_left = 1; knsb.border_width_top = 1; knsb.border_width_right = 1; knsb.border_width_bottom = 1
	knsb.border_color = Color(0.2, 0.7, 0.9, 0.4)
	knsb.set_corner_radius_all(8)
	knsb.set_content_margin_all(8)
	res_knowledge_box.add_theme_stylebox_override("panel", knsb)
	res_knowledge_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_right_deck.add_child(res_knowledge_box)

	lbl_res_knowledge = Label.new()
	lbl_res_knowledge.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_res_knowledge.add_theme_font_size_override("font_size", 13)
	lbl_res_knowledge.add_theme_color_override("font_color", Color(0.8, 0.92, 1.0))
	lbl_res_knowledge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	res_knowledge_box.add_child(lbl_res_knowledge)

	result_actions = GridContainer.new()
	result_actions.columns = 4
	result_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_actions.add_theme_constant_override("h_separation", 10)
	result_actions.add_theme_constant_override("v_separation", 8)
	res_right_deck.add_child(result_actions)

	btn_next = _button(I18n.t("BTN_NEXT", "下一關"))
	btn_review = _button(I18n.t("BTN_REVIEW", "錯題練習"))
	btn_retry = _button(I18n.t("BTN_RETRY", "重玩"))
	btn_select = _button(I18n.t("BTN_SELECT", "回選關"))
	btn_save_retry = _button(I18n.t("BTN_SAVE_RETRY", "重試存檔"))
	btn_kata_next = _button(I18n.t("BTN_START_KATA", "開始片假名"))
	_art_button(btn_save_retry, "btn_small", 32)
	_art_button(btn_kata_next, "btn_next")
	btn_save_retry.visible = false
	btn_kata_next.visible = false
	_art_button(btn_next, "btn_next")
	_art_button(btn_review, "btn_primary", 32)
	_art_button(btn_retry, "btn_retry")
	_art_button(btn_select, "btn_secondary", 32)
	for button in [btn_next, btn_review, btn_retry, btn_select, btn_save_retry, btn_kata_next]:
		result_actions.add_child(button)

	# Keep result_body & lbl_result present for compatibility & tests
	result_body = BoxContainer.new()
	res_root.add_child(result_body)
	lbl_result = _result_label("", 14)
	lbl_result.visible = false
	result_body.add_child(lbl_result)

	# Connections
	btn_retry.pressed.connect(func():
		fade_transition(func():
			if is_drill:
				start_custom_drill()
			else:
				reset_run()
		, 0.18, 0.18)
	)
	btn_next.pressed.connect(func(): fade_transition(func(): go_next_level(), 0.18, 0.18))
	btn_review.pressed.connect(_open_review)
	btn_select.pressed.connect(func():
		fade_transition(func():
			if is_drill:
				is_drill = false
				show_chart("drill")
			else:
				show_select()
		, 0.2, 0.2)
	)
	btn_save_retry.pressed.connect(_retry_save)
	btn_kata_next.pressed.connect(_start_katakana)
	results_box.visible = false
	_build_review()
	_layout_result_cards()
	get_viewport().size_changed.connect(_layout_result_cards)

func _build_review() -> void:
	var panel := _panel_center()
	review_box = panel[0]
	var content: VBoxContainer = panel[1]
	lbl_review_heading = _result_label(I18n.t("BTN_REVIEW", "錯題練習"), 68)
	content.add_child(lbl_review_heading)
	lbl_review_progress = _result_label("", 46)
	content.add_child(lbl_review_progress)
	btn_review_replay = _button(I18n.t("REVIEW_REPLAY", "重播語音"))
	_art_button(btn_review_replay, "btn_small", 32)
	btn_review_replay.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_review_replay.pressed.connect(_replay_review)
	content.add_child(btn_review_replay)
	var choices := HBoxContainer.new()
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	choices.add_theme_constant_override("separation", 16)
	content.add_child(choices)
	for i in lane_count:
		var button := _button("")
		_art_button(button, "btn_small", 32)
		button.add_theme_font_override("font", Art.FONT_KANA)
		button.add_theme_font_size_override("font_size", 78)
		button.pressed.connect(_answer_review.bind(button))
		choices.add_child(button)
		review_choices.append(button)
	lbl_review_feedback = _result_label("", 46)
	content.add_child(lbl_review_feedback)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	content.add_child(actions)
	btn_review_back = _button(I18n.t("REVIEW_BACK", "返回結算"))
	btn_review_next = _button(I18n.t("REVIEW_NEXT", "下一字"))
	for button in [btn_review_back, btn_review_next]:
		_art_button(button, "btn_small", 32)
		actions.add_child(button)
	btn_review_back.pressed.connect(_close_review)
	btn_review_next.pressed.connect(_advance_review)
	review_box.visible = false

func _layout_result_cards() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var landscape := viewport_size.x >= viewport_size.y
	var insets: Dictionary = get_safe_insets()
	var touch_height := 56.0 if landscape else 50.0
	var available_w: float = viewport_size.x - 48.0 - float(insets.left) - float(insets.right)
	var panel_w: float = clampf(available_w * 0.72, 920.0, 1680.0) if landscape else minf(available_w, 720.0)

	if is_instance_valid(results_box) and results_box.get_child_count() > 0:
		var pc := results_box.get_child(0) as Control
		if pc != null:
			pc.custom_minimum_size.x = panel_w

	if is_instance_valid(res_split_box):
		res_split_box.vertical = not landscape
		res_split_box.add_theme_constant_override("separation", 24 if landscape else 10)

	if landscape:
		var left_w := panel_w * 0.35
		var right_w := panel_w * 0.65 - 24.0
		if is_instance_valid(res_left_deck):
			res_left_deck.custom_minimum_size = Vector2(left_w, 0)
		if is_instance_valid(res_right_deck):
			res_right_deck.custom_minimum_size = Vector2(right_w, 0)
		if is_instance_valid(lbl_result_heading):
			lbl_result_heading.add_theme_font_size_override("font_size", 42)
		if is_instance_valid(rank_box):
			rank_box.custom_minimum_size = Vector2(160, 120)
			rank_box.pivot_offset = rank_box.custom_minimum_size * 0.5
		if is_instance_valid(lbl_rank):
			lbl_rank.add_theme_font_size_override("font_size", 54)
		if is_instance_valid(res_badge):
			res_badge.custom_minimum_size = Vector2(140, 48)
			if res_badge.get_child_count() > 0:
				(res_badge.get_child(0) as Label).add_theme_font_size_override("font_size", 20)
		if is_instance_valid(res_stars):
			for st in res_stars.get_children():
				if st is TextureRect:
					st.custom_minimum_size = Vector2(52, 52)
		if is_instance_valid(res_cards_grid):
			res_cards_grid.columns = 2
			var card_w := (right_w - 14.0) * 0.5
			var card_h := 88.0
			for card in [res_card_time, res_card_acc, res_card_combo, res_card_pts]:
				if card != null and is_instance_valid(card):
					card.custom_minimum_size = Vector2(card_w, card_h)
		if is_instance_valid(result_actions):
			var action_count := result_actions.get_children().filter(func(b): return b.visible).size()
			result_actions.columns = action_count if action_count <= 4 else 2
			var btn_w := (right_w - float(result_actions.columns - 1) * 10.0) / float(maxi(1, result_actions.columns))
			for button in [btn_retry, btn_next, btn_review, btn_select, btn_save_retry, btn_kata_next]:
				if button != null and is_instance_valid(button):
					button.custom_minimum_size = Vector2(btn_w, touch_height)
					button.add_theme_font_size_override("font_size", 20)
	else:
		if is_instance_valid(res_left_deck):
			res_left_deck.custom_minimum_size = Vector2.ZERO
		if is_instance_valid(res_right_deck):
			res_right_deck.custom_minimum_size = Vector2.ZERO
		if is_instance_valid(lbl_result_heading):
			lbl_result_heading.add_theme_font_size_override("font_size", 36)
		if is_instance_valid(rank_box):
			rank_box.custom_minimum_size = Vector2(100, 48)
			rank_box.pivot_offset = rank_box.custom_minimum_size * 0.5
		if is_instance_valid(lbl_rank):
			lbl_rank.add_theme_font_size_override("font_size", 30)
		if is_instance_valid(res_badge):
			res_badge.custom_minimum_size = Vector2(100, 38)
			if res_badge.get_child_count() > 0:
				(res_badge.get_child(0) as Label).add_theme_font_size_override("font_size", 16)
		if is_instance_valid(res_stars):
			for st in res_stars.get_children():
				if st is TextureRect:
					st.custom_minimum_size = Vector2(40, 40)
		if is_instance_valid(res_cards_grid):
			res_cards_grid.columns = 2
			var card_w := (panel_w - 40.0) * 0.5
			var card_h := 76.0
			for card in [res_card_time, res_card_acc, res_card_combo, res_card_pts]:
				if card != null and is_instance_valid(card):
					card.custom_minimum_size = Vector2(card_w, card_h)
		if is_instance_valid(result_actions):
			result_actions.columns = 2
			var btn_w := (panel_w - 40.0 - 10.0) * 0.5
			for button in [btn_retry, btn_next, btn_review, btn_select, btn_save_retry, btn_kata_next]:
				if button != null and is_instance_valid(button):
					button.custom_minimum_size = Vector2(btn_w, touch_height)
					button.add_theme_font_size_override("font_size", 18)

	for button in [btn_review_back, btn_review_next, btn_review_replay]:
		if button != null and is_instance_valid(button):
			button.custom_minimum_size = Vector2(260.0 if landscape else 200.0, touch_height)
			button.add_theme_font_size_override("font_size", 22 if landscape else 18)
	var choice_width := minf(220.0 if landscape else 180.0, panel_w / lane_count - 16.0)
	for button in review_choices:
		if button != null and is_instance_valid(button):
			button.custom_minimum_size = Vector2(choice_width, touch_height)
			button.add_theme_font_size_override("font_size", 56 if landscape else 42)
	if is_instance_valid(lbl_review_heading):
		lbl_review_heading.add_theme_font_size_override("font_size", 42 if landscape else 32)
	for label in [lbl_review_progress, lbl_review_feedback]:
		if label != null and is_instance_valid(label):
			label.add_theme_font_size_override("font_size", 22 if landscape else 18)
	if is_instance_valid(lbl_review_feedback):
		lbl_review_feedback.custom_minimum_size = Vector2(minf(800.0 if landscape else 550.0, viewport_size.x - 48.0), 80.0 if landscape else 60.0)
		lbl_review_feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _touch_button(text: String, size: int, art: String, margin := 0) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_meta("art", art)
	p.set_meta("margin", margin)
	p.add_theme_stylebox_override("panel", _tex_style(art + ("_off" if art == "btn_lock" else "_normal"), margin))
	hud.add_child(p)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Assets.FONT_HUD)
	l.add_theme_font_size_override("font_size", int(size * UI))
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08, 0.95))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(l, 0, 0, 1, 1, 0, 0, 0, 0)
	p.add_child(l)
	return p

func _create_pad_badge(parent: Control, pad_text: String, kb_text: String, col: Color) -> Label:
	var b := Label.new()
	b.name = "PadBadge"
	b.text = pad_text if current_input_device == "joypad" else kb_text
	b.add_theme_font_override("font", Assets.FONT_HUD)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08, 0.95))
	b.add_theme_constant_override("outline_size", 6)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.set_meta("pad_text", pad_text)
	b.set_meta("kb_text", kb_text)
	parent.add_child(b)
	return b

## Pressed art while held (lock: on / off). No modulate glow.
func _set_btn_lit(p: Panel, lit: bool) -> void:
	var art: String = p.get_meta("art")
	var key := (art + ("_on" if lit else "_off")) if art == "btn_lock" else (art + ("_pressed" if lit else "_normal"))
	if p.get_meta("key", "") != key:
		p.set_meta("key", key)
		p.add_theme_stylebox_override("panel", _tex_style(key, int(p.get_meta("margin"))))
	p.scale = Vector2.ONE

# ---------------------------------------------------------------- HP
## Upgrade hook: extra max HP (value). refill = also fill to the new max.
func set_max_hp_bonus(bonus: int, refill := true) -> void:
	max_hp_bonus = maxi(0, bonus)
	set_max_hp(base_max_hp + max_hp_bonus, refill)

func set_max_hp(n: int, refill := false) -> void:
	max_hp = maxi(1, n)
	hp = max_hp if refill else mini(hp, max_hp)
	hp_delayed = minf(hp_delayed, float(max_hp)) if not refill else float(hp)
	_emit_hp()

## Upgrade hook: percent of every hit that is ignored (clamped 0..90).
func set_damage_reduction(pct: float) -> void:
	damage_reduction = clampf(pct, 0.0, 90.0)

## Charm hook: each shield point blocks one whole future hit.
func add_shield(n := 1) -> void:
	shield = maxi(0, shield + n)
	_emit_hp()

## Heal hook (value), capped at max_hp.
func heal(n := 10) -> void:
	hp = mini(max_hp, hp + maxi(0, n))
	hp_delayed = maxf(hp_delayed, float(hp))
	_emit_hp()

## Damage after reduction (rounded, at least 1 if raw > 0).
func damage_after_reduction(n: int) -> int:
	if n <= 0:
		return 0
	return maxi(1, int(round(n * (1.0 - damage_reduction / 100.0))))

## Applies damage. Returns true if HP was actually lost. Ends the run at 0.
func take_damage(n := 35) -> bool:
	if n <= 0:
		return false
	if shield > 0:
		shield -= 1
		damaged.emit(0, true)
		_emit_hp()
		_hearts_fx(Color(0.6, 0.85, 1.0))
		return false
	var d := damage_after_reduction(n)
	hp = maxi(0, hp - d)
	hp_delay_wait = bar_wait_s
	damaged.emit(d, false)
	_emit_hp()
	_hearts_fx(Color(1.0, 0.25, 0.25))
	if hp <= 0 and state == State.RUNNING:
		_finish(false, "hp_out")
	return true

func _emit_hp() -> void:
	_refresh_hp_bar()
	hp_changed.emit(hp, max_hp, shield)

func _refresh_hp_bar() -> void:
	if hearts_box == null:
		return
	var W := hearts_box.size.x if hearts_box.size.x > 0.0 else 450.0
	var x0 := W * 101.0 / 500.0; var tw := W * 374.0 / 500.0      # inner track of hp_frame
	hp_fill.offset_left = x0; hp_chunk.offset_left = x0
	hp_fill.offset_right = x0 + maxf(1.0, tw * float(hp) / float(max_hp))
	hp_chunk.offset_right = x0 + maxf(1.0, tw * clampf(hp_delayed, 0.0, float(max_hp)) / float(max_hp))
	hp_fill.visible = hp > 0
	lbl_hp.text = "%d / %d" % [hp, max_hp]
	var ratio := float(hp) / float(max_hp)
	var warning_tint := Color.TRANSPARENT
	if ratio <= 0.25:
		warning_tint = Color("ff526c")
	elif ratio <= 0.5:
		warning_tint = Color("ffca63")
	(hp_fill.material as ShaderMaterial).set_shader_parameter("warning_tint", warning_tint)
	lbl_shield.text = ("盾%d" % shield) if shield > 0 else ""

## Flash + shake of the HP widget only (never the camera / screen).
func _hearts_fx(col: Color) -> void:
	if hearts_box == null:
		return
	if hp_flash_tween != null:
		hp_flash_tween.kill()
	if hp_shake_tween != null:
		hp_shake_tween.kill()
	_set_hp_shake(0.0)
	hearts_box.modulate = col * 1.6
	hp_flash_tween = create_tween()
	hp_flash_tween.tween_property(hearts_box, "modulate", Color.WHITE, 0.4)
	hp_shake_tween = create_tween()
	var previous := 0.0
	for d in [10.0, -8.0, 6.0, -4.0, 0.0]:
		hp_shake_tween.tween_method(_set_hp_shake, previous, d, 0.04)
		previous = d

func _set_hp_shake(offset: float) -> void:
	hearts_box.position.x += offset - hp_shake_offset
	hp_shake_offset = offset

# ---------------------------------------------------------------- pause
func pause_game() -> void:
	if state != State.RUNNING:
		return
	state = State.PAUSED
	pause_count += 1
	_release_inputs()
	lbl_hint.visible = false
	voice.stream_paused = true
	music.stream_paused = true
	pause_box.visible = true
	_update_pad_bar()
	_update_title_prompts()
	_refresh_tutorial()
	btn_resume.grab_focus()

func resume() -> void:
	if state != State.PAUSED:
		return
	_release_inputs()
	pause_box.visible = false
	_update_pad_bar()
	_update_title_prompts()
	lbl_hint.visible = true
	voice.stream_paused = false
	music.stream_paused = false
	state = State.RUNNING
	_refresh_tutorial()

func _release_inputs() -> void:
	ctrl.release_all()
	touches.clear()
	joy_axis_x_steered = false
	joy_trigger_right_held = false
	joy_trigger_left_held = false
	stop_rumble()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if state == State.RUNNING:
			pause_game()
		else:
			_release_inputs()

func _setup_web_visibility() -> void:
	if not OS.has_feature("web"):
		return
	var doc = JavaScriptBridge.get_interface("document")
	if doc == null:
		return
	_js_visibility_cb = JavaScriptBridge.create_callback(_on_js_visibility)
	doc.addEventListener("visibilitychange", _js_visibility_cb)

func _on_js_visibility(_args) -> void:
	var doc = JavaScriptBridge.get_interface("document")
	if doc != null and doc.hidden:
		_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)

## Speed mode switch. Works mid-run (see SpeedController.set_mode) and is saved.
func set_speed_mode(m: String, persist := true) -> void:
	if m != "race" and m != "step":
		m = "race"
	speed_mode = m
	ctrl.set_mode(m)
	touches.clear()
	if persist:
		save.set_setting("speed_mode", m)
		_persist_progress()
	_refresh_mode_buttons()

func mode_name(m := "") -> String:
	var sm: String = m if m != "" else speed_mode
	if sm == "step":
		return I18n.t("MODE_STEP_SHORT", "點放")
	return I18n.t("MODE_RACE_SHORT", "賽車")

func _refresh_mode_buttons() -> void:
	if btn_mode_pause == null:
		return
	btn_mode_pause.text = "模式：%s ⇄ %s" % [mode_name(), mode_name("race" if speed_mode == "step" else "step")]
	if btn_mode_pause_race != null and btn_mode_pause_step != null:
		var race_style := StyleBoxTexture.new()
		race_style.texture = Art.UI.mode_race_active if speed_mode == "race" else Art.UI.mode_race_inactive
		for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			btn_mode_pause_race.add_theme_stylebox_override(s, race_style)
		btn_mode_pause_race.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0) if speed_mode == "race" else Color(0.7, 0.72, 0.8))

		var step_style := StyleBoxTexture.new()
		step_style.texture = Art.UI.mode_step_active if speed_mode == "step" else Art.UI.mode_step_inactive
		for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			btn_mode_pause_step.add_theme_stylebox_override(s, step_style)
		btn_mode_pause_step.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88) if speed_mode == "step" else Color(0.7, 0.72, 0.8))
		(btn_mode_pause_race if speed_mode == "race" else btn_mode_pause_step).button_pressed = true
	(btn_mode_race if speed_mode == "race" else btn_mode_step).button_pressed = true
	lbl_settings_mode.text = "◆ 系統設定 · 選用中：%s模式 ◆" % mode_name()
	if btn_mode_race != null:
		btn_mode_race.text = ("● 賽車模式 (RACING) · 已選用\n長按加速／煞車 · 支援巡航定速" if speed_mode == "race" else "○ 賽車模式 (RACING)\n長按加速／煞車 · 支援巡航定速")
	if btn_mode_step != null:
		btn_mode_step.text = ("● 點放模式 (TAP-STEP) · 已選用\n點一下 ±5 km/h · 節奏精準控速" if speed_mode == "step" else "○ 點放模式 (TAP-STEP)\n點一下 ±5 km/h · 節奏精準控速")
	_layout_select_scroll()

func show_settings() -> void:
	if title_box != null:
		title_box.visible = false
	select_box.visible = false
	settings_box.visible = true
	_refresh_mode_buttons()
	_update_vol_buttons()
	_update_vibration_button()
	_update_hit_pitch_button()
	if btn_lang != null:
		btn_lang.text = "◎ 遊戲語言\n%s" % I18n.LOCALE_NAMES.get(I18n.current_locale, I18n.current_locale)
	_wire_settings_focus()
	_update_pad_bar()
	_update_title_prompts()
	(btn_mode_step if speed_mode == "step" else btn_mode_race).grab_focus()

func set_language(loc: String, persist := true) -> void:
	I18n.set_locale(loc)
	if persist:
		save.set_setting("locale", loc)
		_persist_progress()
	if btn_lang != null:
		btn_lang.text = "◎ 遊戲語言\n%s" % I18n.LOCALE_NAMES.get(loc, loc)
	if lbl_settings_mode != null:
		lbl_settings_mode.text = "◆ 系統設定 · 選用中：%s模式 ◆" % mode_name()
	if btn_mode_race != null:
		btn_mode_race.text = ("● 賽車模式 (RACING) · 已選用\n長按加速／煞車 · 支援巡航定速" if speed_mode == "race" else "○ 賽車模式 (RACING)\n長按加速／煞車 · 支援巡航定速")
	if btn_mode_step != null:
		btn_mode_step.text = ("● 點放模式 (TAP-STEP) · 已選用\n點一下 ±5 km/h · 節奏精準控速" if speed_mode == "step" else "○ 點放模式 (TAP-STEP)\n點一下 ±5 km/h · 節奏精準控速")
	if btn_settings_back != null:
		btn_settings_back.text = I18n.t("BTN_SETTINGS_BACK", "返回確認")
	_update_vol_buttons()
	_update_vibration_button()
	_update_hit_pitch_button()
	_update_pad_bar()
	_update_title_prompts()
	# Pause menu
	if lbl_pause_title != null:
		lbl_pause_title.text = I18n.t("TITLE_PAUSE", "暫停")
	if btn_resume != null:
		btn_resume.text = I18n.t("BTN_RESUME", "繼續")
	if btn_restart != null:
		btn_restart.text = I18n.t("BTN_RESTART", "重來")
	if btn_quit != null:
		btn_quit.text = I18n.t("BTN_QUIT", "回選關")
	if btn_mode_pause_race != null:
		btn_mode_pause_race.text = I18n.t("MODE_PAUSE_RACE", "賽車 (按住)")
	if btn_mode_pause_step != null:
		btn_mode_pause_step.text = I18n.t("MODE_PAUSE_STEP", "點放 ±5")
	# In-game HUD touch buttons
	if btn_accel != null and btn_accel.get_child_count() > 0:
		var la := btn_accel.get_child(0) as Label
		if la != null: la.text = I18n.t("HUD_ACCEL", "加速")
	if btn_brake != null and btn_brake.get_child_count() > 0:
		var lb := btn_brake.get_child(0) as Label
		if lb != null: lb.text = I18n.t("HUD_BRAKE", "煞車")
	if btn_lock != null and btn_lock.get_child_count() > 0:
		var ll := btn_lock.get_child(0) as Label
		if ll != null: ll.text = I18n.t("HUD_LOCK", "鎖定")
	if btn_voice != null and btn_voice.get_child_count() > 0:
		var lv := btn_voice.get_child(0) as Label
		if lv != null: lv.text = I18n.t("HUD_VOICE", "重播")
	# Level select / open submenus
	_refresh_mode_buttons()
	if select_box != null and select_box.visible:
		show_select()
	elif shop_box != null and shop_box.visible:
		_refresh_shop_ui()
	elif achievements_box != null and achievements_box.visible:
		_refresh_achievements_ui()
	elif endless_box != null and endless_box.visible:
		show_endless()

func hide_settings() -> void:
	settings_box.visible = false
	if state == State.TITLE:
		show_title()
	else:
		select_box.visible = true
		_update_pad_bar()
		_update_title_prompts()
		btn_settings.grab_focus()

func _update_vibration_button() -> void:
	if btn_vibration != null and is_instance_valid(btn_vibration):
		var state_str := "開啟 ON" if vibration_enabled else "關閉 OFF"
		btn_vibration.text = "▲ 震動反饋\n%s" % state_str

func _update_hit_pitch_button() -> void:
	if btn_hit_pitch != null and is_instance_valid(btn_hit_pitch):
		var mode := str(save.get_setting("hit_pitch_mode", "pentatonic"))
		var mode_name := "五聲音階"
		if mode == "random": mode_name = "隨機音階"
		elif mode == "fixed": mode_name = "固定音高"
		btn_hit_pitch.text = "◆ 打擊音階\n%s" % mode_name

func _wire_settings_focus() -> void:
	if btn_mode_race == null or btn_mode_step == null or btn_vol_bgm == null:
		return
	btn_mode_race.focus_neighbor_bottom = btn_mode_step.get_path()
	btn_mode_step.focus_neighbor_top = btn_mode_race.get_path()
	btn_mode_step.focus_neighbor_bottom = btn_vol_bgm.get_path()

	btn_vol_bgm.focus_neighbor_top = btn_mode_step.get_path()
	btn_vol_bgm.focus_neighbor_right = btn_vol_sfx.get_path()
	btn_vol_bgm.focus_neighbor_bottom = btn_lang.get_path()

	btn_vol_sfx.focus_neighbor_top = btn_mode_step.get_path()
	btn_vol_sfx.focus_neighbor_left = btn_vol_bgm.get_path()
	btn_vol_sfx.focus_neighbor_right = btn_vol_voice.get_path()
	btn_vol_sfx.focus_neighbor_bottom = btn_lang.get_path()

	btn_vol_voice.focus_neighbor_top = btn_mode_step.get_path()
	btn_vol_voice.focus_neighbor_left = btn_vol_sfx.get_path()
	btn_vol_voice.focus_neighbor_bottom = btn_vibration.get_path() if btn_vibration != null else btn_lang.get_path()

	if btn_lang != null:
		btn_lang.focus_neighbor_top = btn_vol_bgm.get_path()
		if btn_vibration != null:
			btn_lang.focus_neighbor_right = btn_vibration.get_path()
		btn_lang.focus_neighbor_bottom = btn_settings_back.get_path()

	if btn_vibration != null:
		btn_vibration.focus_neighbor_top = btn_vol_voice.get_path()
		btn_vibration.focus_neighbor_left = btn_lang.get_path()
		if btn_hit_pitch != null:
			btn_vibration.focus_neighbor_right = btn_hit_pitch.get_path()
		btn_vibration.focus_neighbor_bottom = btn_settings_back.get_path()

	if btn_hit_pitch != null:
		btn_hit_pitch.focus_neighbor_top = btn_vol_voice.get_path()
		btn_hit_pitch.focus_neighbor_left = btn_vibration.get_path()
		btn_hit_pitch.focus_neighbor_bottom = btn_settings_back.get_path()

	if btn_settings_back != null:
		btn_settings_back.focus_neighbor_top = btn_lang.get_path()

func rumble(weak := 0.4, strong := 0.4, duration := 0.2) -> void:
	if not vibration_enabled:
		return
	var joypads: Array = Input.get_connected_joypads()
	if joypads.is_empty():
		return
	for device in joypads:
		Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), maxf(0.05, duration))

func stop_rumble() -> void:
	var joypads: Array = Input.get_connected_joypads()
	for device in joypads:
		Input.stop_joy_vibration(device)

func _set_input_device(device: String) -> void:
	if current_input_device != device:
		current_input_device = device
		_update_input_prompts()

func _update_input_prompts() -> void:
	for b in [lbl_badge_accel, lbl_badge_brake, lbl_badge_lock, lbl_badge_voice]:
		if b != null and is_instance_valid(b):
			b.text = b.get_meta("pad_text", "") if current_input_device == "joypad" else b.get_meta("kb_text", "")
	_update_pad_bar()
	_update_title_prompts()
	if state == State.READY:
		var speed_help := ""
		if current_input_device == "joypad":
			if speed_mode == "step":
				var step := String.num(ctrl.step_size * 3.6, 2)
				speed_help = I18n.t("HUD_SPEED_HELP_STEP_PAD", "點加速 RT／A +%s／煞車 LT／B -%s km/h") % [step, step]
			else:
				speed_help = I18n.t("HUD_SPEED_HELP_RACE_PAD", "按住加速 RT／A・煞車 LT／B")
			lbl_center.text = I18n.t("HUD_CONTROLS_HELP_PAD", "%s\n左搖桿／十字鍵換線・Y 重播\n按 A 鍵或 RT 開始") % speed_help
		else:
			if speed_mode == "step":
				var step := String.num(ctrl.step_size * 3.6, 2)
				speed_help = I18n.t("HUD_SPEED_HELP_STEP", "點加速 +%s／煞車 -%s km/h（W／S）") % [step, step]
			else:
				speed_help = I18n.t("HUD_SPEED_HELP_RACE", "按住加速／煞車（W／S）")
			lbl_center.text = I18n.t("HUD_CONTROLS_HELP", "%s\n滑動／← → 換線・E 重播\n點畫面或按空白鍵開始") % speed_help

func _update_pad_bar() -> void:
	if pad_bar == null or not is_instance_valid(pad_bar):
		return
	if current_input_device != "joypad":
		pad_bar.visible = false
		return
	pad_bar.visible = true
	if review_box != null and review_box.visible:
		pad_bar.text = I18n.t("PAD_PROMPT_REVIEW", "[X/A/B] 選擇假名  [Y] 重播語音  [Back] 返回")
	elif results_box != null and results_box.visible:
		pad_bar.text = I18n.t("PAD_PROMPT_RESULTS", "[A] 下一關  [X] 重玩  [Y] 錯題練習  [B] 回選關")
	elif pause_box != null and pause_box.visible:
		pad_bar.text = I18n.t("PAD_PROMPT_PAUSE", "[A/Start] 繼續  [X] 重來  [B] 回選關")
	elif settings_box != null and settings_box.visible:
		pad_bar.text = I18n.t("PAD_PROMPT_SETTINGS", "[D-Pad] 移動  [A] 切換設定  [B] 返回選關")
	elif shop_box != null and shop_box.visible:
		pad_bar.text = I18n.t("PAD_PROMPT_SHOP", "[D-Pad] 選擇商品  [A] 購買/裝備  [B] 返回選關")
	elif achievements_box != null and achievements_box.visible:
		pad_bar.text = I18n.t("PAD_PROMPT_ACH", "[D-Pad] 瀏覽成就  [B] 返回選關")
	elif endless_box != null and endless_box.visible:
		pad_bar.text = I18n.t("PAD_PROMPT_ENDLESS", "[A/Start] 出發挑戰！  [B] 返回選關")
	elif chart_box != null and chart_box.visible:
		pad_bar.text = I18n.t("PAD_PROMPT_CHART", "[D-Pad] 移動  [A] 聽發音/勾選  [B] 返回")
	elif title_box != null and title_box.visible:
		pad_bar.text = I18n.t("PAD_PROMPT_TITLE", "[A] 開始遊戲  [Y] 設定  [Back] 離開")
	elif select_box != null and select_box.visible:
		pad_bar.text = I18n.t("PAD_PROMPT_SELECT", "[D-Pad] 移動  [A] 開始  [LB/RB] 切換假名  [Y] 商城  [X] 成就  [Start] 極限")
	elif state == State.RUNNING:
		pad_bar.text = I18n.t("PAD_PROMPT_RUN", "[A/RT] 加速  [B/LT] 煞車  [X] 定速  [Y] 重播  [Start] 暫停")
	elif state == State.READY:
		pad_bar.text = I18n.t("PAD_PROMPT_READY", "[A/RT] 開始奔馳  [B] 回選關")
	else:
		pad_bar.visible = false

func _build_shop() -> void:
	var sp := _panel_center("panel_9slice")
	shop_box = sp[0]
	var shop_root: VBoxContainer = sp[1]
	shop_root.add_theme_constant_override("separation", 14)

	var title := Label.new()
	title.text = I18n.t("BTN_SHOP", "改裝商城")
	title.add_theme_font_override("font", Assets.FONT_HUD)
	title.add_theme_font_size_override("font_size", int(40 * UI))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(title)
	shop_root.add_child(title)

	lbl_shop_points = Label.new()
	lbl_shop_points.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_shop_points.add_theme_font_size_override("font_size", int(24 * UI))
	lbl_shop_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(lbl_shop_points)
	shop_root.add_child(lbl_shop_points)

	shop_scroll = ScrollContainer.new()
	shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shop_scroll.follow_focus = true
	shop_root.add_child(shop_scroll)

	shop_list = VBoxContainer.new()
	shop_list.add_theme_constant_override("separation", 12)
	shop_scroll.add_child(shop_list)

	btn_shop_back = _button(I18n.t("BTN_ENDLESS_BACK", "返回選關"))
	_art_button(btn_shop_back, "btn_secondary", 32)
	btn_shop_back.custom_minimum_size = Vector2(480, 60) * UI
	btn_shop_back.add_theme_font_size_override("font_size", int(26 * UI))
	btn_shop_back.pressed.connect(hide_shop)
	shop_root.add_child(btn_shop_back)

	get_viewport().size_changed.connect(_layout_shop)
	shop_box.visible = false

func _layout_shop() -> void:
	if not is_instance_valid(shop_scroll):
		return
	var view := get_viewport().get_visible_rect().size
	var insets: Dictionary = get_safe_insets()
	var w: float = minf(540.0 * UI, view.x - 60.0 * UI - float(insets.left) - float(insets.right))
	shop_scroll.custom_minimum_size.x = w
	shop_scroll.custom_minimum_size.y = clampf(view.y - 250.0 * UI - float(insets.top) - float(insets.bottom), 120.0, 520.0 * UI)
	if is_instance_valid(btn_shop_back):
		btn_shop_back.custom_minimum_size.x = minf(480.0 * UI, w)

func show_shop() -> void:
	select_box.visible = false
	settings_box.visible = false
	pause_box.visible = false
	if shop_box != null:
		shop_box.visible = false
	if achievements_box != null:
		achievements_box.visible = false
	if endless_box != null:
		endless_box.visible = false
	shop_box.visible = true
	_layout_shop()
	_refresh_shop_ui()
	_update_pad_bar()
	_update_title_prompts()
	btn_shop_back.grab_focus()

func hide_shop() -> void:
	if shop_box != null:
		shop_box.visible = false
	if achievements_box != null:
		achievements_box.visible = false
	show_select()

func _apply_upgrades_from_save() -> void:
	if save == null:
		return
	var aura_id := save.get_equipped_aura()
	var aura_data: Dictionary = AURAS.get(aura_id, AURAS["default"])
	if runner != null:
		runner.set_aura(aura_data.color, float(aura_data.strength), aura_data.get("rim_color", Color.WHITE), float(aura_data.get("rim_strength", 0.0)))
	if runner_trail != null:
		var mat := runner_trail.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = aura_data.trail_color
	# Tactical upgrades
	var hp_lvl: int = save.get_upgrade_level("hp_level")
	if hp_lvl > 0:
		set_max_hp_bonus(hp_lvl * 20, false)
	var armor_lvl: int = save.get_upgrade_level("armor_level")
	if armor_lvl > 0:
		set_damage_reduction(armor_lvl * 15.0)
	var shield_lvl: int = save.get_upgrade_level("shield_level")
	if shield_lvl > 0:
		shield = maxi(shield, shield_lvl)

func _refresh_shop_ui() -> void:
	if not is_instance_valid(shop_list):
		return
	for c in shop_list.get_children():
		shop_list.remove_child(c)
		c.queue_free()

	lbl_shop_points.text = I18n.t("SHOP_POINTS", "持有點數：%d") % save.points()
	var insets: Dictionary = get_safe_insets()
	var view := get_viewport().get_visible_rect().size
	var content_w: float = minf(520.0 * UI, view.x - 80.0 * UI - float(insets.left) - float(insets.right))

	# Section 1: Aura & Trail
	var h1 := Label.new()
	h1.text = I18n.t("SHOP_SECTION_AURA", "【 外觀塗裝與粒子 】")
	h1.add_theme_font_override("font", Assets.FONT_HUD)
	h1.add_theme_font_size_override("font_size", int(22 * UI))
	h1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(h1)
	shop_list.add_child(h1)

	var equipped_aura := save.get_equipped_aura()
	for aura_key in AURAS.keys():
		var a: Dictionary = AURAS[aura_key]
		var item_card := PanelContainer.new()
		var card_sb := StyleBoxFlat.new()
		card_sb.bg_color = Color(0.12, 0.10, 0.20, 0.85)
		card_sb.border_width_left = 3
		card_sb.border_width_right = 3
		card_sb.border_width_top = 3
		card_sb.border_width_bottom = 3
		card_sb.border_color = a.color if equipped_aura == aura_key else Color(0.25, 0.22, 0.40, 0.8)
		card_sb.set_corner_radius_all(8)
		card_sb.set_content_margin_all(8)
		item_card.add_theme_stylebox_override("panel", card_sb)
		item_card.custom_minimum_size.x = content_w
		shop_list.add_child(item_card)

		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		item_card.add_child(row)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var l_name := Label.new()
		l_name.text = I18n.t(a.get("name_key", ""), a.name)
		l_name.add_theme_font_override("font", Assets.FONT_HUD)
		l_name.add_theme_font_size_override("font_size", int(20 * UI))
		l_name.add_theme_color_override("font_color", a.color)
		info.add_child(l_name)

		var l_desc := Label.new()
		l_desc.text = I18n.t(a.get("desc_key", ""), a.desc)
		l_desc.add_theme_font_override("font", Assets.FONT_HUD)
		l_desc.add_theme_font_size_override("font_size", int(15 * UI))
		l_desc.add_theme_color_override("font_color", Color(0.75, 0.78, 0.88))
		info.add_child(l_desc)

		var btn := _button("")
		btn.custom_minimum_size = Vector2(130, 48) * UI
		btn.add_theme_font_size_override("font_size", int(18 * UI))
		row.add_child(btn)

		var aura_id := str(aura_key)
		var is_equipped: bool = str(equipped_aura) == aura_id
		var is_unlocked: bool = save.is_aura_unlocked(aura_id)
		if is_equipped:
			btn.text = I18n.t("SHOP_EQUIPPED", "已裝備")
			btn.disabled = true
			_art_button(btn, "btn_small", 32)
		elif is_unlocked:
			btn.text = I18n.t("SHOP_EQUIP", "裝備")
			_art_button(btn, "btn_primary", 32)
			btn.pressed.connect(func():
				save.equip_aura(aura_id)
				save.save_file()
				_apply_upgrades_from_save()
				_refresh_shop_ui()
			)
		else:
			var cost: int = int(a.cost)
			btn.text = "%d 點" % cost
			btn.disabled = save.points() < cost
			_art_button(btn, "btn_secondary" if btn.disabled else "btn_primary", 32)
			btn.pressed.connect(func():
				if save.unlock_aura(aura_id, cost):
					save.equip_aura(aura_id)
					save.save_file()
					_apply_upgrades_from_save()
					check_achievement("custom_racer")
					_refresh_shop_ui()
			)

	# Section 2: Tactical Upgrades
	var h2 := Label.new()
	h2.text = I18n.t("SHOP_SECTION_UPGRADE", "【 戰術裝備升級 】")
	h2.add_theme_font_override("font", Assets.FONT_HUD)
	h2.add_theme_font_size_override("font_size", int(22 * UI))
	h2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(h2)
	shop_list.add_child(h2)

	for upg_key in UPGRADES.keys():
		var u: Dictionary = UPGRADES[upg_key]
		var upg_id := str(upg_key)
		var cur_lvl: int = save.get_upgrade_level(upg_id)
		var max_lvl: int = int(u.max_level)

		var item_card := PanelContainer.new()
		var card_sb := StyleBoxFlat.new()
		card_sb.bg_color = Color(0.12, 0.10, 0.20, 0.85)
		card_sb.border_width_left = 3
		card_sb.border_width_right = 3
		card_sb.border_width_top = 3
		card_sb.border_width_bottom = 3
		card_sb.border_color = Color(0.35, 0.70, 0.95, 0.85) if cur_lvl > 0 else Color(0.25, 0.22, 0.40, 0.8)
		card_sb.set_corner_radius_all(8)
		card_sb.set_content_margin_all(8)
		item_card.add_theme_stylebox_override("panel", card_sb)
		item_card.custom_minimum_size.x = content_w
		shop_list.add_child(item_card)

		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		item_card.add_child(row)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var l_name := Label.new()
		l_name.text = "%s (Lv.%d/%d)" % [u.name, cur_lvl, max_lvl]
		l_name.add_theme_font_override("font", Assets.FONT_HUD)
		l_name.add_theme_font_size_override("font_size", int(20 * UI))
		_ink(l_name)
		info.add_child(l_name)

		var l_desc := Label.new()
		l_desc.text = u.desc
		l_desc.add_theme_font_override("font", Assets.FONT_HUD)
		l_desc.add_theme_font_size_override("font_size", int(15 * UI))
		l_desc.add_theme_color_override("font_color", Color(0.75, 0.78, 0.88))
		info.add_child(l_desc)

		var btn := _button("")
		btn.custom_minimum_size = Vector2(130, 48) * UI
		btn.add_theme_font_size_override("font_size", int(18 * UI))
		row.add_child(btn)

		if cur_lvl >= max_lvl:
			btn.text = "已滿級"
			btn.disabled = true
			_art_button(btn, "btn_small", 32)
		else:
			var cost: int = int(u.costs[cur_lvl])
			btn.text = "%d 點" % cost
			btn.disabled = save.points() < cost
			_art_button(btn, "btn_secondary" if btn.disabled else "btn_primary", 32)
			btn.pressed.connect(func():
				if save.buy_upgrade(upg_id, max_lvl, cost):
					save.save_file()
					_apply_upgrades_from_save()
					check_achievement("custom_racer")
					_refresh_shop_ui()
			)

func _build_achievements() -> void:
	var ap := _panel_center("panel_9slice")
	achievements_box = ap[0]
	var ach_root: VBoxContainer = ap[1]
	ach_root.add_theme_constant_override("separation", 14)

	var title := Label.new()
	title.text = I18n.t("BTN_ACHIEVEMENTS", "成就獎章")
	title.add_theme_font_override("font", Assets.FONT_HUD)
	title.add_theme_font_size_override("font_size", int(40 * UI))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(title)
	ach_root.add_child(title)

	lbl_achievements_count = Label.new()
	lbl_achievements_count.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_achievements_count.add_theme_font_size_override("font_size", int(24 * UI))
	lbl_achievements_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(lbl_achievements_count)
	ach_root.add_child(lbl_achievements_count)

	achievements_scroll = ScrollContainer.new()
	achievements_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	achievements_scroll.follow_focus = true
	ach_root.add_child(achievements_scroll)

	achievements_list = VBoxContainer.new()
	achievements_list.add_theme_constant_override("separation", 10)
	achievements_scroll.add_child(achievements_list)

	btn_achievements_back = _button(I18n.t("BTN_ENDLESS_BACK", "返回選關"))
	_art_button(btn_achievements_back, "btn_secondary", 32)
	btn_achievements_back.custom_minimum_size = Vector2(480, 60) * UI
	btn_achievements_back.add_theme_font_size_override("font_size", int(26 * UI))
	btn_achievements_back.pressed.connect(hide_achievements)
	ach_root.add_child(btn_achievements_back)

	get_viewport().size_changed.connect(_layout_achievements)
	achievements_box.visible = false

func _layout_achievements() -> void:
	if not is_instance_valid(achievements_scroll):
		return
	var view := get_viewport().get_visible_rect().size
	var insets: Dictionary = get_safe_insets()
	var w: float = minf(540.0 * UI, view.x - 60.0 * UI - float(insets.left) - float(insets.right))
	achievements_scroll.custom_minimum_size.x = w
	achievements_scroll.custom_minimum_size.y = clampf(view.y - 250.0 * UI - float(insets.top) - float(insets.bottom), 120.0, 520.0 * UI)
	if is_instance_valid(btn_achievements_back):
		btn_achievements_back.custom_minimum_size.x = minf(480.0 * UI, w)

func show_achievements() -> void:
	select_box.visible = false
	settings_box.visible = false
	pause_box.visible = false
	if shop_box != null:
		shop_box.visible = false
	if achievements_box != null:
		achievements_box.visible = false
	if endless_box != null:
		endless_box.visible = false
	achievements_box.visible = true
	_layout_achievements()
	_refresh_achievements_ui()
	_update_pad_bar()
	_update_title_prompts()
	btn_achievements_back.grab_focus()

func hide_achievements() -> void:
	if achievements_box != null:
		achievements_box.visible = false
	show_select()

func _refresh_achievements_ui() -> void:
	if not is_instance_valid(achievements_list):
		return
	for c in achievements_list.get_children():
		achievements_list.remove_child(c)
		c.queue_free()

	var unlocked_count: int = save.achievement_count() if save != null else 0
	var total_count: int = ACHIEVEMENTS.size()
	lbl_achievements_count.text = I18n.t("ACH_PROGRESS", "達成進度：%d / %d") % [unlocked_count, total_count]

	var insets: Dictionary = get_safe_insets()
	var view := get_viewport().get_visible_rect().size
	var content_w: float = minf(520.0 * UI, view.x - 80.0 * UI - float(insets.left) - float(insets.right))

	btn_claim_all = null
	var unclaimed: int = save.unclaimed_achievement_count() if save != null else 0
	if unclaimed > 0:
		btn_claim_all = _button("一鍵領取全部獎勵 (%d 項)" % unclaimed)
		_art_button(btn_claim_all, "btn_primary", 32)
		btn_claim_all.custom_minimum_size = Vector2(content_w, 48 * UI)
		btn_claim_all.add_theme_font_size_override("font_size", int(18 * UI))
		btn_claim_all.pressed.connect(func():
			for k in ACHIEVEMENTS.keys():
				var aid := str(k)
				if save.is_achievement_unlocked(aid) and not save.is_achievement_claimed(aid):
					var rew: int = int(ACHIEVEMENTS[k].get("reward", 0))
					save.claim_achievement(aid, rew)
			save.save_file()
			sfx("star", 1.3, 3.0)
			_refresh_achievements_ui()
		)
		achievements_list.add_child(btn_claim_all)

	for ach_key in ACHIEVEMENTS.keys():
		var ach_id := str(ach_key)
		var a: Dictionary = ACHIEVEMENTS[ach_key]
		var is_unlocked: bool = save.is_achievement_unlocked(ach_id) if save != null else false
		var is_claimed: bool = save.is_achievement_claimed(ach_id) if save != null else false

		var item_card := PanelContainer.new()
		var card_sb := StyleBoxFlat.new()
		card_sb.bg_color = Color(0.12, 0.10, 0.20, 0.85) if is_unlocked else Color(0.08, 0.07, 0.14, 0.65)
		card_sb.border_width_left = 3
		card_sb.border_width_right = 3
		card_sb.border_width_top = 3
		card_sb.border_width_bottom = 3
		card_sb.border_color = Color(1.0, 0.85, 0.25, 0.9) if is_unlocked else Color(0.25, 0.22, 0.38, 0.6)
		card_sb.set_corner_radius_all(8)
		card_sb.set_content_margin_all(10)
		item_card.add_theme_stylebox_override("panel", card_sb)
		item_card.custom_minimum_size.x = content_w
		achievements_list.add_child(item_card)

		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		item_card.add_child(row)

		var badge_icon := TextureRect.new()
		badge_icon.texture = Art.UI.star_full_40 if is_unlocked else Art.UI.star_empty_40
		badge_icon.custom_minimum_size = Vector2(36, 36) * UI
		badge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge_icon.modulate = Color(1.0, 0.9, 0.3) if is_unlocked else Color(0.5, 0.5, 0.6, 0.6)
		row.add_child(badge_icon)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var l_title := Label.new()
		l_title.text = a.title
		l_title.add_theme_font_override("font", Assets.FONT_HUD)
		l_title.add_theme_font_size_override("font_size", int(20 * UI))
		l_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4) if is_unlocked else Color(0.65, 0.68, 0.78))
		info.add_child(l_title)

		var l_desc := Label.new()
		l_desc.text = a.desc
		l_desc.add_theme_font_override("font", Assets.FONT_HUD)
		l_desc.add_theme_font_size_override("font_size", int(15 * UI))
		l_desc.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9) if is_unlocked else Color(0.48, 0.50, 0.60))
		info.add_child(l_desc)

		var status_box := VBoxContainer.new()
		status_box.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(status_box)

		if not is_unlocked:
			var l_stat := Label.new()
			l_stat.text = "未達成"
			l_stat.add_theme_font_override("font", Assets.FONT_HUD)
			l_stat.add_theme_font_size_override("font_size", int(16 * UI))
			l_stat.add_theme_color_override("font_color", Color(0.5, 0.52, 0.6))
			l_stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			status_box.add_child(l_stat)

			var l_rew := Label.new()
			l_rew.text = "+%d 點" % int(a.reward)
			l_rew.add_theme_font_override("font", Assets.FONT_HUD)
			l_rew.add_theme_font_size_override("font_size", int(14 * UI))
			l_rew.add_theme_color_override("font_color", Color(0.45, 0.48, 0.55))
			l_rew.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			status_box.add_child(l_rew)
		elif is_claimed:
			var l_stat := Label.new()
			l_stat.text = "✓ 已領取"
			l_stat.add_theme_font_override("font", Assets.FONT_HUD)
			l_stat.add_theme_font_size_override("font_size", int(16 * UI))
			l_stat.add_theme_color_override("font_color", Color(0.3, 0.95, 0.45))
			l_stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			status_box.add_child(l_stat)

			var l_rew := Label.new()
			l_rew.text = "+%d 點" % int(a.reward)
			l_rew.add_theme_font_override("font", Assets.FONT_HUD)
			l_rew.add_theme_font_size_override("font_size", int(14 * UI))
			l_rew.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
			l_rew.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			status_box.add_child(l_rew)
		else:
			var btn_claim := _button("領取 +%d 點" % int(a.reward))
			_art_button(btn_claim, "btn_primary", 32)
			btn_claim.custom_minimum_size = Vector2(130, 44) * UI
			btn_claim.add_theme_font_size_override("font_size", int(16 * UI))
			btn_claim.pressed.connect(func():
				if save.claim_achievement(ach_id, int(a.reward)):
					save.save_file()
					sfx("star", 1.2, 2.0)
					_refresh_achievements_ui()
			)
			status_box.add_child(btn_claim)

func _build_achievement_toast() -> void:
	achievement_toast = PanelContainer.new()
	achievement_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.16, 0.94)
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(1.0, 0.85, 0.25, 0.95)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	achievement_toast.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.name = "HBox"
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 14)
	achievement_toast.add_child(hbox)

	var icon := TextureRect.new()
	icon.texture = Art.UI.badge_new_record
	icon.custom_minimum_size = Vector2(44, 44) * UI
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	var lbl_top := Label.new()
	lbl_top.name = "LblTop"
	lbl_top.text = "★ 成就解鎖！"
	lbl_top.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_top.add_theme_font_size_override("font_size", int(18 * UI))
	lbl_top.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	vbox.add_child(lbl_top)

	toast_lbl_name = Label.new()
	toast_lbl_name.name = "LblName"
	toast_lbl_name.add_theme_font_override("font", Assets.FONT_HUD)
	toast_lbl_name.add_theme_font_size_override("font_size", int(22 * UI))
	toast_lbl_name.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(toast_lbl_name)

	toast_lbl_desc = Label.new()
	toast_lbl_desc.name = "LblDesc"
	toast_lbl_desc.add_theme_font_override("font", Assets.FONT_HUD)
	toast_lbl_desc.add_theme_font_size_override("font_size", int(15 * UI))
	toast_lbl_desc.add_theme_color_override("font_color", Color(0.4, 0.88, 1.0))
	vbox.add_child(toast_lbl_desc)

	achievement_toast.visible = false
	hud.add_child(achievement_toast)

func _build_transitions() -> void:
	transition_layer = CanvasLayer.new()
	transition_layer.layer = 100
	add_child(transition_layer)
	fade_rect = ColorRect.new()
	fade_rect.color = Color.BLACK
	fade_rect.modulate.a = 0.0
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_px(fade_rect, 0, 0, 1, 1, 0, 0, 0, 0)
	transition_layer.add_child(fade_rect)

func fade_transition(on_midpoint: Callable, fade_out := 0.22, fade_in := 0.22) -> void:
	if instant_transitions or autopilot or not is_inside_tree() or fade_out <= 0.0:
		on_midpoint.call()
		return
	if is_transitioning:
		on_midpoint.call()
		return
	is_transitioning = true
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, fade_out).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		on_midpoint.call()
	)
	tw.tween_property(fade_rect, "modulate:a", 0.0, fade_in).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if is_instance_valid(fade_rect):
			fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		is_transitioning = false
	)

func _build_title() -> void:
	var tp := _panel_center("panel_9slice")
	title_box = tp[0]
	var title_root: VBoxContainer = tp[1]
	title_root.add_theme_constant_override("separation", 14)

	title_logo_rect = TextureRect.new()
	title_logo_rect.texture = Art.ICON
	title_logo_rect.custom_minimum_size = Vector2(110, 110) * UI
	title_logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_logo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_root.add_child(title_logo_rect)

	lbl_title_name = Label.new()
	lbl_title_name.text = I18n.t("GAME_TITLE", "假名跑酷 2.0")
	lbl_title_name.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_title_name.add_theme_font_size_override("font_size", int(48 * UI))
	lbl_title_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title_name.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))
	lbl_title_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	lbl_title_name.add_theme_constant_override("shadow_offset_x", 3)
	lbl_title_name.add_theme_constant_override("shadow_offset_y", 3)
	title_root.add_child(lbl_title_name)

	lbl_title_sub = Label.new()
	lbl_title_sub.text = I18n.t("GAME_SUBTITLE", "日語五十音聽力疾走")
	lbl_title_sub.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_title_sub.add_theme_font_size_override("font_size", int(22 * UI))
	lbl_title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title_sub.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 0.9))
	title_root.add_child(lbl_title_sub)

	lbl_title_press = Label.new()
	lbl_title_press.text = I18n.t("TITLE_PRESS_START_KEY", "— 點擊畫面 或 按空白鍵開始 —")
	lbl_title_press.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_title_press.add_theme_font_size_override("font_size", int(20 * UI))
	lbl_title_press.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title_press.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	title_root.add_child(lbl_title_press)

	var btn_vbox := VBoxContainer.new()
	btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_vbox.add_theme_constant_override("separation", 10)
	title_root.add_child(btn_vbox)

	btn_title_start = _button(I18n.t("BTN_START_GAME", "開始遊戲"))
	btn_title_start.custom_minimum_size = Vector2(360, 68) * UI
	_art_button(btn_title_start, "btn_primary", 32)
	btn_vbox.add_child(btn_title_start)

	btn_title_chart = _button(I18n.t("BTN_CHART", "五十音・特訓"))
	btn_title_chart.custom_minimum_size = Vector2(360, 56) * UI
	_art_button(btn_title_chart, "btn_secondary", 32)
	btn_vbox.add_child(btn_title_chart)

	var sub_hbox := HBoxContainer.new()
	sub_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	sub_hbox.add_theme_constant_override("separation", 10)
	btn_vbox.add_child(sub_hbox)

	btn_title_settings = _button(I18n.t("BTN_TITLE_SETTINGS", "設定"))
	btn_title_settings.custom_minimum_size = Vector2(175, 56) * UI
	_art_button(btn_title_settings, "btn_secondary", 32)
	sub_hbox.add_child(btn_title_settings)

	btn_title_quit = _button(I18n.t("BTN_TITLE_QUIT", "離開遊戲"))
	btn_title_quit.custom_minimum_size = Vector2(175, 56) * UI
	_art_button(btn_title_quit, "btn_secondary", 32)
	sub_hbox.add_child(btn_title_quit)

	btn_title_start.pressed.connect(start_from_title)
	btn_title_chart.pressed.connect(func(): show_chart())
	btn_title_settings.pressed.connect(show_settings)
	btn_title_quit.pressed.connect(func():
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
		get_tree().quit()
	)

	_wire_title_focus()
	title_box.visible = false

func _wire_title_focus() -> void:
	if btn_title_start == null or btn_title_chart == null or btn_title_settings == null or btn_title_quit == null:
		return
	btn_title_start.focus_neighbor_bottom = btn_title_chart.get_path()
	btn_title_chart.focus_neighbor_top = btn_title_start.get_path()
	btn_title_chart.focus_neighbor_bottom = btn_title_settings.get_path()
	btn_title_settings.focus_neighbor_top = btn_title_chart.get_path()
	btn_title_settings.focus_neighbor_right = btn_title_quit.get_path()
	btn_title_quit.focus_neighbor_top = btn_title_chart.get_path()
	btn_title_quit.focus_neighbor_left = btn_title_settings.get_path()

func _update_title_prompts() -> void:
	if lbl_title_name != null and is_instance_valid(lbl_title_name):
		lbl_title_name.text = I18n.t("GAME_TITLE", "假名跑酷 2.0")
	if lbl_title_sub != null and is_instance_valid(lbl_title_sub):
		lbl_title_sub.text = I18n.t("GAME_SUBTITLE", "日語五十音聽力疾走")
	if lbl_title_press != null and is_instance_valid(lbl_title_press):
		if current_input_device == "joypad":
			lbl_title_press.text = I18n.t("TITLE_PRESS_START_PAD", "— 按 [A] 鍵開始遊戲 —")
		else:
			lbl_title_press.text = I18n.t("TITLE_PRESS_START_KEY", "— 點擊畫面 或 按空白鍵開始 —")
	if btn_title_start != null and is_instance_valid(btn_title_start):
		btn_title_start.text = I18n.t("BTN_START_GAME", "開始遊戲")
	if btn_title_chart != null and is_instance_valid(btn_title_chart):
		btn_title_chart.text = I18n.t("BTN_CHART", "五十音・特訓")
	if btn_title_settings != null and is_instance_valid(btn_title_settings):
		btn_title_settings.text = I18n.t("BTN_TITLE_SETTINGS", "設定")
	if btn_title_quit != null and is_instance_valid(btn_title_quit):
		btn_title_quit.text = I18n.t("BTN_TITLE_QUIT", "離開遊戲")

func show_title() -> void:
	state = State.TITLE
	if title_box != null:
		title_box.visible = true
	if chart_box != null:
		chart_box.visible = false
	if select_box != null:
		select_box.visible = false
	if results_box != null:
		results_box.visible = false
	if pause_box != null:
		pause_box.visible = false
	if settings_box != null:
		settings_box.visible = false
	if shop_box != null:
		shop_box.visible = false
	if achievements_box != null:
		achievements_box.visible = false
	if endless_box != null:
		endless_box.visible = false
	lbl_center.text = ""
	lbl_hint.text = ""
	_update_title_prompts()
	_update_pad_bar()
	if btn_title_start != null and is_instance_valid(btn_title_start):
		btn_title_start.grab_focus()

	if press_start_tween != null and press_start_tween.is_valid():
		press_start_tween.kill()
	if lbl_title_press != null and is_instance_valid(lbl_title_press):
		press_start_tween = create_tween().set_loops()
		press_start_tween.tween_property(lbl_title_press, "modulate:a", 0.35, 0.7).set_trans(Tween.TRANS_SINE)
		press_start_tween.tween_property(lbl_title_press, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)

func start_from_title() -> void:
	if title_box == null or not title_box.visible:
		return
	sfx("star", 1.1, 1.0)
	fade_transition(func():
		title_box.visible = false
		show_select()
	, 0.22, 0.22)

func _queue_achievement_toast(id: String, title: String, desc: String, reward: int) -> void:
	toast_queue.append({"id": id, "title": title, "desc": desc, "reward": reward})
	if toast_tween == null or not toast_tween.is_valid() or not toast_tween.is_running():
		_show_next_achievement_toast()

func _show_next_achievement_toast() -> void:
	if toast_queue.is_empty() or achievement_toast == null or not is_inside_tree():
		return
	var item: Dictionary = toast_queue.pop_front()
	if toast_lbl_name: toast_lbl_name.text = "【%s】" % str(item.title)
	if toast_lbl_desc: toast_lbl_desc.text = "%s · 獎勵 +%d 點" % [str(item.desc), int(item.reward)]

	var view := get_viewport().get_visible_rect().size
	var insets: Dictionary = get_safe_insets()
	var toast_w := minf(500.0 * UI, view.x - 40.0 * UI)
	achievement_toast.custom_minimum_size = Vector2(toast_w, 0)
	achievement_toast.reset_size()
	var toast_x := (view.x - achievement_toast.size.x) * 0.5
	var start_y := -achievement_toast.size.y - 20.0
	var target_y := float(insets.top) + 20.0 * UI

	achievement_toast.position = Vector2(toast_x, start_y)
	achievement_toast.visible = true
	achievement_toast.modulate.a = 0.0

	sfx("star", 1.25, 3.0)

	if toast_tween != null:
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_property(achievement_toast, "position:y", target_y, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	toast_tween.parallel().tween_property(achievement_toast, "modulate:a", 1.0, 0.2)
	toast_tween.tween_interval(2.6)
	toast_tween.tween_property(achievement_toast, "position:y", start_y, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	toast_tween.parallel().tween_property(achievement_toast, "modulate:a", 0.0, 0.3)
	toast_tween.tween_callback(func():
		if is_instance_valid(achievement_toast):
			achievement_toast.visible = false
		_show_next_achievement_toast()
	)

func check_achievement(id: String) -> void:
	if save == null or save.is_achievement_unlocked(id):
		return
	var ach_data: Dictionary = ACHIEVEMENTS.get(id, {})
	if ach_data.is_empty():
		return
	var reward: int = int(ach_data.get("reward", 0))
	if save.unlock_achievement(id):
		save.save_file()
		_queue_achievement_toast(id, str(ach_data.get("title", "")), str(ach_data.get("desc", "")), reward)

func _build_endless() -> void:
	var ep := _panel_center("panel_9slice")
	endless_box = ep[0]
	var endless_root: VBoxContainer = ep[1]
	endless_root.add_theme_constant_override("separation", 14)

	var title := Label.new()
	title.text = I18n.t("ENDLESS_PANEL_TITLE", "無盡極限跑酷")
	title.add_theme_font_override("font", Assets.FONT_HUD)
	title.add_theme_font_size_override("font_size", int(40 * UI))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(title)
	endless_root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = I18n.t("ENDLESS_PANEL_SUB", "全五十音隨機循環 · 波次難度漸增 · 挑戰生存極限")
	subtitle.add_theme_font_override("font", Assets.FONT_HUD)
	subtitle.add_theme_font_size_override("font_size", int(18 * UI))
	subtitle.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(subtitle)
	endless_root.add_child(subtitle)

	endless_scroll = ScrollContainer.new()
	endless_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	endless_scroll.follow_focus = true
	endless_root.add_child(endless_scroll)

	endless_list = VBoxContainer.new()
	endless_list.add_theme_constant_override("separation", 12)
	endless_scroll.add_child(endless_list)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	endless_root.add_child(btn_row)

	btn_endless_start = _button(I18n.t("BTN_ENDLESS_START", "出發挑戰！"))
	_art_button(btn_endless_start, "btn_primary", 32)
	btn_endless_start.custom_minimum_size = Vector2(230, 56) * UI
	btn_endless_start.add_theme_font_size_override("font_size", int(24 * UI))
	btn_endless_start.pressed.connect(start_endless)
	btn_row.add_child(btn_endless_start)

	btn_endless_back = _button(I18n.t("BTN_ENDLESS_BACK", "返回選關"))
	_art_button(btn_endless_back, "btn_secondary", 32)
	btn_endless_back.custom_minimum_size = Vector2(230, 56) * UI
	btn_endless_back.add_theme_font_size_override("font_size", int(24 * UI))
	btn_endless_back.pressed.connect(hide_endless)
	btn_row.add_child(btn_endless_back)

	get_viewport().size_changed.connect(_layout_endless)
	endless_box.visible = false

func _layout_endless() -> void:
	if not is_instance_valid(endless_scroll):
		return
	var view := get_viewport().get_visible_rect().size
	var insets: Dictionary = get_safe_insets()
	var w: float = minf(540.0 * UI, view.x - 60.0 * UI - float(insets.left) - float(insets.right))
	endless_scroll.custom_minimum_size.x = w
	endless_scroll.custom_minimum_size.y = clampf(view.y - 250.0 * UI - float(insets.top) - float(insets.bottom), 120.0, 520.0 * UI)
	if is_instance_valid(btn_endless_start) and is_instance_valid(btn_endless_back):
		var bw: float = (w - 20.0) * 0.5
		btn_endless_start.custom_minimum_size.x = bw
		btn_endless_back.custom_minimum_size.x = bw

func show_endless() -> void:
	select_box.visible = false
	settings_box.visible = false
	pause_box.visible = false
	if shop_box != null: shop_box.visible = false
	if achievements_box != null: achievements_box.visible = false
	if endless_box != null: endless_box.visible = true
	_layout_endless()
	_refresh_endless_ui()
	_update_pad_bar()
	_update_title_prompts()
	if is_instance_valid(btn_endless_start):
		btn_endless_start.grab_focus()

func hide_endless() -> void:
	if endless_box != null:
		endless_box.visible = false
	show_select()
	if is_instance_valid(btn_endless):
		btn_endless.grab_focus()

func _refresh_endless_ui() -> void:
	if not is_instance_valid(endless_list):
		return
	for c in endless_list.get_children():
		endless_list.remove_child(c)
		c.queue_free()

	var insets: Dictionary = get_safe_insets()
	var view := get_viewport().get_visible_rect().size
	var content_w: float = minf(520.0 * UI, view.x - 80.0 * UI - float(insets.left) - float(insets.right))

	var ed: Dictionary = save.get_endless() if save != null else {}
	var best_score: int = int(ed.get("best_score", 0))
	var best_dist: float = float(ed.get("best_distance", 0.0))
	var best_cor: int = int(ed.get("best_correct", 0))
	var best_cmb: int = int(ed.get("best_combo", 0))

	# 1. Best record stats card
	var stats_card := PanelContainer.new()
	var stats_sb := StyleBoxFlat.new()
	stats_sb.bg_color = Color(0.10, 0.09, 0.18, 0.90)
	stats_sb.border_width_left = 3
	stats_sb.border_width_right = 3
	stats_sb.border_width_top = 3
	stats_sb.border_width_bottom = 3
	stats_sb.border_color = Color(0.2, 0.9, 1.0, 0.85)
	stats_sb.set_corner_radius_all(10)
	stats_sb.set_content_margin_all(14)
	stats_card.add_theme_stylebox_override("panel", stats_sb)
	stats_card.custom_minimum_size.x = content_w
	endless_list.add_child(stats_card)

	var stats_vb := VBoxContainer.new()
	stats_vb.add_theme_constant_override("separation", 6)
	stats_card.add_child(stats_vb)

	var lbl_stats_title := Label.new()
	lbl_stats_title.text = I18n.t("ENDLESS_BEST_TITLE", "★ 個人歷史最佳戰績")
	lbl_stats_title.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_stats_title.add_theme_font_size_override("font_size", int(22 * UI))
	lbl_stats_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	stats_vb.add_child(lbl_stats_title)

	var lbl_score := Label.new()
	lbl_score.text = I18n.t("ENDLESS_BEST_SCORE", "最高得分：%d 分") % best_score
	lbl_score.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_score.add_theme_font_size_override("font_size", int(20 * UI))
	lbl_score.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	stats_vb.add_child(lbl_score)

	var lbl_substats := Label.new()
	lbl_substats.text = I18n.t("ENDLESS_BEST_SUBSTATS", "最遠奔馳：%.1f 公尺　最多正解：%d 題　最高連擊：%d") % [best_dist, best_cor, best_cmb]
	lbl_substats.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_substats.add_theme_font_size_override("font_size", int(15 * UI))
	lbl_substats.add_theme_color_override("font_color", Color(0.7, 0.75, 0.88))
	stats_vb.add_child(lbl_substats)

	# 2. Rules card
	var rules_card := PanelContainer.new()
	var rules_sb := StyleBoxFlat.new()
	rules_sb.bg_color = Color(0.08, 0.07, 0.14, 0.75)
	rules_sb.border_width_left = 2
	rules_sb.border_width_right = 2
	rules_sb.border_width_top = 2
	rules_sb.border_width_bottom = 2
	rules_sb.border_color = Color(0.4, 0.35, 0.6, 0.6)
	rules_sb.set_corner_radius_all(10)
	rules_sb.set_content_margin_all(12)
	rules_card.add_theme_stylebox_override("panel", rules_sb)
	rules_card.custom_minimum_size.x = content_w
	endless_list.add_child(rules_card)

	var rules_vb := VBoxContainer.new()
	rules_vb.add_theme_constant_override("separation", 6)
	rules_card.add_child(rules_vb)

	var l_rt := Label.new()
	l_rt.text = I18n.t("ENDLESS_RULES_TITLE", "★ 極限挑戰機制")
	l_rt.add_theme_font_override("font", Assets.FONT_HUD)
	l_rt.add_theme_font_size_override("font_size", int(18 * UI))
	l_rt.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	rules_vb.add_child(l_rt)

	var l_rd := Label.new()
	l_rd.text = I18n.t("ENDLESS_RULES_BODY", "• 每 10 題為一個 WAVE，最高時速持續攀升、石碑間隔逐步緊縮！\n• 每達成 10 連擊觸發「連擊獎勵」，立即回復 +15 HP 體力續命！\n• 改裝商城解鎖的光芒特效、最大體力、護盾抵擋均全數繼承！\n• 最終結算得分可換算為改裝商城點數，多玩多賺！")
	l_rd.add_theme_font_override("font", Assets.FONT_HUD)
	l_rd.add_theme_font_size_override("font_size", int(14 * UI))
	l_rd.add_theme_color_override("font_color", Color(0.75, 0.78, 0.88))
	rules_vb.add_child(l_rd)

	# 3. Top 5 history
	var hist: Array = ed.get("history", [])
	if not hist.is_empty():
		var hist_title := Label.new()
		hist_title.text = I18n.t("ENDLESS_TOP5_TITLE", "★ 歷史戰績 TOP 5")
		hist_title.add_theme_font_override("font", Assets.FONT_HUD)
		hist_title.add_theme_font_size_override("font_size", int(18 * UI))
		hist_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		endless_list.add_child(hist_title)

		for i in hist.size():
			var h_item: Dictionary = hist[i]
			var h_row := PanelContainer.new()
			var h_sb := StyleBoxFlat.new()
			h_sb.bg_color = Color(0.06, 0.05, 0.11, 0.70)
			h_sb.border_width_left = 1
			h_sb.border_width_right = 1
			h_sb.border_width_top = 1
			h_sb.border_width_bottom = 1
			h_sb.border_color = Color(0.3, 0.35, 0.5, 0.4)
			h_sb.set_corner_radius_all(6)
			h_sb.set_content_margin_all(8)
			h_row.add_theme_stylebox_override("panel", h_sb)
			h_row.custom_minimum_size.x = content_w
			endless_list.add_child(h_row)

			var h_lbl := Label.new()
			var medal: String = ["①", "②", "③", "④", "⑤"][i] if i < 5 else "•"
			h_lbl.text = I18n.t("ENDLESS_TOP5_ROW", "%s 第 %d 名：%d 分  (%.0fm · %d 題 · %d 連擊)") % [
				medal, i + 1, int(h_item.get("score", 0)),
				float(h_item.get("distance", 0.0)),
				int(h_item.get("correct", 0)),
				int(h_item.get("combo", 0))
			]
			h_lbl.add_theme_font_override("font", Assets.FONT_HUD)
			h_lbl.add_theme_font_size_override("font_size", int(14 * UI))
			h_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
			h_row.add_child(h_lbl)

func _get_endless_pool_for_tier(t: int) -> Array:
	var rows: Array = []
	if t == 0:
		rows = ["あ行", "か行", "さ行", "た行", "な行"]
	elif t == 1:
		rows = ["あ行", "か行", "さ行", "た行", "な行", "は行", "ま行", "や行", "ら行", "わ行"]
	elif t == 2:
		rows = ["あ行", "か行", "さ行", "た行", "な行", "は行", "ま行", "や行", "ら行", "わ行", "が行", "ざ行", "だ行", "ば行", "ぱ行"]
	elif t == 3:
		rows = ["あ行", "か行", "さ行", "た行", "な行", "は行", "ま行", "や行", "ら行", "わ行", "ア行", "カ行", "サ行", "タ行", "ナ行"]
	else:
		rows = cfg.get("kana_rows", {}).keys()
	var res := LevelDB.pool_for_rows(cfg, rows)
	return res if not res.is_empty() else ["あ", "い", "う", "え", "お"]

func start_endless() -> void:
	_end_tutorial()
	if endless_box != null:
		endless_box.visible = false
	select_box.visible = false
	is_endless = true
	endless_score = 0
	endless_tier = 0

	var rm := LevelDB.romaji_map(cfg)
	var pool := _get_endless_pool_for_tier(0)
	lvl = {
		"id": "endless",
		"name": "無盡極限挑戰",
		"type": "endless",
		"script": "all",
		"target_correct": 999999,
		"time_limit_s": 999999.0,
		"wrong_penalty_s": 0.0,
		"miss_penalty_s": 0.0,
		"voice_locked": false,
		"kana": pool,
		"romaji": pool.map(func(k): return rm.get(k, "")),
		"review_kana": []
	}
	level_id = "endless"
	hint_first_n = 1
	hint_ratio = 0.02

	var HP: Dictionary = cfg.get("hp", {})
	base_max_hp = maxi(1, int(HP.get("max_hp", 100)))
	wrong_damage = 30
	miss_damage = 15
	damage_reduction = 0.0
	shield_thresholds = []
	boss_shield_up = false
	_apply_bgm()

	reset_run()

func _finish_endless(reason := "") -> void:
	fail_reason = reason
	state = State.FAILED
	result_time = 0.0
	ctrl.reset()
	music.stop()
	voice.stop()
	sfx("back")

	var rec_res := save.record_endless(endless_score, player_dist, correct, best_combo)
	var new_best: bool = bool(rec_res.get("new_high_score", false))
	last_points = int(endless_score / 40.0) + correct * 3
	save.add_points(last_points)
	_persist_progress()

	if correct >= 10: check_achievement("endless_runner")
	if correct >= 30: check_achievement("endless_survivor")
	if player_dist >= 1000.0: check_achievement("endless_marathon")

	lbl_result_heading.text = I18n.t("TITLE_ENDLESS_FINISH", "極限挑戰結束")
	var grade := "C"
	var grade_col := Color(0.65, 0.72, 0.85)
	if endless_score >= 15000:
		grade = "S+"
		grade_col = Color(1.0, 0.85, 0.2)
	elif endless_score >= 10000:
		grade = "S"
		grade_col = Color(1.0, 0.85, 0.2)
	elif endless_score >= 6000:
		grade = "A"
		grade_col = Color(0.1, 0.95, 1.0)
	elif endless_score >= 3000:
		grade = "B"
		grade_col = Color(1.0, 0.45, 0.85)

	lbl_rank.text = grade
	lbl_rank.add_theme_color_override("font_color", grade_col)
	var sb := rank_box.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.border_color = grade_col

	rank_box.scale = Vector2(2.2, 2.2)
	rank_box.pivot_offset = rank_box.custom_minimum_size * 0.5
	rank_box.modulate.a = 0.0
	var rkt := create_tween()
	rkt.tween_interval(0.08)
	rkt.tween_property(rank_box, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rkt.parallel().tween_property(rank_box, "modulate:a", 1.0, 0.15)

	lbl_result.text = I18n.t("ENDLESS_RESULT_STATS", "★ 無盡極限挑戰 ★\n\n最終得分 %d%s\n突破波次 WAVE %d　奔馳距離 %.1f 公尺\n答對 %d 題　最佳連擊 %d\n獲得點數 +%d（總點數 %d）\n\n★ 歷史最高分：%d 分") % [
		endless_score,
		I18n.t("ENDLESS_RESULT_NEW_BEST", "（新紀錄！）") if new_best else "",
		endless_tier + 1,
		player_dist,
		correct,
		best_combo,
		last_points,
		save.points(),
		save.get_endless_best_score()
	]

	res_badge.visible = new_best
	res_chip_stage.text = "★ %s · SURVIVAL" % I18n.t("BTN_ENDLESS", "無盡挑戰")
	lbl_card_time_val.text = "%d 分" % endless_score
	lbl_card_time_sub.text = "★ 歷史最高分：%d 分" % save.get_endless_best_score()
	lbl_card_acc_val.text = "WAVE %d" % (endless_tier + 1)
	lbl_card_acc_sub.text = "奔馳距離 %.1f 公尺" % player_dist
	lbl_card_combo_val.text = "%d 題正解" % correct
	lbl_card_combo_sub.text = "最佳連擊 %d 連擊" % best_combo
	lbl_card_pts_val.text = "+%d 點" % last_points
	lbl_card_pts_sub.text = "累計持有 %d 點" % save.points()
	res_weak_box.visible = false
	res_knowledge_box.visible = false
	for i in 3:
		var st_child := res_stars.get_child(i) as TextureRect
		st_child.visible = false

	lbl_center.text = ""
	lbl_hint.text = ""
	btn_next.visible = false
	btn_kata_next.visible = false
	btn_review.visible = false
	btn_retry.text = I18n.t("BTN_RETRY_DRILL", "再練一次") if is_drill else I18n.t("BTN_RETRY_ENDLESS", "再戰極限")
	btn_select.text = I18n.t("BTN_BACK_CHART", "回五十音表") if is_drill else I18n.t("BTN_SELECT", "回選關")
	if is_drill:
		lbl_result_heading.text = I18n.t("TITLE_DRILL_FINISH", "特訓完成")
	_refresh_save_notice()
	_layout_result_cards()
	pause_box.visible = false
	lbl_hint.visible = true
	touches.clear()
	results_box.visible = true
	btn_retry.grab_focus()

func play_kana_voice(romaji: String) -> void:
	var r := romaji
	if r == "di": r = "ji"
	elif r == "du": r = "zu"
	var clip: AudioStream = Assets.VOICE.get(r, null)
	if clip != null:
		voice.stream = clip
		voice.play()
	else:
		sfx("focus")

func _build_chart() -> void:
	var cp := _panel_center("panel_9slice")
	chart_box = cp[0]
	var chart_root: VBoxContainer = cp[1]
	chart_root.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = I18n.t("CHART_TITLE", "五十音圖表與自訂特訓")
	title.add_theme_font_override("font", Assets.FONT_HUD)
	title.add_theme_font_size_override("font_size", int(36 * UI))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(title)
	chart_root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = I18n.t("CHART_SUBTITLE", "點擊假名聆聽原生發音 · 自由組合弱點行段疾走特訓")
	subtitle.add_theme_font_override("font", Assets.FONT_HUD)
	subtitle.add_theme_font_size_override("font_size", int(16 * UI))
	subtitle.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ink(subtitle)
	chart_root.add_child(subtitle)

	chart_tabs_hbox = HBoxContainer.new()
	chart_tabs_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	chart_tabs_hbox.add_theme_constant_override("separation", 8)
	chart_root.add_child(chart_tabs_hbox)

	var tab_defs := [
		["hira", I18n.t("CHART_TAB_HIRA", "平假名")],
		["kata", I18n.t("CHART_TAB_KATA", "片假名")],
		["dakuon", I18n.t("CHART_TAB_DAKUON", "濁音/半濁音")],
		["youon", I18n.t("CHART_TAB_YOUON", "拗音")],
		["drill", I18n.t("CHART_TAB_DRILL", "★自訂特訓")]
	]
	chart_tab_buttons.clear()
	for td in tab_defs:
		var tb := _button(td[1])
		tb.custom_minimum_size = Vector2(90, 44) * UI
		tb.add_theme_font_size_override("font_size", int(15 * UI))
		_art_button(tb, "tab_active" if chart_tab == td[0] else "tab_inactive", 16)
		tb.pressed.connect(func():
			chart_tab = td[0]
			_refresh_chart_ui()
		)
		chart_tabs_hbox.add_child(tb)
		chart_tab_buttons[td[0]] = tb

	chart_scroll = ScrollContainer.new()
	chart_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chart_scroll.follow_focus = true
	chart_root.add_child(chart_scroll)

	chart_content = VBoxContainer.new()
	chart_content.add_theme_constant_override("separation", 10)
	chart_scroll.add_child(chart_content)

	btn_chart_back = _button(I18n.t("BTN_SETTINGS_BACK", "返回"))
	_art_button(btn_chart_back, "btn_secondary", 32)
	btn_chart_back.custom_minimum_size = Vector2(440, 52) * UI
	btn_chart_back.add_theme_font_size_override("font_size", int(22 * UI))
	btn_chart_back.pressed.connect(hide_chart)
	chart_root.add_child(btn_chart_back)

	get_viewport().size_changed.connect(_layout_chart)
	chart_box.visible = false

func _layout_chart() -> void:
	if not is_instance_valid(chart_scroll):
		return
	var view := get_viewport().get_visible_rect().size
	var insets: Dictionary = get_safe_insets()
	var w: float = minf(540.0 * UI, view.x - 60.0 * UI - float(insets.left) - float(insets.right))
	chart_scroll.custom_minimum_size.x = w
	chart_scroll.custom_minimum_size.y = clampf(view.y - 250.0 * UI - float(insets.top) - float(insets.bottom), 120.0, 520.0 * UI)
	if is_instance_valid(btn_chart_back):
		btn_chart_back.custom_minimum_size.x = minf(440.0 * UI, w)

func show_chart(tab := "") -> void:
	if tab != "":
		chart_tab = tab
	select_box.visible = false
	settings_box.visible = false
	pause_box.visible = false
	if shop_box != null: shop_box.visible = false
	if achievements_box != null: achievements_box.visible = false
	if endless_box != null: endless_box.visible = false
	if title_box != null: title_box.visible = false
	if chart_box != null:
		chart_box.visible = true
	_refresh_chart_ui()
	_layout_chart()
	_update_pad_bar()
	_update_title_prompts()
	if chart_tab_buttons.has(chart_tab) and is_instance_valid(chart_tab_buttons[chart_tab]):
		chart_tab_buttons[chart_tab].grab_focus()

func hide_chart() -> void:
	if chart_box != null:
		chart_box.visible = false
	if state == State.TITLE:
		show_title()
		if is_instance_valid(btn_title_chart):
			btn_title_chart.grab_focus()
	else:
		show_select()
		if is_instance_valid(btn_chart):
			btn_chart.grab_focus()

func _refresh_chart_ui() -> void:
	if not is_instance_valid(chart_content):
		return
	for c in chart_content.get_children():
		chart_content.remove_child(c)
		c.queue_free()

	# Update tab buttons
	for t_id in chart_tab_buttons:
		var btn: Button = chart_tab_buttons[t_id]
		if is_instance_valid(btn):
			var active: bool = (chart_tab == t_id)
			_art_button(btn, "tab_active" if active else "tab_inactive", 16)
			btn.button_pressed = active

	if chart_tab in ["hira", "kata", "dakuon", "youon"]:
		_render_chart_table(chart_tab)
	elif chart_tab == "drill":
		_render_drill_panel()

func _render_chart_table(tab: String) -> void:
	var rows_data: Array = []
	match tab:
		"hira": rows_data = CHART_HIRA_SEION
		"kata": rows_data = CHART_KATA_SEION
		"dakuon": rows_data = CHART_DAKUON
		"youon": rows_data = CHART_YOUON

	# Column headers
	var legend_lbl := Label.new()
	legend_lbl.text = I18n.t("CHART_LEGEND", "● 精通反射 (<0.9s)   ● 學習中   ● 易錯/偏慢")
	legend_lbl.add_theme_font_override("font", Assets.FONT_HUD)
	legend_lbl.add_theme_font_size_override("font_size", int(14 * UI))
	legend_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95))
	legend_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chart_content.add_child(legend_lbl)

	var head_hbox := HBoxContainer.new()
	head_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	head_hbox.add_theme_constant_override("separation", 6)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(65 * UI, 24 * UI)
	head_hbox.add_child(spacer)

	var cols: Array = ["a", "i", "u", "e", "o"] if tab != "youon" else ["a", "u", "o"]
	for c_name in cols:
		var c_lbl := Label.new()
		c_lbl.text = c_name
		c_lbl.add_theme_font_override("font", Assets.FONT_HUD)
		c_lbl.add_theme_font_size_override("font_size", int(16 * UI))
		c_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
		c_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c_lbl.custom_minimum_size = Vector2((58.0 if tab != "youon" else 85.0) * UI, 24 * UI)
		head_hbox.add_child(c_lbl)
	chart_content.add_child(head_hbox)

	for row_entry in rows_data:
		var r_name: String = row_entry[0]
		var kana_list: Array = row_entry[1]

		var row_hbox := HBoxContainer.new()
		row_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		row_hbox.add_theme_constant_override("separation", 6)

		var r_lbl := Label.new()
		r_lbl.text = r_name
		r_lbl.add_theme_font_override("font", Assets.FONT_HUD)
		r_lbl.add_theme_font_size_override("font_size", int(15 * UI))
		r_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		r_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r_lbl.custom_minimum_size = Vector2(65 * UI, 50 * UI)
		row_hbox.add_child(r_lbl)

		var cell_w: float = (58.0 if tab != "youon" else 85.0) * UI
		for cell in kana_list:
			var k: String = cell[0]
			var r: String = cell[1]
			if k == "":
				var empty_box := Control.new()
				empty_box.custom_minimum_size = Vector2(cell_w, 50 * UI)
				row_hbox.add_child(empty_box)
			else:
				var cell_btn := _button("%s\n%s" % [k, r])
				cell_btn.add_theme_font_size_override("font_size", int(16 * UI))
				cell_btn.custom_minimum_size = Vector2(cell_w, 50 * UI)
				_art_button(cell_btn, "btn_secondary", 16)
				var tier: String = save.get_kana_tier(k)
				var tier_col: Color = Color(0.9, 0.95, 1.0)
				match tier:
					"mastered": tier_col = Color(0.25, 0.98, 0.45)
					"learning": tier_col = Color(1.0, 0.88, 0.30)
					"weak": tier_col = Color(1.0, 0.38, 0.38)
				cell_btn.add_theme_color_override("font_color", tier_col)
				cell_btn.add_theme_color_override("font_hover_color", tier_col.lightened(0.2))
				cell_btn.pressed.connect(play_kana_voice.bind(r))
				row_hbox.add_child(cell_btn)

		chart_content.add_child(row_hbox)

func _init_drill_defaults() -> void:
	if drill_selected_rows.is_empty():
		drill_selected_rows["あ行"] = true
		drill_selected_rows["か行"] = true
		drill_selected_rows["さ行"] = true

func _render_drill_panel() -> void:
	_init_drill_defaults()

	# Quick select row
	var q_row := HBoxContainer.new()
	q_row.alignment = BoxContainer.ALIGNMENT_CENTER
	q_row.add_theme_constant_override("separation", 6)
	chart_content.add_child(q_row)

	var q_configs := [
		["all", I18n.t("DRILL_QUICK_ALL", "全選")],
		["clear", I18n.t("DRILL_QUICK_CLEAR", "清空")],
		["hira", I18n.t("DRILL_QUICK_HIRA", "只選平假")],
		["kata", I18n.t("DRILL_QUICK_KATA", "只選片假")],
		["confuse", I18n.t("DRILL_QUICK_CONFUSABLE", "易混淆組")],
		["weak", I18n.t("DRILL_QUICK_WEAK", "★ 弱點急行軍")]
	]
	for qc in q_configs:
		var q_btn := _button(qc[1])
		q_btn.custom_minimum_size = Vector2(88, 40) * UI
		q_btn.add_theme_font_size_override("font_size", int(14 * UI))
		_art_button(q_btn, "btn_secondary", 16)
		q_btn.pressed.connect(_quick_select_drill.bind(qc[0]))
		q_row.add_child(q_btn)

	# Stats & Settings Box
	var settings_card := VBoxContainer.new()
	settings_card.add_theme_constant_override("separation", 8)
	chart_content.add_child(settings_card)

	lbl_drill_count = Label.new()
	lbl_drill_count.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_drill_count.add_theme_font_size_override("font_size", int(20 * UI))
	lbl_drill_count.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	lbl_drill_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_drill_counter()
	settings_card.add_child(lbl_drill_count)

	# Count & Mode Select Row
	var opts_row := HBoxContainer.new()
	opts_row.alignment = BoxContainer.ALIGNMENT_CENTER
	opts_row.add_theme_constant_override("separation", 8)
	settings_card.add_child(opts_row)

	var count_opts := [
		["short", I18n.t("DRILL_COUNT_SHORT", "短程(15)")],
		["mid", I18n.t("DRILL_COUNT_MID", "中程(25)")],
		["long", I18n.t("DRILL_COUNT_LONG", "長程(40)")],
		["endless", I18n.t("DRILL_COUNT_ENDLESS", "無盡")]
	]
	for co in count_opts:
		var c_btn := _button(co[1])
		c_btn.custom_minimum_size = Vector2(82, 42) * UI
		c_btn.add_theme_font_size_override("font_size", int(14 * UI))
		_art_button(c_btn, "tab_active" if drill_count_mode == co[0] else "btn_secondary", 16)
		c_btn.pressed.connect(func():
			drill_count_mode = co[0]
			_refresh_chart_ui()
		)
		opts_row.add_child(c_btn)

	var mode_opts := [
		["race", I18n.t("DRILL_MODE_RACE", "賽車")],
		["step", I18n.t("DRILL_MODE_STEP", "點放")]
	]
	for mo in mode_opts:
		var m_btn := _button(mo[1])
		m_btn.custom_minimum_size = Vector2(76, 42) * UI
		m_btn.add_theme_font_size_override("font_size", int(14 * UI))
		_art_button(m_btn, "tab_active" if drill_speed_mode == mo[0] else "btn_secondary", 16)
		m_btn.pressed.connect(func():
			drill_speed_mode = mo[0]
			_refresh_chart_ui()
		)
		opts_row.add_child(m_btn)

	# Start Button
	btn_drill_start = _button(I18n.t("DRILL_BTN_START", "★ 開始自訂特訓！"))
	_art_button(btn_drill_start, "btn_primary", 32)
	btn_drill_start.custom_minimum_size = Vector2(400, 54) * UI
	btn_drill_start.add_theme_font_size_override("font_size", int(22 * UI))
	btn_drill_start.pressed.connect(start_custom_drill)
	settings_card.add_child(btn_drill_start)

	lbl_drill_warn = Label.new()
	lbl_drill_warn.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_drill_warn.add_theme_font_size_override("font_size", int(15 * UI))
	lbl_drill_warn.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	lbl_drill_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_drill_warn.visible = false
	settings_card.add_child(lbl_drill_warn)

	# Checkable Rows Section
	var R: Dictionary = cfg.get("kana_rows", {})

	# Hiragana Section
	var hira_head := Label.new()
	hira_head.text = "【平假名行段】"
	hira_head.add_theme_font_override("font", Assets.FONT_HUD)
	hira_head.add_theme_font_size_override("font_size", int(17 * UI))
	hira_head.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	chart_content.add_child(hira_head)

	for r_entry in CHART_HIRA_SEION + CHART_DAKUON.slice(0, 5) + CHART_YOUON.slice(0, 11):
		var r_name: String = r_entry[0]
		if not R.has(r_name): continue
		_add_drill_row_button(r_name, R[r_name])

	# Katakana Section
	var kata_head := Label.new()
	kata_head.text = "【片假名行段】"
	kata_head.add_theme_font_override("font", Assets.FONT_HUD)
	kata_head.add_theme_font_size_override("font_size", int(17 * UI))
	kata_head.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	chart_content.add_child(kata_head)

	for r_entry in CHART_KATA_SEION + CHART_DAKUON.slice(5) + CHART_YOUON.slice(11):
		var r_name: String = r_entry[0]
		if not R.has(r_name): continue
		_add_drill_row_button(r_name, R[r_name])

func _add_drill_row_button(r_name: String, pairs: Array) -> void:
	var sample := ""
	for i in mini(5, pairs.size()):
		sample += pairs[i][0] + " "
	var is_chk: bool = drill_selected_rows.get(r_name, false)
	var row_btn := _button("%s  %s: %s" % ["[✓]" if is_chk else "[  ]", r_name, sample.strip_edges()])
	row_btn.custom_minimum_size = Vector2(400, 44) * UI
	row_btn.add_theme_font_size_override("font_size", int(16 * UI))
	row_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_art_button(row_btn, "tab_active" if is_chk else "btn_secondary", 16)
	row_btn.pressed.connect(func():
		drill_selected_rows[r_name] = not drill_selected_rows.get(r_name, false)
		var now_chk: bool = drill_selected_rows[r_name]
		row_btn.text = "%s  %s: %s" % ["[✓]" if now_chk else "[  ]", r_name, sample.strip_edges()]
		_art_button(row_btn, "tab_active" if now_chk else "btn_secondary", 16)
		_update_drill_counter()
		if lbl_drill_warn != null: lbl_drill_warn.visible = false
	)
	chart_content.add_child(row_btn)

func _calc_drill_pool_size() -> int:
	var count := 0
	var R: Dictionary = cfg.get("kana_rows", {})
	var seen := {}
	for r_name in drill_selected_rows:
		if drill_selected_rows.get(r_name, false):
			for pair in R.get(r_name, []):
				if not seen.has(pair[0]) and LevelDB.has_voice(pair[1]):
					seen[pair[0]] = true
					count += 1
	return count

func _update_drill_counter() -> void:
	if lbl_drill_count == null or not is_instance_valid(lbl_drill_count):
		return
	var c := _calc_drill_pool_size()
	lbl_drill_count.text = I18n.t("DRILL_SELECTED_COUNT", "已選取 %d 個假名") % c

func _quick_select_drill(mode: String) -> void:
	var R: Dictionary = cfg.get("kana_rows", {})
	match mode:
		"all":
			for r in R: drill_selected_rows[r] = true
		"clear":
			for r in R: drill_selected_rows[r] = false
		"hira":
			for r in R:
				var first_k: String = R[r][0][0]
				var code: int = first_k.unicode_at(0)
				drill_selected_rows[r] = (code >= 0x3040 and code <= 0x309F)
		"kata":
			for r in R:
				var first_k: String = R[r][0][0]
				var code: int = first_k.unicode_at(0)
				drill_selected_rows[r] = (code >= 0x30A0 and code <= 0x30FF)
		"confuse":
			for r in R: drill_selected_rows[r] = false
			for r in ["あ行", "か行", "さ行", "な行", "は行", "わ行", "サ行", "ア行", "タ行"]:
				if R.has(r): drill_selected_rows[r] = true
		"weak":
			var weak_kana: Array = save.get_weakest_kana(5)
			if weak_kana.is_empty():
				for r in R: drill_selected_rows[r] = false
				for r in ["あ行", "か行", "さ行"]:
					if R.has(r): drill_selected_rows[r] = true
				_notice(I18n.t("NOTICE_NO_WEAK_DATA", "尚無弱點紀錄，推薦基礎練習組！"))
			else:
				for r in R: drill_selected_rows[r] = false
				for r in R:
					for pair in R[r]:
						if weak_kana.has(pair[0]):
							drill_selected_rows[r] = true
							break
				_notice(I18n.t("NOTICE_WEAK_SELECTED", "★ 已鎖定個人弱點行：%s") % "、".join(weak_kana))
	_refresh_chart_ui()

func start_custom_drill() -> void:
	_end_tutorial()
	var pool: Array = []
	var R: Dictionary = cfg.get("kana_rows", {})
	for r_name in drill_selected_rows:
		if drill_selected_rows.get(r_name, false):
			for pair in R.get(r_name, []):
				var k: String = pair[0]
				if not pool.has(k) and LevelDB.has_voice(pair[1]):
					pool.append(k)
	if pool.size() < 3:
		if lbl_drill_warn != null and is_instance_valid(lbl_drill_warn):
			lbl_drill_warn.text = I18n.t("DRILL_NEED_3_KANA", "請至少選取 3 個假名以進行特訓！")
			lbl_drill_warn.visible = true
		sfx("ng")
		return
	if chart_box != null:
		chart_box.visible = false
	select_box.visible = false
	is_drill = true
	is_endless = (drill_count_mode == "endless")
	set_speed_mode(drill_speed_mode, false)
	
	var rm := LevelDB.romaji_map(cfg)
	var tgt_count: int = 999999 if is_endless else (15 if drill_count_mode == "short" else (25 if drill_count_mode == "mid" else 40))
	lvl = {
		"id": "drill",
		"name": I18n.t("LEVEL_CUSTOM_DRILL", "自訂假名特訓"),
		"type": "endless" if is_endless else "normal",
		"script": "custom",
		"target_correct": tgt_count,
		"time_limit_s": 999999.0 if is_endless else float(tgt_count * 5.0),
		"wrong_penalty_s": 1.5,
		"miss_penalty_s": 1.0,
		"voice_locked": false,
		"kana": pool,
		"romaji": pool.map(func(k): return rm.get(k, "")),
		"review_kana": []
	}
	level_id = "drill"
	hint_first_n = 2
	hint_ratio = 0.25
	var HP: Dictionary = cfg.get("hp", {})
	base_max_hp = maxi(1, int(HP.get("max_hp", 100)))
	wrong_damage = 30
	miss_damage = 10
	damage_reduction = 0.0
	shield_thresholds = []
	boss_shield_up = false
	_apply_bgm()
	fade_transition(func():
		reset_run()
	, 0.2, 0.2)

func start_daily_run() -> void:
	_end_tutorial()
	if chart_box != null: chart_box.visible = false
	if endless_box != null: endless_box.visible = false
	select_box.visible = false
	is_daily = true
	is_endless = false
	is_drill = false

	var today := Time.get_date_string_from_system()
	var seed_val: int = int(abs(today.hash()))
	var drng := RandomNumberGenerator.new()
	drng.seed = seed_val

	var all_rows: Array = cfg.get("kana_rows", {}).keys()
	var r1: String = all_rows[drng.randi_range(0, all_rows.size() - 1)]
	var r2: String = all_rows[drng.randi_range(0, all_rows.size() - 1)]
	while r2 == r1 and all_rows.size() > 1:
		r2 = all_rows[drng.randi_range(0, all_rows.size() - 1)]

	var pool := LevelDB.pool_for_rows(cfg, [r1, r2])
	if pool.size() < 3:
		pool = ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ"]
	var rm := LevelDB.romaji_map(cfg)

	lvl = {
		"id": "daily",
		"name": I18n.t("DAILY_LEVEL_TITLE", "今日特快 · %s") % today,
		"type": "normal",
		"script": "mixed",
		"target_correct": 20,
		"time_limit_s": 50.0,
		"star3_s": 32.0,
		"star2_s": 42.0,
		"wrong_penalty_s": 2.0,
		"miss_penalty_s": 1.0,
		"voice_locked": false,
		"kana": pool,
		"romaji": pool.map(func(k): return rm.get(k, "")),
		"review_kana": []
	}
	level_id = "daily"
	hint_first_n = 2
	hint_ratio = 0.35
	var HP: Dictionary = cfg.get("hp", {})
	base_max_hp = maxi(1, int(HP.get("max_hp", 100)))
	wrong_damage = 35
	miss_damage = 0
	damage_reduction = 0.0
	shield_thresholds = []
	boss_shield_up = false
	_apply_bgm()
	fade_transition(func():
		reset_run()
	, 0.2, 0.2)


func _layout_select_scroll() -> void:
	var view := get_viewport().get_visible_rect().size
	var short_side := minf(view.x, view.y)
	var insets: Dictionary = get_safe_insets()
	var footer_height := maxf(90.0, short_side * 0.113)
	if is_instance_valid(select_scroll):
		select_scroll.custom_minimum_size.y = maxf(140.0, view.y - 620.0 * UI - (footer_height - 90.0) - float(insets.top) - float(insets.bottom))
	if not is_instance_valid(btn_tutorial) or not btn_tutorial.is_inside_tree():
		return
	var font_size := roundi(short_side * 0.034)
	var compact := font_size * 9.0 + 64.0 > btn_tutorial.custom_minimum_size.x
	btn_tutorial.text = I18n.t("BTN_TUTORIAL_COMPACT", "新手練習\n3 題") if compact else I18n.t("BTN_TUTORIAL", "新手練習 · 3 題")
	btn_settings.text = (I18n.t("SETTINGS_BTN_COMPACT", "設定\n%s模式") if compact else I18n.t("SETTINGS_BTN", "設定（%s模式）")) % mode_name()
	if is_instance_valid(btn_to_title):
		btn_to_title.text = I18n.t("BTN_TO_TITLE", "回主畫面")
	for button in [btn_tutorial, btn_settings, btn_to_title]:
		if button != null and is_instance_valid(button):
			button.custom_minimum_size.y = footer_height
			button.add_theme_font_size_override("font_size", font_size)

## Touch buttons scale with the short side of the (stretched) canvas so they stay
## comfortably large in portrait and landscape.
func _layout_touch() -> void:
	# The new layout defines a new base position, independent of an active shake.
	_set_hp_shake(0.0)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var ins: Dictionary = get_safe_insets()
	var inl: float = float(ins.left)
	var inr: float = float(ins.right)
	var intop: float = float(ins.top)
	var inb: float = float(ins.bottom)

	var m := minf(vs.x, vs.y)
	var a := m * 0.28      # accel  (art 320x250 incl. shadow)
	var b := m * 0.24      # brake
	var t := m * 0.13      # pause / voice
	var g := m * 0.035     # margin
	var ah := a * 250.0 / 320.0
	var bh := b * 250.0 / 320.0
	# Run status follows the sides. Only the question cue occupies the upper centre.
	_place_px(timer_panel, 0, 0, 0, 0, g + inl, g + intop, g + inl + m * 0.365, intop + m * 0.118)
	_place_px(lbl_count, 0, 0, 0, 0, g + inl + m * 0.01, intop + m * 0.12, g + inl + m * 0.365, intop + m * 0.206)
	_place_px(hearts_box, 0, 0, 0, 0, g + inl, intop + m * 0.207, g + inl + m * 0.365, intop + m * 0.294)
	_place_px(shield_box, 0, 0, 0, 0, g + inl, intop + m * 0.305, g + inl + m * 0.365, intop + m * 0.388)
	_place_px(combo_badge, 1, 0, 1, 0, -g - inr - m * 0.24, intop + m * 0.332, -g - inr, intop + m * 0.410)
	_place_px(lbl_hint, 0.5, 0, 0.5, 0, -m * 0.11, intop + m * 0.074, m * 0.11, intop + m * 0.204)
	_place_px(lbl_notice, 0.5, 0, 0.5, 0, -m * 0.16, intop + m * 0.225, m * 0.16, intop + m * 0.299)
	_place_px(lbl_float, 0.5, 0, 0.5, 0, m * 0.115, intop + m * 0.163, m * 0.315, intop + m * 0.222)
	_place_px(go_box, 0.5, 0, 0.5, 0, m * 0.127, intop + m * 0.050, m * 0.227, intop + m * 0.150)
	_place_px(judge, 0.5, 0, 0.5, 0, m * 0.132, intop + m * 0.055, m * 0.222, intop + m * 0.145)
	judge.pivot_offset = judge.size * 0.5
	for style in [[lbl_time, 0.04], [lbl_count, 0.051], [lbl_hp, 0.034], [lbl_shield, 0.028],
			[lbl_boss, 0.034], [lbl_combo, 0.038], [lbl_hint, 0.083], [lbl_notice, 0.037], [lbl_float, 0.031],
			[go_box.get_child(0), 0.041], [ready_title, 0.051], [lbl_center, 0.040], [ready_knowledge, 0.033]]:
		style[0].add_theme_font_size_override("font_size", roundi(m * style[1]))
	for label in [ready_title, lbl_center, ready_knowledge]:
		label.custom_minimum_size.x = m * 0.77

	_place_px(btn_accel, 1, 1, 1, 1, -g - inr - a, -g - inb - ah, -g - inr, -g - inb)
	_place_px(btn_brake, 0, 1, 0, 1, g + inl, -g - inb - bh, g + inl + b, -g - inb)
	var sw := m * 0.30; var sh := sw * 130.0 / 240.0
	_place_px(speedo, 0.5, 1, 0.5, 1, -sw * 0.5, -g - inb - sh, sw * 0.5, -g - inb)
	speedo_needle.size = Vector2(12, 44) * (sh / 130.0)
	speedo_needle.pivot_offset = Vector2(speedo_needle.size.x * 0.5, speedo_needle.size.y * 0.9)
	# Dial centre in the 240 × 130 speedometer artwork.
	speedo_needle.position = Vector2(sw * 69.0 / 240.0, sh * 65.0 / 130.0) - speedo_needle.pivot_offset
	_place_px(lbl_speed, 0.43, 0, 1, 1, 0, 0, -sw * 0.055, -sh * 0.08)
	lbl_speed.add_theme_font_size_override("font_size", maxi(12, int(sh * 0.2)))
	lbl_speed.clip_text = true
	var lw := m * 0.18; var lh := lw * 130.0 / 160.0
	var lock_bottom := -g - inb - ah - g * 0.5
	_place_px(btn_lock, 1, 1, 1, 1, -g - inr - lw, lock_bottom - lh, -g - inr, lock_bottom)
	_place_px(btn_pause, 1, 0, 1, 0, -g - inr - t, g + intop, -g - inr, g + intop + t * 158.0 / 148.0)
	_place_px(btn_voice, 1, 0, 1, 0, -g - inr - t, g + intop + t + g * 0.6, -g - inr, g + intop + t + g * 0.6 + t)
	for p in [btn_accel, btn_brake, btn_lock, btn_pause, btn_voice]:
		var lab: Label = p.get_child(0)
		var label_scale := 0.17
		if p == btn_lock:
			label_scale = 0.23
		elif p == btn_voice:
			label_scale = 0.26
		lab.add_theme_font_size_override("font_size", maxi(12, roundi(p.size.y * label_scale)))
	lbl_lock_kmh.add_theme_font_size_override("font_size", maxi(10, int(lh * 0.26)))
	if pad_bar != null and is_instance_valid(pad_bar):
		_place_px(pad_bar, 0, 1, 1, 1, inl + m * 0.25, -inb - m * 0.048, -inr - m * 0.25, -inb - m * 0.008)
		pad_bar.add_theme_font_size_override("font_size", roundi(m * 0.030))

func show_select() -> void:
	_end_tutorial()
	is_endless = false
	is_drill = false
	is_daily = false
	if chart_box != null:
		chart_box.visible = false
	if title_box != null:
		title_box.visible = false
	if endless_box != null:
		endless_box.visible = false
	if shop_box != null:
		shop_box.visible = false
	if achievements_box != null:
		achievements_box.visible = false
	settings_box.visible = false
	pause_box.visible = false
	review_box.visible = false
	_update_pad_bar()
	_update_title_prompts()
	voice.stream_paused = false
	voice.stop()
	music.stream_paused = false
	touches.clear()
	state = State.SELECT
	ctrl.reset()
	if music.playing:
		music.stop()
	results_box.visible = false
	lbl_center.text = ""
	lbl_hint.text = ""
	for c in select_list.get_children():
		select_list.remove_child(c)
		c.queue_free()
	level_buttons.clear()
	var insets: Dictionary = get_safe_insets()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var landscape := vs.x >= vs.y
	var available_w: float = vs.x - 48.0 - float(insets.left) - float(insets.right)
	var w: float = clampf(available_w * 0.54, 760.0, 960.0) if landscape else clampf(available_w, 640.0, 840.0)

	if select_box != null and select_box.get_child_count() > 0:
		var pc := select_box.get_child(0) as PanelContainer
		if pc != null:
			var ssb := StyleBoxFlat.new()
			ssb.bg_color = Color(0.03, 0.04, 0.09, 0.95)
			ssb.border_width_left = 2; ssb.border_width_top = 2; ssb.border_width_right = 2; ssb.border_width_bottom = 2
			ssb.border_color = Color(0.18, 0.85, 1.0, 0.65)
			ssb.set_corner_radius_all(14)
			ssb.set_content_margin_all(16)
			pc.add_theme_stylebox_override("panel", ssb)
			pc.custom_minimum_size.x = w

	var rank_info: Dictionary = save.get_player_rank()
	var daily_info: Dictionary = save.check_daily_status()

	# 1. Top HUD Profile Header Bar
	var top_hud := PanelContainer.new()
	var th_sb := StyleBoxFlat.new()
	th_sb.bg_color = Color(0.04, 0.06, 0.14, 0.95)
	th_sb.border_width_left = 2; th_sb.border_width_top = 2; th_sb.border_width_right = 2; th_sb.border_width_bottom = 2
	th_sb.border_color = Color(0.2, 0.85, 1.0, 0.55)
	th_sb.set_corner_radius_all(10)
	th_sb.set_content_margin_all(8)
	top_hud.add_theme_stylebox_override("panel", th_sb)
	top_hud.custom_minimum_size = Vector2(w, 54 * UI)
	select_list.add_child(top_hud)

	var th_hbox := HBoxContainer.new()
	th_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	th_hbox.add_theme_constant_override("separation", 16)
	top_hud.add_child(th_hbox)

	var lbl_rank := Label.new()
	lbl_rank.text = "◆ %s %s" % [rank_info.badge, rank_info.title]
	lbl_rank.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_rank.add_theme_font_size_override("font_size", int(18 * UI))
	lbl_rank.add_theme_color_override("font_color", rank_info.color)
	th_hbox.add_child(lbl_rank)

	var title := Label.new()
	title.text = "【 %s 】" % I18n.t("TITLE_SELECT", "任務選關 MISSION SELECT")
	title.add_theme_font_override("font", Assets.FONT_HUD)
	title.add_theme_font_size_override("font_size", int(20 * UI))
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	th_hbox.add_child(title)

	lbl_points = Label.new()
	lbl_points.text = I18n.t("POINTS_UNREADABLE", "讀不到紀錄") if save.unreadable else (I18n.t("POINTS_TOTAL", "◆ 總點數 %d") % save.points())
	if progress_pending:
		lbl_points.text += I18n.t("POINTS_PENDING", "・未存檔")
	lbl_points.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_points.add_theme_font_size_override("font_size", int(17 * UI))
	lbl_points.add_theme_color_override("font_color", Color(0.85, 0.55, 1.0))
	th_hbox.add_child(lbl_points)

	var lbl_streak := Label.new()
	lbl_streak.text = "★ %s %d %s" % [I18n.t("DAILY_STREAK_PRE", "連續"), daily_info.streak, I18n.t("DAILY_STREAK_POST", "天")]
	lbl_streak.add_theme_font_override("font", Assets.FONT_HUD)
	lbl_streak.add_theme_font_size_override("font_size", int(17 * UI))
	lbl_streak.add_theme_color_override("font_color", Color(1.0, 0.65, 0.2))
	th_hbox.add_child(lbl_streak)

	# 2. Featured Daily Challenge (btn_daily)
	btn_daily = _button(I18n.t("BTN_DAILY_RUN", "★ 今日特快 (獎勵 +100點)") if not daily_info.completed else I18n.t("BTN_DAILY_DONE", "★ 今日特快 (今日已達成 ★★★)"))
	_art_button(btn_daily, "btn_primary" if not daily_info.completed else "btn_secondary", 32)
	btn_daily.custom_minimum_size = Vector2(w, 52 * UI)
	btn_daily.add_theme_font_size_override("font_size", int(20 * UI))
	btn_daily.pressed.connect(start_daily_run)
	select_list.add_child(btn_daily)

	# 3. 4-Column Navigation Bar
	var nav_grid := GridContainer.new()
	nav_grid.columns = 4
	nav_grid.add_theme_constant_override("h_separation", 8)
	nav_grid.add_theme_constant_override("v_separation", 8)
	select_list.add_child(nav_grid)

	var nav_btn_w := (w - 24.0) / 4.0

	btn_chart = _button(I18n.t("BTN_CHART", "五十音・特訓"))
	_art_button(btn_chart, "btn_secondary", 32)
	btn_chart.custom_minimum_size = Vector2(nav_btn_w, 46 * UI)
	btn_chart.add_theme_font_size_override("font_size", int(16 * UI))
	btn_chart.pressed.connect(func(): show_chart())
	nav_grid.add_child(btn_chart)

	btn_endless = _button(I18n.t("BTN_ENDLESS", "★無盡挑戰"))
	_art_button(btn_endless, "btn_primary", 32)
	btn_endless.custom_minimum_size = Vector2(nav_btn_w, 46 * UI)
	btn_endless.add_theme_font_size_override("font_size", int(16 * UI))
	btn_endless.pressed.connect(show_endless)
	nav_grid.add_child(btn_endless)

	btn_shop = _button(I18n.t("BTN_SHOP", "改裝商城"))
	_art_button(btn_shop, "btn_secondary", 32)
	btn_shop.custom_minimum_size = Vector2(nav_btn_w, 46 * UI)
	btn_shop.add_theme_font_size_override("font_size", int(16 * UI))
	btn_shop.pressed.connect(show_shop)
	nav_grid.add_child(btn_shop)

	btn_achievements = _button(I18n.t("BTN_ACHIEVEMENTS", "成就獎章"))
	_art_button(btn_achievements, "btn_secondary", 32)
	btn_achievements.custom_minimum_size = Vector2(nav_btn_w, 46 * UI)
	btn_achievements.add_theme_font_size_override("font_size", int(16 * UI))
	btn_achievements.pressed.connect(show_achievements)
	nav_grid.add_child(btn_achievements)
	if progress_pending:
		var retry_save := _button(I18n.t("BTN_SAVE_RETRY", "重試存檔"))
		_art_button(retry_save, "btn_small", 32)
		retry_save.pressed.connect(_retry_save)
		select_list.add_child(retry_save)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	select_list.add_child(tabs)
	btn_tab_hira = _button(I18n.t("TAB_HIRA", "平假名")); btn_tab_kata = _button(I18n.t("TAB_KATA", "片假名"))
	var kata_open := false
	for i in levels.size():
		if levels[i].get("script") == "kata" and save.is_unlocked(levels, i):
			kata_open = true
			break
	for b in [btn_tab_hira, btn_tab_kata]:
		b.toggle_mode = true
		_art_button(b, "tab_inactive", 32)
		b.add_theme_stylebox_override("pressed", _tex_style("tab_active", 32))
		b.add_theme_stylebox_override("hover_pressed", _tex_style("tab_active", 32))
		b.custom_minimum_size = Vector2(w * 0.5 - 5, clampf(w * 0.5 * 110.0 / 470.0, 48.0 * UI, 64.0 * UI))
		b.add_theme_font_size_override("font_size", int(24 * UI))
		tabs.add_child(b)
	btn_tab_kata.disabled = not kata_open
	if btn_tab_kata.disabled:
		btn_tab_kata.text = I18n.t("TAB_KATA_LOCKED", "片假名（鎖定）")
		btn_tab_kata.add_theme_stylebox_override("disabled", _tex_style("tab_locked", 32))
	btn_tab_hira.button_pressed = select_tab == "hira"
	btn_tab_kata.button_pressed = select_tab == "kata"
	btn_tab_hira.pressed.connect(_select_kana_tab.bind("hira"))
	btn_tab_kata.pressed.connect(_select_kana_tab.bind("kata"))
	# Distance buttons choose the printed distance directly.
	var drow := HBoxContainer.new()
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	drow.add_theme_constant_override("separation", 10)
	select_list.add_child(drow)
	var distance_group := ButtonGroup.new()
	for d in cfg.get("distances", {}).get("order", ["short", "mid", "long"]):
		var db := _button(distance_name(d))
		_art_button(db, "dist_selected" if d == distance else "dist_unselected", 32)
		db.custom_minimum_size = Vector2(w / 3.0 - 8, clampf((w / 3.0) * 110.0 / 300.0, 46.0 * UI, 58.0 * UI))
		db.add_theme_font_size_override("font_size", int(22 * UI))
		db.toggle_mode = true
		db.button_group = distance_group
		db.button_pressed = d == distance
		if d == distance:
			btn_distance = db
		db.pressed.connect(_select_distance.bind(d))
		drow.add_child(db)
	select_scroll = ScrollContainer.new()
	select_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	select_scroll.follow_focus = true
	select_scroll.custom_minimum_size.x = w
	select_list.add_child(select_scroll)
	_layout_select_scroll()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_scroll.add_child(list)
	var zone := -1
	var first_scroll_target: Control = null
	for i in levels.size():
		var L: Dictionary = levels[i]
		if str(L.get("script", "hira")) != select_tab:
			continue
		if int(L.get("zone", 0)) != zone:
			zone = int(L.get("zone", 0))
			var zl := Label.new()
			zl.text = (I18n.t("ZONE_FORMAT", "第 %d 區") % zone) if zone > 0 else I18n.t("ZONE_FINAL", "最終關")
			zl.add_theme_font_override("font", Assets.FONT_HUD)
			zl.add_theme_font_size_override("font_size", int(26 * UI))
			_ink(zl)
			zl.add_theme_stylebox_override("normal", _tex_style("zone_header_%d" % clampi(zone, 1, 5) if zone > 0 else "zone_header_final", 32, 110))
			zl.custom_minimum_size = Vector2(w - 20, (w - 20) * 130.0 / 960.0)
			zl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			list.add_child(zl)
		var id := str(L.get("id"))
		var E := LevelDB.effective(cfg, levels, i, distance)
		var unlocked := _can_choose_level(i, E)
		var rec: Dictionary = save.get_record(id, distance)
		var txt := "      %s  ·  %d%s" % [str(L.get("name", id)), int(E.target_correct), I18n.t("QUESTIONS_UNIT", "題")]
		if bool(E.voice_locked):
			txt += "    " + I18n.t("STAGE_MISSING_VOICE", "缺語音")
		elif not unlocked:
			txt += "    " + I18n.t("STAGE_LOCKED", "◆ 鎖定")
		elif float(rec.get("best_time", -1.0)) >= 0.0:
			txt += "    %s  %.1fs" % [_stars_text(int(rec.get("best_stars", 0))), float(rec.best_time)]
		elif bool(rec.get("cleared", false)):
			txt += "    " + I18n.t("STAGE_CLEARED", "通過")
		var b := _button(txt)
		var typ := str(L.get("type", "normal"))
		var row_art := "stage_row_locked" if not unlocked else ("stage_row_boss" if typ != "normal" else ("stage_row_cleared" if save.cleared_any(id) else "stage_row_normal"))
		var rh := clampf((w - 20) * 125.0 / 960.0, 72.0 * UI, 96.0 * UI)
		_art_button(b, row_art, 40, rh * 0.85)
		b.add_theme_stylebox_override("pressed", _tex_style("stage_row_selected", 40, rh * 0.85))
		b.add_theme_stylebox_override("disabled", _tex_style("stage_row_locked", 40, rh * 0.85))
		b.custom_minimum_size = Vector2(w - 20, rh)
		b.add_theme_font_size_override("font_size", int(22 * UI))
		# kana badge (left 126x126 of the row) - Zen Maru label with glowing tile background
		var badge := Label.new()
		var rws: Array = L.get("rows", [])
		badge.text = "" if not unlocked else (str(rws[0]).substr(0, 1) if rws.size() > 0 and typ == "normal" else ("★" if typ != "normal" else ""))
		badge.add_theme_font_override("font", Art.FONT_KANA)
		badge.add_theme_font_size_override("font_size", int(rh * 0.44))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ink(badge)
		b.add_child(badge); _place_px(badge, 0, 0, 0, 1, rh * 0.06, 0, rh * 0.78, -rh * 0.06)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not unlocked
		b.pressed.connect(choose_level.bind(i))
		b.set_meta("level_index", i)
		list.add_child(b)
		level_buttons.append(b)
		if unlocked:
			first_scroll_target = b
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	select_list.add_child(footer)
	var f_btn_w := (w - 20.0) / 3.0
	var tutorial_recommended: bool = lane_count == 3 and save.data.levels.is_empty() and not bool(save.get_setting("tutorial_seen", false))
	btn_tutorial = _button("新手練習 · 3 題")
	_art_button(btn_tutorial, "btn_primary" if tutorial_recommended else "btn_secondary", 32)
	btn_tutorial.custom_minimum_size = Vector2(f_btn_w, 56 * UI)
	btn_tutorial.disabled = lane_count != 3
	btn_tutorial.pressed.connect(start_tutorial)
	footer.add_child(btn_tutorial)
	btn_settings = _button("")
	_art_button(btn_settings, "btn_secondary", 32)
	btn_settings.custom_minimum_size = Vector2(f_btn_w, 56 * UI)
	btn_settings.pressed.connect(show_settings)
	footer.add_child(btn_settings)
	btn_to_title = _button(I18n.t("BTN_TO_TITLE", "回主畫面"))
	_art_button(btn_to_title, "btn_secondary", 32)
	btn_to_title.custom_minimum_size = Vector2(f_btn_w, 56 * UI)
	btn_to_title.add_theme_font_size_override("font_size", int(18 * UI))
	btn_to_title.pressed.connect(func():
		fade_transition(func(): show_title(), 0.2, 0.2)
	)
	footer.add_child(btn_to_title)
	_refresh_mode_buttons()
	select_box.visible = true
	if tutorial_recommended:
		btn_tutorial.grab_focus()
	elif first_scroll_target != null:
		first_scroll_target.grab_focus()
		select_scroll.ensure_control_visible.call_deferred(first_scroll_target)
	else:
		(btn_tab_kata if select_tab == "kata" else btn_tab_hira).grab_focus()

func _select_kana_tab(tab: String) -> void:
	if tab == "kata" and btn_tab_kata.disabled:
		return
	if select_tab != tab:
		sfx("tab", 1.0, -2.0)
	select_tab = tab
	show_select()
	(btn_tab_kata if tab == "kata" else btn_tab_hira).grab_focus()

func _select_distance(d: String) -> void:
	if distance != d:
		set_distance(d)
		show_select()
		btn_distance.grab_focus()

func choose_level(i: int) -> void:
	if not _can_choose_level(i):
		return
	is_endless = false
	is_daily = false
	is_drill = false
	_end_tutorial()
	fade_transition(func():
		select_box.visible = false
		set_level(i)
		reset_run()
	, 0.18, 0.18)

func go_next_level() -> void:
	if can_go_next():
		choose_level(level_index + 1)

func can_go_next() -> bool:
	return _can_choose_level(level_index + 1)

func _can_choose_level(i: int, effective := {}) -> bool:
	if not save.is_unlocked(levels, i):
		return false
	if effective.is_empty():
		effective = LevelDB.effective(cfg, levels, i, distance)
	return not bool(effective.voice_locked)

func is_tutorial_active() -> bool:
	return tutorial_step >= 0

func start_tutorial() -> void:
	if lane_count != 3:
		return
	is_endless = false
	tutorial_step = 0
	reset_run()

func _end_tutorial() -> void:
	if not is_tutorial_active():
		return
	tutorial_step = -1
	_refresh_tutorial()
	if not bool(save.get_setting("tutorial_seen", false)):
		save.set_setting("tutorial_seen", true)
		_persist_progress()

func _continue_from_tutorial() -> void:
	if _can_choose_level(0):
		choose_level(0)
	else:
		show_select()

func _build_tutorial_hud() -> void:
	tutorial_panel = PanelContainer.new()
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := _tex_style("panel_9slice", 44)
	panel_style.set_content_margin_all(24)
	tutorial_panel.add_theme_stylebox_override("panel", panel_style)
	hud.add_child(tutorial_panel)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 8)
	tutorial_panel.add_child(stack)
	lbl_tutorial_title = _label(28, HORIZONTAL_ALIGNMENT_CENTER)
	lbl_tutorial = _label(26, HORIZONTAL_ALIGNMENT_CENTER)
	for label in [lbl_tutorial_title, lbl_tutorial]:
		hud.remove_child(label)
		stack.add_child(label)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_ink(label)
	tutorial_actions = HBoxContainer.new()
	tutorial_actions.add_theme_constant_override("separation", 12)
	stack.add_child(tutorial_actions)
	var back := _button("回選關")
	_art_button(back, "btn_secondary", 32)
	back.pressed.connect(show_select)
	btn_tutorial_continue = _button("開始第一關")
	_art_button(btn_tutorial_continue, "btn_primary", 32)
	btn_tutorial_continue.pressed.connect(_continue_from_tutorial)
	for button in [back, btn_tutorial_continue]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tutorial_actions.add_child(button)
	tutorial_panel.hide()
	get_viewport().size_changed.connect(_layout_tutorial)

func _layout_tutorial() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var short_side := minf(viewport_size.x, viewport_size.y)
	var insets: Dictionary = get_safe_insets()
	var width := short_side * (0.68 if tutorial_actions.visible else 0.62)
	var anchor_y := 0.40 if tutorial_actions.visible else 0.0
	var top: float = 0.0 if tutorial_actions.visible else (short_side * 0.027 + float(insets.top))
	_place_px(tutorial_panel, 0.5, anchor_y, 0.5, anchor_y, -width * 0.5, top, width * 0.5, top)
	lbl_tutorial_title.add_theme_font_size_override("font_size", roundi(short_side * 0.045))
	lbl_tutorial.add_theme_font_size_override("font_size", roundi(short_side * 0.040))
	for button in tutorial_actions.get_children():
		button.custom_minimum_size = Vector2(0, short_side * 0.115)
		button.add_theme_font_size_override("font_size", roundi(short_side * 0.043))

func _refresh_tutorial(feedback := "") -> void:
	tutorial_panel.visible = is_tutorial_active() and state != State.PAUSED
	if not tutorial_panel.visible:
		return
	var complete := tutorial_step == TUTORIAL_ROWS.size()
	tutorial_actions.visible = complete
	if complete:
		lbl_tutorial_title.text = "練習完成"
		lbl_tutorial.text = "正式關卡會計時，也能重播。"
	else:
		lbl_tutorial_title.text = "新手練習 %d / %d · 不計時" % [tutorial_step + 1, TUTORIAL_ROWS.size()]
		lbl_tutorial.text = feedback if feedback != "" else TUTORIAL_ROWS[tutorial_step].prompt
		if tutorial_step == 0 and feedback == "":
			lbl_tutorial.text += "\n連按加速鍵或空白鍵來提速。" if speed_mode == "step" else "\n按住加速鍵或空白鍵。"
	_layout_tutorial()

func _resolve_tutorial(row: Dictionary, hit: int) -> void:
	var needs_replay := tutorial_step == TUTORIAL_ROWS.size() - 1 and not tutorial_replayed
	var feedback := ""
	if needs_replay:
		feedback = "先按「重播」或 E。\n再撞上聽到的石碑。"
	elif hit == row.target:
		_fx_correct(row.stones[hit])
		tutorial_step += 1
	else:
		feedback = "對應的字是「%s」。\n跟著聲音再試一次。" % row.kana[row.target]
	if tutorial_step == TUTORIAL_ROWS.size():
		check_achievement("tutorial_done")
		state = State.SELECT
		result_time = 0.0
		ctrl.reset()
		touches.clear()
		voice.stop()
		_refresh_tutorial()
		btn_tutorial_continue.grab_focus()
		return
	_refresh_tutorial(feedback)
	_spawn_rows()
	_activate_next()

static func _stars_text(n: int) -> String:
	var t := ""
	for i in 3:
		t += "★" if i < n else "☆"
	return t

func _resolve_bgm() -> AudioStream:
	if is_endless:
		return Assets.MUSIC.get("hit")
	if lvl != null and lvl.has("music"):
		var m: String = str(lvl.music)
		if Assets.MUSIC.has(m):
			return Assets.MUSIC.get(m)
	if lvl != null:
		if lvl.get("type", "") == "boss" or level_id.ends_with("-BOSS") or level_id == "ULT":
			return Assets.MUSIC.get("ryu")
		if lvl.get("script", "") == "kata":
			return Assets.MUSIC.get("hosi")
	var fb: Dictionary = cfg.get("feedback", {})
	var def_m: String = str(fb.get("music", "res://audio/music/dash.mp3"))
	if Assets.MUSIC.has(def_m):
		return Assets.MUSIC.get(def_m)
	return Assets.MUSIC.get("dash")

func _apply_bgm() -> void:
	if music == null:
		return
	var target_stream := _resolve_bgm()
	var fb: Dictionary = cfg.get("feedback", {})
	var base_vol: float = float(fb.get("music_volume_db", -12.0))
	if target_stream == Assets.MUSIC.get("hosi"):
		base_vol += 2.0
	music.volume_db = base_vol
	if music.stream != target_stream:
		music.stream = target_stream

func _build_audio() -> void:
	voice = AudioStreamPlayer.new()
	voice.bus = &"Voice"
	add_child(voice)
	music = AudioStreamPlayer.new()
	music.bus = &"BGM"
	add_child(music)
	_apply_bgm()
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		sfx_pool.append(p)

func _apply_audio_volumes() -> void:
	_set_bus_vol("BGM", float(save.get_setting("vol_bgm", 0.8)))
	_set_bus_vol("SFX", float(save.get_setting("vol_sfx", 1.0)))
	_set_bus_vol("Voice", float(save.get_setting("vol_voice", 1.0)))

func _set_bus_vol(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, linear <= 0.01)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.01)))

func _vol_label(prefix: String, key: String, default_val: float) -> String:
	var v := float(save.get_setting(key, default_val))
	var pct := roundi(v * 100.0)
	var filled := roundi(v * 5.0)
	var meter := "■".repeat(filled) + "□".repeat(5 - filled)
	if v <= 0.01:
		return "%s: 靜音\n[□□□□□]" % prefix
	return "%s: %d%%\n[%s]" % [prefix, pct, meter]

func _update_vol_buttons() -> void:
	if btn_vol_bgm != null:
		btn_vol_bgm.text = _vol_label(I18n.t("VOL_MUSIC", "音樂"), "vol_bgm", 0.8)
	if btn_vol_sfx != null:
		btn_vol_sfx.text = _vol_label(I18n.t("VOL_SFX", "音效"), "vol_sfx", 1.0)
	if btn_vol_voice != null:
		btn_vol_voice.text = _vol_label(I18n.t("VOL_VOICE", "語音"), "vol_voice", 1.0)

func _cycle_vol(key: String, default_val: float) -> void:
	var v := float(save.get_setting(key, default_val))
	var next_v := 1.0
	if v >= 0.95:
		next_v = 0.8
	elif v >= 0.75:
		next_v = 0.6
	elif v >= 0.55:
		next_v = 0.4
	elif v >= 0.35:
		next_v = 0.2
	elif v >= 0.15:
		next_v = 0.0
	else:
		next_v = 1.0
	save.set_setting(key, next_v)
	_persist_progress()
	_apply_audio_volumes()
	_update_vol_buttons()
	if key == "vol_voice":
		sfx("tap")
		_play_kana("あ")
	else:
		sfx("tap")

func sfx(name: String, pitch := 1.0, vol := 0.0) -> void:
	var st: AudioStream = Assets.SFX.get(name)
	if st == null:
		return
	for p in sfx_pool:
		if not p.playing:
			p.stream = st
			p.pitch_scale = pitch
			p.volume_db = vol
			p.play()
			return

func _exit_tree() -> void:
	for p in [voice, music] + sfx_pool:
		if is_instance_valid(p):
			p.stop()
			p.stream = null

# ---------------------------------------------------------------- run
func reset_run() -> void:
	speedlines_intensity = 0.0
	if speedlines_mat != null:
		speedlines_mat.set_shader_parameter("intensity", 0.0)
	if hit_flash != null:
		hit_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	if hp_flash_tween != null:
		hp_flash_tween.kill()
	if hp_shake_tween != null:
		hp_shake_tween.kill()
	_set_hp_shake(0.0)
	hearts_box.modulate = Color.WHITE
	for r in rows:
		if is_instance_valid(r.node):
			r.node.queue_free()
	rows.clear()
	review_items.clear()
	review_box.visible = false
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	elapsed = 0.0; penalty = 0.0; shield_bonus = 0.0; correct = 0; wrong = 0; missed = 0
	endless_slow_timer = 0.0; endless_drain_tick = 0.0; runner_opacity = 1.0
	player_dist = 0.0; lane = 1; player_x = lane_x(lane); q_counter = 0
	question_draws.clear()
	ctrl.reset()
	next_row_dist = first_row
	appearances.clear(); requeue.clear(); voice_only_announced = false
	_set_combo(0); best_combo = 0
	fail_reason = ""
	shield = 0
	_apply_upgrades_from_save()
	max_hp = base_max_hp + max_hp_bonus
	hp = max_hp
	hp_delayed = float(hp); hp_delay_wait = 0.0
	shield_phase = 0; boss_shield_up = false; break_progress = 0; shields_broken = 0
	last_points = 0; last_record = {}; review_asked = 0
	lbl_boss.text = ""
	_emit_hp()
	lbl_hint.text = ""; lbl_notice.text = ""
	judge.modulate.a = 0.0
	if is_tutorial_active():
		tutorial_step = 0
		tutorial_replayed = false
	_spawn_rows()
	state = State.READY
	results_box.visible = false
	select_box.visible = false
	settings_box.visible = false
	pause_box.visible = false
	if shop_box != null:
		shop_box.visible = false
	if achievements_box != null:
		achievements_box.visible = false
	if endless_box != null:
		endless_box.visible = false
	lbl_hint.visible = true
	voice.stream_paused = false
	music.stream_paused = false
	touches.clear()
	var speed_help := I18n.t("HUD_SPEED_HELP_RACE", "按住加速／煞車（W／S）")
	if speed_mode == "step":
		var step := String.num(ctrl.step_size * 3.6, 2)
		speed_help = I18n.t("HUD_SPEED_HELP_STEP", "點加速 +%s／煞車 -%s km/h（W／S）") % [step, step]
	if is_endless:
		endless_score = 0
		endless_tier = 0
		ctrl.max_speed = 38.0 / 3.6
		row_spacing = 26.0
		miss_damage = 15
		wrong_damage = 30
		ready_title.text = "★ 無盡極限挑戰 ★\n生存極限・WAVE 1"
		ready_knowledge.text = "速度隨波次攀升，考驗即時聽辨反應！每 10 連擊恢復體力。"
	else:
		ready_title.text = "%s\n%s・%d 題" % [str(lvl.get("name", "Level 1")), distance_name(), int(lvl.target_correct)]
		ready_knowledge.text = str(lvl.get("knowledge", ""))
	lbl_center.text = I18n.t("HUD_CONTROLS_HELP", "%s\n滑動／← → 換線・E 重播\n點畫面或按空白鍵開始") % speed_help
	lbl_float.text = ""
	voice.stop()
	if music.playing:
		music.stop()
	# Refill the starting roadside after the previous run recycled its sprites.
	prop_rng.seed = 12345
	for key in next_prop:
		next_prop[key] = 0.0
	for prop in props:
		prop.hide()
	_update_view(0.0)
	_update_hud()
	if is_tutorial_active():
		start_run()

func start_run() -> void:
	state = State.RUNNING
	select_box.visible = false
	results_box.visible = false
	lbl_center.text = ""
	logger.start(level_id)
	if is_tutorial_active():
		_refresh_tutorial()
		_activate_next()
		_update_hud()
		return
	_apply_bgm()
	if music.stream:
		music.play()
	_go_pop()
	_activate_next()
	_update_hud()

## Roadside start stamp, separate from the question and lane view.
func _go_pop() -> void:
	if go_tween != null and go_tween.is_running():
		go_tween.kill()
	go_box.modulate.a = 1.0
	go_tween = create_tween()
	go_tween.tween_property(go_box, "modulate:a", 0.0, 0.18).set_delay(0.25)

## ○ / × stamp beside the pronunciation cue.
func _judge(ok: bool) -> void:
	if judge_tween != null and judge_tween.is_running():
		judge_tween.kill()
	judge.texture = Art.UI.judge_ok if ok else Art.UI.judge_ng
	judge.modulate.a = 1.0
	judge.scale = Vector2(1.1, 1.1)
	judge_tween = create_tween().set_parallel(true)
	judge_tween.tween_property(judge, "scale", Vector2.ONE, 0.10)
	judge_tween.tween_property(judge, "modulate:a", 0.0, 0.22).set_delay(0.17)

func clock() -> float:
	return maxf(0.0, elapsed + penalty - shield_bonus)

func _spawn_rows() -> void:
	if is_tutorial_active():
		if tutorial_step < TUTORIAL_ROWS.size() and active_row() == null:
			var example: Dictionary = TUTORIAL_ROWS[tutorial_step]
			_add_row(example.kana, example.target, player_dist + 26.0)
		return
	if bool(lvl.get("voice_locked", false)):
		return
	var pool: Array = lvl.get("kana", ["あ"])
	var review: Array = lvl.get("review_kana", [])
	while next_row_dist < player_dist + spawn_ahead:
		var r: Dictionary
		var is_review := false
		var from_requeue := not requeue.is_empty()
		if from_requeue:
			var t: String = requeue.pop_front()
			r = Rules.make_row_ex(pool if pool.has(t) else review, t, "", -1, rng, lane_count, lookalikes, same_sound)
			is_review = not pool.has(t)
		else:
			is_review = review.size() >= 2 and rng.randf() < review_ratio
			var source := review if is_review else pool
			var previous: String = "" if rows.is_empty() else rows.back().kana[rows.back().target]
			var target := Rules.balanced_target(source, question_draws, previous, rng)
			question_draws[target] = int(question_draws.get(target, 0)) + 1
			r = Rules.make_row_ex(source, target, "", -1, rng, lane_count, lookalikes, same_sound, pool if is_review else [])
		_add_row(r.kana, r.target, next_row_dist, is_review, from_requeue)
		next_row_dist += row_spacing

func _add_row(kana: Array, target: int, dist: float, is_review := false, from_requeue := false) -> void:
	var node := Node3D.new()
	node.position = Vector3(0, 0, -dist)
	add_child(node)
	var stones: Array = []
	for i in kana.size():
		var st := _make_stone(str(kana[i]))
		st.position = Vector3(lane_x(i), TABLET_H * 0.5, 0)
		node.add_child(st)
		stones.append(st)
	var row := {"dist": dist, "kana": kana, "target": target, "node": node,
		"stones": stones, "resolved": false, "voice_t": -1.0, "q": 0, "hint": false, "retry": false,
		"review": is_review, "from_requeue": from_requeue}
	_apply_row_labels(row)
	rows.append(row)

## Solid bevelled stone; labels and shield overlays sit in front of its face.
const TABLET_H := StoneTablet.HEIGHT
func _make_stone(k: String) -> MeshInstance3D:
	var st := MeshInstance3D.new()
	if stone_mesh == null:
		stone_mesh = StoneTablet.make_mesh()
		stone_material = ShaderMaterial.new()
		stone_material.shader = StoneTablet.SHADER
	st.mesh = stone_mesh
	st.material_override = stone_material
	var lab := Label3D.new()
	lab.name = "Kana"
	lab.font = Art.FONT_KANA
	lab.font_size = 160
	lab.pixel_size = 0.0074
	lab.outline_size = 14
	lab.modulate = Color("ffffff")
	lab.outline_modulate = Color("0d131e")
	# Keep the glyph in front of the tablet and shield at close range in Compatibility.
	lab.position = Vector3(0, -0.02, StoneTablet.FRONT + 0.035)
	lab.text = k
	st.add_child(lab)
	var ov := MeshInstance3D.new()
	ov.name = "ShieldOv"
	var oq := QuadMesh.new(); oq.size = Vector2(TABLET_H * 340.0 / 288.0, TABLET_H * 360.0 / 288.0)
	ov.mesh = oq
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.albedo_texture = Art.TABLET_SHIELD
	om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ov.material_override = om
	ov.position.z = StoneTablet.FRONT + 0.01
	ov.visible = false
	st.add_child(ov)
	var fx := Sprite3D.new()
	fx.name = "ShieldFx"
	fx.shaded = false
	fx.texture = Art.SHIELD.loop
	fx.hframes = 8
	fx.pixel_size = TABLET_H * 1.5 / 256.0
	fx.position.z = StoneTablet.FRONT + 0.02
	fx.visible = false
	st.add_child(fx)
	var focus_frame := MeshInstance3D.new()
	focus_frame.name = "FocusFrame"
	var focus_quad := QuadMesh.new(); focus_quad.size = Vector2(StoneTablet.WIDTH + 0.1, 0.09)
	focus_frame.mesh = focus_quad
	var focus_material := ShaderMaterial.new()
	focus_material.shader = preload("res://shaders/tablet_focus.gdshader")
	focus_frame.material_override = focus_material
	focus_frame.position = Vector3(0, -TABLET_H * 0.5 + 0.055, StoneTablet.FRONT + 0.025)
	focus_frame.visible = false
	st.add_child(focus_frame)
	return st

## Boss shield VFX: appear (8f) -> loop (8f) on the stones of rows ahead; hit (6f) / break (10f) one-shots. 24 fps.
var _shield_fx_t := 0.0
var _shield_fx_anim := ""
var _shield_was_up := false
func _shield_fx(anim: String) -> void:
	_shield_fx_anim = anim
	_shield_fx_t = 0.0

func _tick_shield_fx(dt: float) -> void:
	if not _shield_was_up and boss_shield_up:
		_shield_fx("appear")
	elif _shield_was_up and not boss_shield_up and state == State.RUNNING:
		_shield_fx("break")
	_shield_was_up = boss_shield_up
	_shield_fx_t += dt
	var frames := {"appear": 8, "loop": 8, "hit": 6, "break": 10}
	var f := int(_shield_fx_t * 24.0)
	if _shield_fx_anim != "" and _shield_fx_anim != "loop" and f >= int(frames[_shield_fx_anim]):
		_shield_fx_anim = "loop" if boss_shield_up else ""
		_shield_fx_t = 0.0; f = 0
	for r in rows:
		for st in r.stones:
			if not is_instance_valid(st): continue
			var fx: Sprite3D = st.get_node("ShieldFx")
			var on: bool = (boss_shield_up or _shield_fx_anim == "break") and not r.resolved and _shield_fx_anim != ""
			st.get_node("ShieldOv").visible = boss_shield_up and not r.resolved
			fx.visible = on
			if on:
				fx.texture = Art.SHIELD[_shield_fx_anim]
				fx.hframes = int(frames[_shield_fx_anim])
				fx.frame = (f % fx.hframes) if _shield_fx_anim == "loop" else mini(f, fx.hframes - 1)

func _apply_row_labels(row: Dictionary) -> void:
	for i in row.stones.size():
		var lab := row.stones[i].get_node("Kana") as Label3D
		lab.text = row.kana[i] if i < row.kana.size() else ""
		lab.font_size = 160 if lab.text.length() < 2 else 100

## Wrong hit: the next row becomes the same question with the correct kana in a different lane.
func _retry_in_next_row(after_row: Dictionary, kana: String, avoid_lane: int) -> void:
	var idx := rows.find(after_row)
	for j in range(idx + 1, rows.size()):
		var nxt: Dictionary = rows[j]
		if nxt.resolved or nxt.voice_t >= 0.0:
			continue
		var pool: Array = lvl.get("kana", ["あ"])
		var is_review := not pool.has(kana)
		var r := Rules.make_row_ex(lvl.get("review_kana", pool) if is_review else pool, kana, "", avoid_lane, rng, lane_count, lookalikes, same_sound)
		if nxt.from_requeue:
			requeue.push_front(nxt.kana[nxt.target])
		elif not nxt.retry:
			# This future question was reserved at spawn but never played.
			var displaced: String = nxt.kana[nxt.target]
			question_draws[displaced] = int(question_draws.get(displaced, 1)) - 1
		nxt.from_requeue = false
		nxt.kana = r.kana
		nxt.target = r.target
		nxt.retry = true
		nxt.review = is_review
		for st in nxt.stones:
			st.visible = false
		for ii in r.kana.size():
			if ii < nxt.stones.size():
				nxt.stones[ii].visible = true
		_apply_row_labels(nxt)
		return
	requeue.push_front(kana)

func active_row():
	for r in rows:
		if not r.resolved:
			return r
	return null

func _focus_row(row: Dictionary) -> void:
	for stone in row.stones:
		stone.get_node("FocusFrame").visible = true
		var glyph := stone.get_node("Kana") as Label3D
		glyph.modulate = Color("fff4d9")
		glyph.outline_size = 12

func _activate_next() -> void:
	var r = active_row()
	if r == null or r.voice_t >= 0.0:
		return
	q_counter += 1
	r.q = q_counter
	r.voice_t = elapsed
	_focus_row(r)
	if is_tutorial_active():
		play_voice(r)
		return
	var k: String = r.kana[r.target]
	if r.get("review", false):
		review_asked += 1
	var seen: int = appearances.get(k, 0)
	appearances[k] = seen + 1
	var progress := float(correct) / maxf(1.0, float(lvl.get("target_correct", 20)))
	r.hint = Rules.hint_visible(seen, hint_first_n, progress, hint_ratio)
	if progress >= hint_ratio and not voice_only_announced:
		voice_only_announced = true
		_notice(I18n.t("HUD_VOICE_ONLY", "聽音模式"))
	lbl_hint.text = _romaji(k) if r.hint else "?"
	lbl_hint.modulate.a = 1.0 if r.hint else 0.6
	play_voice(r)

var _romaji_cache := {}
func _romaji(k: String) -> String:
	if _romaji_cache.is_empty():
		_romaji_cache = LevelDB.romaji_map(cfg)
	return str(_romaji_cache.get(k, ""))

func _notice(t: String) -> void:
	if notice_tween != null and notice_tween.is_running():
		notice_tween.kill()
	lbl_notice.text = t
	lbl_notice.modulate.a = 1.0
	notice_tween = create_tween()
	notice_tween.tween_property(lbl_notice, "modulate:a", 0.0, 0.25).set_delay(1.3)

func _set_combo(v: int) -> void:
	var increased := v > combo and v >= 2
	combo = v
	best_combo = maxi(best_combo, combo)
	if combo >= 50: check_achievement("combo_50")
	elif combo >= 30: check_achievement("combo_30")
	elif combo >= 10: check_achievement("combo_10")
	lbl_combo.text = (I18n.t("HUD_COMBO", "%d 連擊") % combo) if combo >= 2 else ""
	if combo_tween != null:
		combo_tween.kill()
	lbl_combo.scale = Vector2.ONE
	if increased:
		lbl_combo.pivot_offset = lbl_combo.size * 0.5
		lbl_combo.scale = Vector2(1.12, 1.12)
		combo_tween = create_tween()
		combo_tween.tween_property(lbl_combo, "scale", Vector2.ONE, 0.16)

func play_voice(r) -> void:
	_play_kana(r.kana[r.target])

func _play_kana(kana: String) -> void:
	voice.stream = Assets.VOICE.get(_romaji(kana))
	if voice.stream:
		voice.play()

## Delayed red HP chunk: waits bar_wait_s after a hit, then drains to the real HP.
func _tick_hp_bar(dt: float) -> void:
	if hp_delay_wait > 0.0:
		hp_delay_wait -= dt
	elif hp_delayed > float(hp):
		hp_delayed = maxf(float(hp), hp_delayed - bar_drain * dt)

func _process(dt: float) -> void:
	_tick_hp_bar(dt)
	if state == State.RUNNING:
		_tick(dt)
	elif state == State.CLEARED or state == State.FAILED or tutorial_actions.is_visible_in_tree():
		result_time += dt
	_update_view(dt)
	_update_hud()

func _tick(dt: float) -> void:
	var time_limit := float(lvl.get("time_limit_s", 60.0))
	if not is_tutorial_active() and not is_endless:
		var remaining := time_limit - clock()
		if remaining <= 0.0:
			_finish(false, "time_up")
			return
		# Only advance as far as the deadline, even when a frame straddles it.
		dt = minf(dt, remaining)
	if autopilot:
		if speed_mode == "step":
			if ctrl.target < ctrl.max_speed: ctrl.tap_up()
		else:
			ctrl.holding = true
		var ar = active_row()
		if ar != null:
			lane = ar.target
	ctrl.step(dt)
	elapsed += dt
	player_dist += ctrl.speed * dt
	player_x = move_toward(player_x, lane_x(lane), lane_change_speed * dt)
	if is_endless:
		endless_score += int(ctrl.speed * dt * 2.5)
		var current_tier: int = int(correct / 10)
		if current_tier > endless_tier:
			endless_tier = current_tier
			ctrl.max_speed = minf(68.0 / 3.6, (38.0 + endless_tier * 6.0) / 3.6)
			row_spacing = maxf(16.0, 26.0 - endless_tier * 2.0)
			endless_score += 1000 * endless_tier
			var rm := LevelDB.romaji_map(cfg)
			var pool := _get_endless_pool_for_tier(endless_tier)
			lvl["kana"] = pool
			lvl["romaji"] = pool.map(func(k): return rm.get(k, ""))
			_notice(I18n.t("HUD_ENDLESS_WAVE_BREAK", "★ WAVE %d 突破！極限提速！ ★") % (endless_tier + 1))
			sfx("star", 1.25, 3.0)
			_screen_flash(Color(0.2, 0.9, 1.0, 0.2), 0.2)
			_spawn_shockwave(player.global_position + Vector3(0, 1.0, 0), Color(0.2, 0.9, 1.0), 280.0)
		if state == State.RUNNING:
			if ctrl.kmh() < 12.0:
				endless_slow_timer += dt
				if endless_slow_timer >= 2.5:
					endless_drain_tick += dt
					if endless_drain_tick >= 0.5:
						endless_drain_tick = 0.0
						take_damage(5)
						_screen_flash(Color(1.0, 0.15, 0.15, 0.22), 0.15)
						_float_text(I18n.t("FLOAT_LOW_SPEED_WARN", "低速警告！ -5 HP"), Color(1.0, 0.3, 0.3))
						rumble(0.25, 0.35, 0.15)
						sfx("miss", 0.9, -2.0)
			else:
				endless_slow_timer = 0.0
				endless_drain_tick = 0.0
	_spawn_rows()
	var r = active_row()
	if r != null and player_dist >= r.dist:
		_resolve(r)
	# cleanup passed rows
	while rows.size() > 0 and rows[0].resolved and rows[0].dist < player_dist - 15.0:
		var old = rows.pop_front()
		if is_instance_valid(old.node):
			old.node.queue_free()
	if state != State.RUNNING or is_tutorial_active():
		return
	if is_endless:
		return
	if correct >= int(lvl.get("target_correct", 20)) and clock() <= time_limit:
		_finish(true)
	elif clock() >= time_limit:
		_finish(false, "time_up")

func _resolve(r) -> void:
	r.resolved = true
	var lane_xs: Array = []
	for i in r.kana.size():
		lane_xs.append(lane_x(i))
	var hit := Rules.hit_lane(player_x, lane_xs, player_w, stone_w)
	if is_tutorial_active():
		_resolve_tutorial(r, hit)
		return
	var reaction: float = elapsed - float(r.voice_t)
	var k: String = r.kana[r.target]
	var result := "miss"
	var damage := 0
	if hit == -1:
		missed += 1
		var added_time := float(lvl.get("miss_penalty_s", 1.0))
		penalty += added_time
		requeue.append(k)          # comes back later (next newly spawned row)
		_set_combo(0)
		_fx_miss(r, added_time)
		break_progress = 0
		damage = miss_damage
		if is_endless:
			_float_text("漏答！ -%d" % damage_after_reduction(miss_damage), Color(1.0, 0.4, 0.4))
	elif hit == r.target:
		result = "correct"
		if boss_shield_up:
			result = "shield"
			break_progress += 1
			runner.play_once("hit_shield", 8)   # last ~8 frames are already running -> back to run early
			_shield_fx("hit")
			if break_progress >= break_chain:
				boss_shield_up = false
				shields_broken += 1
				shield_bonus += 3.0
				rumble(0.8, 1.0, 0.35)
				_notice(I18n.t("HUD_SHIELD_BREAK_NOTICE", "護盾擊破！時間獎勵 -3.0秒"))
				_float_text(I18n.t("FLOAT_TIME_BONUS", "時間獎勵 -3.0s！"), Color(0.35, 1.0, 0.85))
				_spawn_shockwave(player.global_position + Vector3(0, 1.2, -1.0), Color(0.4, 0.95, 1.0), 380.0)
				_screen_flash(Color(0.4, 0.95, 1.0, 0.25), 0.22)
				_burst(player.global_position + Vector3(0, 1.2, -1.0), Color(0.4, 0.95, 1.0))
				sfx("shatter", 0.78, 4.0)
				sfx("star", 1.4, 1.0)
		else:
			correct += 1
			_check_boss_shield()
		_set_combo(combo + 1)
		_fx_correct(r.stones[hit])
		if is_endless:
			var hit_pts: int = int(120.0 * (1.0 + float(combo) * 0.1) * (1.0 + ctrl.kmh() / 50.0))
			endless_score += hit_pts
			_float_text("+%d" % hit_pts, Color(1.0, 0.9, 0.2))
			if combo > 0 and combo % 10 == 0:
				var heal := 15
				hp = mini(max_hp, hp + heal)
				_hearts_fx(Color(0.2, 1.0, 0.4))
				_emit_hp()
				rumble(0.35, 0.5, 0.2)
				_notice(I18n.t("HUD_ENDLESS_HEAL", "連擊獎勵！HP +%d") % heal)
				sfx("heal", 1.0, 2.0)
			if correct >= 10: check_achievement("endless_runner")
			if correct >= 30: check_achievement("endless_survivor")
			if player_dist >= 1000.0: check_achievement("endless_marathon")
	else:
		result = "wrong"
		wrong += 1
		var added_time := float(lvl.get("wrong_penalty_s", 2.0))
		penalty += added_time
		ctrl.scale_speed(float(cfg.get("speed", {}).get("wrong_hit_speed_factor", 0.5)))
		_set_combo(0)
		_fx_wrong(r.stones[hit], r.stones[r.target], added_time)
		_retry_in_next_row(r, k, r.target)
		break_progress = 0
		damage = wrong_damage
		if is_endless:
			_float_text(I18n.t("FLOAT_WRONG_DAMAGE", "答錯！ -%d") % damage_after_reduction(wrong_damage), Color(1.0, 0.2, 0.2))
	if result == "wrong" or result == "miss":
		var item: Dictionary = review_items.get(k, {"choices": r.kana.duplicate(), "wrong": 0, "missed": 0, "confused_with": ""})
		if result == "wrong":
			item.wrong += 1
			item.confused_with = r.kana[hit]
			item.choices = r.kana.duplicate()
		else:
			item.missed += 1
		review_items[k] = item
	logger.add(r.q, k, result, reaction, ctrl.kmh(), clock())
	save.record_kana_stat(k, result, reaction)
	# Lethal damage writes the result log immediately.
	take_damage(damage)
	if state == State.RUNNING and (is_endless or (correct < int(lvl.get("target_correct", 20)) and clock() < float(lvl.get("time_limit_s", 60.0)))):
		_activate_next()

## Boss/ultimate: at each threshold of the required count, raise a shield that needs N correct in a row.
func _check_boss_shield() -> void:
	if shield_phase >= shield_thresholds.size():
		return
	var need := int(ceil(float(shield_thresholds[shield_phase]) * float(lvl.target_correct)))
	if correct >= need and correct < int(lvl.target_correct):
		shield_phase += 1
		boss_shield_up = true
		break_progress = 0
		_notice(I18n.t("HUD_SHIELD_RAISE_NOTICE", "護盾展開！"))

func _finish(cleared: bool, reason := "") -> void:
	if is_endless:
		_finish_endless(reason)
		return
	fail_reason = "" if cleared else (reason if reason != "" else "time_up")
	state = State.CLEARED if cleared else State.FAILED
	result_time = 0.0
	ctrl.reset()
	music.stop()
	voice.stop()
	var stars := Rules.stars_for(clock(), lvl) if cleared else 0
	var new_best := false
	var first_hira_boss := cleared and level_id == "1-BOSS" and not save.cleared_any("1-BOSS")
	last_points = 0
	if cleared:
		if is_daily:
			var daily_res := save.record_daily_clear(100)
			last_points = 50 + (100 if daily_res.first_today else 0)
			if not daily_res.first_today:
				save.add_points(50)
			_persist_progress()
			sfx("star", 1.3, 3.0)
			if daily_res.first_today:
				_notice(I18n.t("HUD_DAILY_STREAK_POPUP", "★ 今日特快達成！連續第 %d 天！獲得 +100 點") % daily_res.streak)
		elif is_drill:
			last_points = correct * 2
			save.add_points(last_points)
			_persist_progress()
			sfx("shatter", 0.8, 2.0)
		else:
			last_record = save.record(level_id, distance, stars, clock())
			new_best = bool(last_record.better)
			last_points = Rules.points_for(bool(last_record.first_clear), int(last_record.new_stars), distance_multiplier(), cfg.get("points", {}))
			save.add_points(last_points)
			_persist_progress()
			sfx("shatter", 0.8, 2.0)
			check_achievement("first_step")
			if stars == 3:
				check_achievement("three_stars")
			if hp >= max_hp:
				check_achievement("flawless")
			if ctrl.kmh() >= 45.0:
				check_achievement("speed_demon")
			if str(lvl.get("type", "")) == "boss" or str(lvl.get("type", "")) == "ultimate":
				check_achievement("boss_breaker")
			if str(lvl.get("script", "")) == "kata":
				check_achievement("kata_pioneer")
		var all_hira_cleared := true
		for l in levels:
			if str(l.get("script", "")) == "hira" and not save.cleared_any(str(l.get("id", ""))):
				all_hira_cleared = false
				break
		if all_hira_cleared:
			check_achievement("hira_master")
	else:
		sfx("back")
	lbl_result_heading.text = I18n.t("TITLE_RESULTS_CLEAR", "通關成功") if cleared else (I18n.t("TITLE_RESULTS_HP", "體力耗盡") if fail_reason == "hp_out" else I18n.t("TITLE_RESULTS_TIME", "時間到"))
	var grade := "C"
	var grade_col := Color(0.65, 0.72, 0.85)
	if cleared:
		if stars == 3 and wrong == 0 and missed == 0:
			grade = "S+"
			grade_col = Color(1.0, 0.85, 0.2)
		elif stars == 3:
			grade = "S"
			grade_col = Color(1.0, 0.85, 0.2)
		elif stars == 2:
			grade = "A"
			grade_col = Color(0.1, 0.95, 1.0)
		else:
			grade = "B"
			grade_col = Color(1.0, 0.45, 0.85)
	lbl_rank.text = grade
	lbl_rank.add_theme_color_override("font_color", grade_col)
	var sb := rank_box.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.border_color = grade_col
	rank_box.scale = Vector2(2.2, 2.2)
	rank_box.pivot_offset = rank_box.custom_minimum_size * 0.5
	rank_box.modulate.a = 0.0
	var rkt := create_tween()
	rkt.tween_interval(0.08)
	rkt.tween_property(rank_box, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rkt.parallel().tween_property(rank_box, "modulate:a", 1.0, 0.15)
	var body_fmt := I18n.t("RESULTS_BODY_FORMAT", "%s\n%s・%s模式\n\n答對 %d / %d　答錯 %d　漏答 %d\n用時 %.2f 秒（含罰時 %.1f 秒）\n最佳連擊 %d　體力 %d / %d\n獲得點數 +%d（總點數 %d）")
	lbl_result.text = body_fmt % [
		str(lvl.get("name", "")), distance_name(), mode_name(), correct, int(lvl.target_correct), wrong, missed,
		clock(), penalty, best_combo, hp, max_hp, last_points, save.points()]
	if shield_bonus > 0.0:
		lbl_result.text += I18n.t("RESULTS_SHIELD_BONUS_INFO", "\n★ 破盾時間獎勵：-%.1f 秒") % shield_bonus
	if is_daily:
		lbl_result.text += I18n.t("RESULTS_DAILY_STREAK_LINE", "\n\n★ 每日疾走連續簽到：第 %d 天！") % save.get_daily().get("streak", 1)
	if cleared and stars < 3:
		var next_limit := float(lvl.star2_s if stars < 2 else lvl.star3_s)
		lbl_result.text += I18n.t("RESULTS_NEXT_STAR", "\n再快 %.2f 秒可達 %d 星") % [maxf(0.0, clock() - next_limit), stars + 1]
	if not review_items.is_empty():
		var kana := "、".join(review_items.keys().slice(0, 4))
		lbl_result.text += I18n.t("RESULTS_REVIEW_COUNT", "\n待複習 %d 字　%s") % [review_items.size(), kana]
		if review_items.size() > 4:
			lbl_result.text += I18n.t("RESULTS_REVIEW_ETC", " 等")
	var knowledge := str(lvl.get("knowledge", ""))
	if not knowledge.is_empty():
		lbl_result.text += I18n.t("RESULTS_KNOWLEDGE", "\n\n小知識：%s") % knowledge
	res_badge.visible = new_best

	# Populate Visual Dashboard Cards
	if is_daily:
		res_chip_stage.text = "★ %s · %s" % [I18n.t("DAILY_RUN_TITLE", "每日特快"), distance_name()]
	elif is_drill:
		res_chip_stage.text = "★ %s · %s" % [I18n.t("DRILL_TITLE", "假名特訓"), mode_name()]
	else:
		res_chip_stage.text = "%s · %s · %s模式" % [str(lvl.get("name", "")), distance_name(), mode_name()]

	lbl_card_time_val.text = "%.2f 秒" % clock()
	var time_subs: Array = []
	if penalty > 0.0:
		time_subs.append("+%.1fs 罰時" % penalty)
	if shield_bonus > 0.0:
		time_subs.append("-%.1fs 破盾" % shield_bonus)
	if cleared and stars < 3:
		var next_limit := float(lvl.star2_s if stars < 2 else lvl.star3_s)
		time_subs.append("差 %.2fs 達 %d 星" % [maxf(0.0, clock() - next_limit), stars + 1])
	lbl_card_time_sub.text = "  ".join(time_subs) if not time_subs.is_empty() else "節奏完美！"

	lbl_card_acc_val.text = "%d / %d" % [correct, int(lvl.target_correct)]
	if wrong == 0 and missed == 0:
		lbl_card_acc_sub.text = "★ PERFECT 完美過關！"
		lbl_card_acc_sub.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		lbl_card_acc_sub.text = "× 答錯 %d   ○ 漏答 %d" % [wrong, missed]
		lbl_card_acc_sub.add_theme_color_override("font_color", Color(0.9, 0.6, 0.6))

	lbl_card_combo_val.text = "%d MAX" % best_combo
	lbl_card_combo_sub.text = "體力 %d / %d" % [hp, max_hp]

	lbl_card_pts_val.text = "+%d 點" % last_points
	var pts_sub_txt := "累計持有 %d 點" % save.points()
	if is_daily:
		pts_sub_txt += " (★ 連續第 %d 天)" % save.get_daily().get("streak", 1)
	lbl_card_pts_sub.text = pts_sub_txt

	# Weak Kana Visual Tiles
	for child in res_weak_tiles.get_children():
		res_weak_tiles.remove_child(child)
		child.queue_free()

	if not review_items.is_empty():
		res_weak_box.visible = true
		for kana in review_items.keys().slice(0, 8):
			var tile := PanelContainer.new()
			var tsb := StyleBoxFlat.new()
			tsb.bg_color = Color(0.12, 0.05, 0.08, 0.90)
			tsb.border_width_left = 2; tsb.border_width_top = 2; tsb.border_width_right = 2; tsb.border_width_bottom = 2
			tsb.border_color = Color(1.0, 0.35, 0.25, 0.85)
			tsb.set_corner_radius_all(8)
			tsb.set_content_margin_all(4)
			tile.add_theme_stylebox_override("panel", tsb)
			tile.custom_minimum_size = Vector2(48, 52)

			var tvb := VBoxContainer.new()
			tvb.alignment = BoxContainer.ALIGNMENT_CENTER
			tvb.add_theme_constant_override("separation", 0)
			tile.add_child(tvb)

			var klbl := Label.new()
			klbl.text = kana
			klbl.add_theme_font_override("font", Art.FONT_KANA)
			klbl.add_theme_font_size_override("font_size", 22)
			klbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
			klbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tvb.add_child(klbl)

			var rlbl := Label.new()
			rlbl.text = _romaji(kana)
			rlbl.add_theme_font_override("font", Assets.FONT_HUD)
			rlbl.add_theme_font_size_override("font_size", 10)
			rlbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
			rlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tvb.add_child(rlbl)

			res_weak_tiles.add_child(tile)
	else:
		res_weak_box.visible = false

	# Knowledge capsule
	if not knowledge.is_empty():
		res_knowledge_box.visible = true
		lbl_res_knowledge.text = "【小知識】%s" % knowledge
	else:
		res_knowledge_box.visible = false
	btn_retry.text = I18n.t("BTN_RETRY_DRILL", "再練一次") if is_drill else I18n.t("BTN_RETRY", "重來")
	btn_select.text = I18n.t("BTN_BACK_CHART", "回五十音表") if is_drill else I18n.t("BTN_SELECT", "回選關")
	if is_daily:
		lbl_result_heading.text = I18n.t("TITLE_DAILY_FINISH", "今日特快完成")
		btn_next.visible = false
		btn_kata_next.visible = false
	elif is_drill:
		lbl_result_heading.text = I18n.t("TITLE_DRILL_FINISH", "特訓完成")
		btn_next.visible = false
		btn_kata_next.visible = false
	for i in 3:
		var st_child := res_stars.get_child(i) as TextureRect
		st_child.visible = true
		st_child.pivot_offset = st_child.custom_minimum_size * 0.5
		if i < stars:
			st_child.texture = Art.UI.star_full_200
			st_child.scale = Vector2(0.1, 0.1)
			var stt := create_tween()
			stt.tween_interval(0.18 + i * 0.14)
			stt.tween_property(st_child, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			stt.tween_callback(func(): sfx("star", 1.0 + i * 0.15, 1.0))
		else:
			st_child.texture = Art.UI.star_empty_200
			st_child.scale = Vector2.ONE
	lbl_center.text = ""
	lbl_hint.text = ""
	var next_available := can_go_next()
	btn_next.visible = next_available
	btn_next.disabled = not next_available
	btn_next.text = I18n.t("BTN_NEXT_HIRA", "繼續平假名") if first_hira_boss else I18n.t("BTN_NEXT", "下一關")
	btn_kata_next.visible = first_hira_boss
	btn_kata_next.text = I18n.t("BTN_START_KATA", "開始片假名")
	_refresh_save_notice()
	btn_review.visible = not review_items.is_empty()
	btn_review.text = I18n.t("BTN_REVIEW", "錯題練習")
	result_actions.move_child(btn_review, 0 if btn_review.visible and not cleared else 2)
	_layout_result_cards()
	pause_box.visible = false
	lbl_hint.visible = true
	touches.clear()
	results_box.visible = true
	_update_pad_bar()
	_update_title_prompts()
	(btn_save_retry if progress_pending else (btn_review if btn_review.visible and not cleared else btn_retry)).grab_focus()
	if dev_mode:
		last_saved_path = logger.save("clear" if cleared else fail_reason, elapsed, clock(), stars, hp, speed_mode, distance, last_points, int(lvl.target_correct))
		print("[dev] timing saved: ", last_saved_path)
	lbl_boss.text = ""
	print("[result] %s %s %s%s clock=%.3f elapsed=%.3f penalty=%.1f correct=%d wrong=%d miss=%d stars=%d" % [
		level_id, distance, "CLEAR" if cleared else "FAIL", "" if cleared else "(" + fail_reason + ")", clock(), elapsed, penalty, correct, wrong, missed, stars])

func _persist_progress() -> bool:
	progress_pending = not save.save_file()
	_refresh_save_notice()
	return not progress_pending

func _refresh_save_notice() -> void:
	if btn_save_retry == null:
		return
	btn_save_retry.visible = progress_pending
	var unsaved_tag := I18n.t("UNSAVED_TAG", "（未存檔）")
	lbl_result_heading.text = lbl_result_heading.text.replace(unsaved_tag, "").replace("（未存檔）", "")
	if progress_pending:
		lbl_result_heading.text += unsaved_tag

func _retry_save() -> void:
	if not progress_pending:
		return
	_persist_progress()
	_layout_result_cards()
	if select_box.visible:
		show_select()
	elif not progress_pending:
		btn_retry.grab_focus()

func _start_katakana() -> void:
	for i in levels.size():
		if levels[i].get("script") == "kata":
			choose_level(i)
			return

func _open_review() -> void:
	if not results_box.visible or review_items.is_empty():
		return
	review_index = 0
	results_box.visible = false
	review_box.visible = true
	lbl_review_heading.text = I18n.t("BTN_REVIEW", "錯題練習")
	btn_review_replay.text = I18n.t("REVIEW_REPLAY", "重播語音")
	btn_review_back.text = I18n.t("REVIEW_BACK", "返回結算")
	_update_pad_bar()
	_update_title_prompts()
	_show_review_item()

func _show_review_item() -> void:
	review_attempts = 0
	var target: String = review_items.keys()[review_index]
	var item: Dictionary = review_items[target]
	lbl_review_progress.text = I18n.t("REVIEW_PROGRESS", "%d / %d　這局答錯 %d 次・漏答 %d 次") % [review_index + 1, review_items.size(), item.wrong, item.missed]
	var options: Array = item.choices.duplicate()
	options.shuffle()
	for i in review_choices.size():
		var button := review_choices[i]
		button.visible = i < options.size()
		button.disabled = false
		button.text = options[i] if button.visible else ""
	lbl_review_feedback.text = I18n.t("REVIEW_TITLE", "聽語音，選出對應的假名\n可按 1／2／3 選擇")
	btn_review_next.text = I18n.t("REVIEW_FINISH", "完成練習") if review_index == review_items.size() - 1 else I18n.t("REVIEW_NEXT", "下一字")
	btn_review_next.disabled = true
	btn_review_replay.grab_focus()
	_play_kana(target)

func _replay_review() -> void:
	if review_box.visible:
		_play_kana(review_items.keys()[review_index])

func _answer_review(button: Button) -> void:
	if not review_box.visible or not btn_review_next.disabled:
		return
	var target: String = review_items.keys()[review_index]
	if button.text != target:
		review_attempts += 1
		lbl_review_feedback.text = "再聽一次，選出對應的假名" if review_attempts == 1 else "正解是「%s」，再選一次" % target
		_play_kana(target)
		return
	lbl_review_feedback.text = "答對了！「%s」是 %s" % [target, _romaji(target)]
	var confused_with: String = review_items[target].confused_with
	if not confused_with.is_empty():
		lbl_review_feedback.text += "\n這局曾選「%s」" % confused_with
	for choice in review_choices:
		choice.disabled = true
	btn_review_next.disabled = false
	btn_review_next.grab_focus()

func _advance_review() -> void:
	if not review_box.visible or btn_review_next.disabled:
		return
	review_index += 1
	if review_index == review_items.size():
		_close_review()
	else:
		_show_review_item()

func _close_review() -> void:
	if not review_box.visible:
		return
	voice.stop()
	review_box.visible = false
	results_box.visible = true
	_update_pad_bar()
	_update_title_prompts()
	btn_review.grab_focus()

# ---------------------------------------------------------------- feedback
class ShockwaveRing extends Control:
	var current_radius: float = 12.0
	var current_alpha: float = 0.95
	var current_width: float = 6.0
	var ring_color: Color = Color(0.35, 0.95, 1.0)

	func _draw() -> void:
		if current_alpha <= 0.01:
			return
		var c := Color(ring_color.r, ring_color.g, ring_color.b, current_alpha)
		var c_inner := Color(ring_color.r, ring_color.g, ring_color.b, current_alpha * 0.45)
		draw_arc(Vector2.ZERO, current_radius, 0.0, TAU, 36, c, current_width, true)
		draw_arc(Vector2.ZERO, current_radius * 0.72, 0.0, TAU, 28, c_inner, current_width * 0.55, true)

func _spawn_shockwave(at_3d: Vector3, col: Color = Color(0.35, 0.95, 1.0), max_r: float = 160.0) -> void:
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree() or fx_layer == null:
		return
	var center_2d: Vector2 = cam.unproject_position(at_3d)
	var sw := ShockwaveRing.new()
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.position = center_2d
	sw.ring_color = col
	sw.current_radius = 12.0 * UI
	sw.current_alpha = 0.95
	sw.current_width = 7.0 * UI
	fx_layer.add_child(sw)

	var target_r := max_r * UI
	var tw := create_tween()
	tw.tween_method(func(v: float):
		if is_instance_valid(sw):
			sw.current_radius = lerpf(12.0 * UI, target_r, v)
			sw.current_alpha = lerpf(0.95, 0.0, v)
			sw.current_width = lerpf(7.0 * UI, 1.5 * UI, v)
			sw.queue_redraw()
	, 0.0, 1.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(sw.queue_free)

func _screen_flash(c: Color, duration: float = 0.12) -> void:
	if hit_flash == null or not is_instance_valid(hit_flash):
		return
	hit_flash.color = c
	var tw := create_tween()
	tw.tween_property(hit_flash, "color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _spawn_shatter_sprite(at_3d: Vector3) -> void:
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree() or fx_layer == null:
		return
	var sp := Sprite2D.new()
	sp.texture = Art.TABLET_SHATTER
	sp.hframes = 8
	sp.vframes = 1
	sp.frame = 0
	sp.position = cam.unproject_position(at_3d)
	sp.scale = Vector2.ONE * (UI * 1.5)
	fx_layer.add_child(sp)

	var tw := create_tween()
	tw.tween_method(func(f: float):
		if is_instance_valid(sp):
			sp.frame = clampi(int(f), 0, 7)
	, 0.0, 7.99, 0.22)
	tw.tween_callback(sp.queue_free)

func _float_text(t: String, c: Color) -> void:
	if float_tween != null and float_tween.is_running():
		float_tween.kill()
	lbl_float.text = t
	lbl_float.add_theme_color_override("font_color", c)
	lbl_float.modulate.a = 1.0
	float_tween = create_tween()
	float_tween.tween_property(lbl_float, "modulate:a", 0.0, 0.45).set_delay(0.35)

func _glow(st: MeshInstance3D, c: Color, energy: float, dur: float) -> void:
	# Only the hit stone gets its own tint; the ordinary rock material stays shared.
	var m: ShaderMaterial = st.material_override.duplicate()
	st.material_override = m
	m.set_shader_parameter("hit_tint", c)
	m.set_shader_parameter("hit_strength", minf(0.8, energy * 0.2))
	create_tween().tween_property(m, "shader_parameter/hit_strength", 0.0, dur)

func calc_hit_pitch(cmb: int) -> float:
	var mode := str(save.get_setting("hit_pitch_mode", "pentatonic"))
	if mode == "fixed":
		return 1.0
	elif mode == "random":
		return rng.randf_range(0.95, 1.1)
	if cmb <= 1:
		return 1.0
	var step := (cmb - 1) % 5
	var oct: int = mini(1, (cmb - 1) / 5)
	return PENTATONIC_RATIOS[step] * (1.0 + float(oct) * 0.28)

func _fx_correct(st: MeshInstance3D) -> void:
	rumble(0.25 if combo < 10 else 0.45, 0.1 if combo < 10 else 0.3, 0.12)
	var fb: Dictionary = cfg.get("feedback", {})
	var glow_col := Color(1.0, 0.88, 0.3) if combo >= 10 else Color(0.35, 0.95, 1.0)
	_glow(st, glow_col, float(fb.get("glow_strength", 4.0)), 0.5)
	# knockback: stone flies forward and tumbles away from the player
	var kb := float(fb.get("knockback_distance_m", 7.0))
	var side := signf(st.position.x) if absf(st.position.x) > 0.1 else (1.0 if rng.randf() > 0.5 else -1.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(st, "position", st.position + Vector3(side * 2.5, 2.5, -kb), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(st, "rotation", Vector3(-4.0, side * 3.0, side * 2.0), 0.45)
	tw.tween_property(st, "scale", Vector3.ONE * 0.2, 0.45).set_delay(0.15)
	_shatter(st)
	_sparks(st.global_position)
	_burst(st.global_position + Vector3(0, 0.5, 0), glow_col)
	_spawn_shatter_sprite(st.global_position)
	_spawn_shockwave(st.global_position, glow_col, 220.0 if combo >= 10 else 160.0)
	_screen_flash(Color(1.0, 0.92, 0.4, 0.14) if combo >= 10 else Color(0.25, 0.88, 1.0, 0.12), 0.12)
	var target_pitch := calc_hit_pitch(combo)
	sfx("shatter", target_pitch, 3.0)
	if combo in [5, 10, 15, 20, 30, 40, 50]:
		sfx("star", 1.0 + float(mini(combo, 40)) * 0.02, -1.0)
		if combo >= 10:
			sfx("focus", 1.25, -2.0)
	# player punch (scale pop) + tiny FOV punch, no camera shake
	runner.play_once("hit_correct")
	var pt := create_tween()
	pt.tween_property(player_mesh, "scale", Vector3(1.06, 0.96, 1.0), 0.05)
	pt.tween_property(player_mesh, "scale", Vector3.ONE, 0.15)
	_glow_player(glow_col, 3.0)
	var fov_punch := float(fb.get("fov_punch_deg", 4.0))
	cam.fov = base_fov + fov_punch
	_judge(true)

## Multi-chunk 3D fracture trajectory with glowing break surfaces.
func _shatter(st: MeshInstance3D) -> void:
	st.transparency = 1.0
	st.get_node("FocusFrame").hide()
	var chip_data := [
		[Vector3(-0.45, 0.3, 0.15), Vector3(0.18, 0.14, 0.25), Vector3(-2.8, 2.2, -4.5), Vector3(4.0, -3.0, 2.0)],
		[Vector3(0.45, 0.35, 0.1), Vector3(0.16, 0.20, 0.22), Vector3(3.0, 2.5, -4.0), Vector3(-3.5, 4.0, -2.5)],
		[Vector3(-0.2, 0.65, -0.1), Vector3(0.20, 0.12, 0.28), Vector3(-1.5, 3.2, -3.8), Vector3(2.0, 5.0, 3.0)],
		[Vector3(0.25, 0.60, 0.05), Vector3(0.15, 0.18, 0.20), Vector3(1.8, 3.5, -4.2), Vector3(-4.0, -2.0, 4.0)],
		[Vector3(-0.35, -0.25, 0.2), Vector3(0.22, 0.16, 0.32), Vector3(-2.5, 1.2, -3.2), Vector3(3.0, 2.0, -3.0)],
		[Vector3(0.35, -0.2, 0.25), Vector3(0.18, 0.15, 0.26), Vector3(2.6, 1.4, -3.0), Vector3(-2.0, 3.5, 2.5)],
		[Vector3(0.0, 0.1, -0.2), Vector3(0.24, 0.22, 0.20), Vector3(0.5, 2.8, -5.5), Vector3(5.0, 1.0, -4.0)],
		[Vector3(-0.15, -0.5, 0.1), Vector3(0.14, 0.12, 0.18), Vector3(-1.8, 0.8, -2.5), Vector3(-3.0, -4.0, 2.0)],
		[Vector3(0.2, -0.45, 0.15), Vector3(0.16, 0.14, 0.19), Vector3(1.9, 0.9, -2.8), Vector3(2.5, -3.0, -3.5)],
		[Vector3(0.0, 0.8, 0.0), Vector3(0.12, 0.10, 0.15), Vector3(0.2, 3.8, -4.8), Vector3(6.0, 2.0, 5.0)],
	]
	var glow_col := Color(1.0, 0.88, 0.3) if combo >= 10 else Color(0.35, 0.95, 1.0)
	for d in chip_data:
		var chip := MeshInstance3D.new()
		chip.mesh = stone_mesh
		var cm: ShaderMaterial = stone_material.duplicate()
		cm.set_shader_parameter("hit_tint", glow_col)
		cm.set_shader_parameter("hit_strength", 0.75)
		chip.material_override = cm
		chip.scale = d[1]
		chip.position = st.global_position + d[0] * 0.5
		add_child(chip)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(chip, "position", chip.position + d[2], 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(chip, "rotation", d[3], 0.38)
		tw.tween_property(chip, "scale", Vector3.ZERO, 0.18).set_delay(0.20)
		tw.chain().tween_callback(chip.queue_free)

## Sparks (batch02 sparks_atlas) burst on the 2D fx layer at the stone's screen position.
func _sparks(at: Vector3) -> void:
	if cam == null or not cam.is_inside_tree():
		return
	var p := CPUParticles2D.new()
	var t := AtlasTexture.new(); t.atlas = Art.VFX.sparks; t.region = Rect2(0, 0, 64, 64)
	p.texture = t
	p.one_shot = true
	p.explosiveness = 1.0
	# Keep the hit burst local while the player reads the next row.
	p.amount = 12
	p.lifetime = 0.38
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 280.0
	p.initial_velocity_max = 560.0
	p.damping_min = 600.0; p.damping_max = 600.0
	p.angular_velocity_min = -360.0; p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.5; p.scale_amount_max = 1.0
	p.position = cam.unproject_position(at)
	fx_layer.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

func _fx_wrong(st: MeshInstance3D, right: MeshInstance3D, added_time: float) -> void:
	rumble(0.65, 0.85, 0.3)
	runner.play_once("hit_wrong")
	_glow(st, Color(1.0, 0.2, 0.2), 3.0, 0.6)
	_glow(right, Color(0.3, 1.0, 0.5), 1.5, 0.8)   # show which one was right
	var tw := create_tween()
	tw.tween_property(st, "position", st.position + Vector3(0, 0.3, -1.2), 0.08)
	tw.tween_property(st, "position", st.position + Vector3(0, 0, -0.8), 0.2)
	var pt := create_tween()
	pt.tween_property(player_mesh, "position:z", 0.6, 0.06)
	pt.tween_property(player_mesh, "position:z", 0.0, 0.25)
	_glow_player(Color(1.0, 0.2, 0.2), 2.5)
	_screen_flash(Color(1.0, 0.2, 0.2, 0.16), 0.18)
	_spawn_shockwave(st.global_position, Color(1.0, 0.25, 0.25), 130.0)
	sfx("miss", 1.0, 0.0)
	if bool(cfg.get("feedback", {}).get("screen_shake_on_normal_hit", false)):
		cam.h_offset = 0.15
	_float_text(I18n.t("FLOAT_WRONG_TIME", "答錯 %+.1f 秒") % added_time, Color(1.0, 0.35, 0.35))
	_judge(false)

func _fx_miss(r, added_time: float) -> void:
	_glow(r.stones[r.target], Color(0.3, 1.0, 0.5), 1.5, 0.8)
	sfx("tick")
	_float_text("漏答 %+.1f 秒" % added_time, Color(0.8, 0.8, 1.0))

func _glow_player(c: Color, e: float) -> void:
	player_mat.emission = c
	player_mat.emission_energy_multiplier = e
	var tw := create_tween()
	tw.tween_property(player_mat, "emission_energy_multiplier", 0.0, 0.35)

func _burst(at: Vector3, c: Color) -> void:
	var p := CPUParticles3D.new()
	add_child(p)
	p.global_position = at
	p.one_shot = true
	p.amount = 24
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector3(0, 0.5, -1)
	p.spread = 70.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0, -12, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.08; sm.height = 0.16
	p.mesh = sm
	var m := _mat(c, true)
	m.emission_energy_multiplier = 4.0
	p.material_override = m
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

# ---------------------------------------------------------------- view
func _update_view(dt: float) -> void:
	player.position = Vector3(player_x, 0, -player_dist)
	cam.position = Vector3(player_x * 0.4, 4.1, -player_dist + 7.0)
	cam.look_at(Vector3(player_x * 0.4, 1.3, -player_dist - 14.0))
	cam.fov = move_toward(cam.fov, base_fov + ctrl.kmh() * 0.08, 40.0 * dt)
	cam.h_offset = move_toward(cam.h_offset, 0.0, dt)
	var g := get_node("Ground") as Node3D
	g.position.z = -player_dist - 150.0
	for m in road_mats:
		m.uv1_offset.y = -fmod(player_dist, float(m.get_meta("tile")) * 100.0) / float(m.get_meta("tile"))
	_spawn_props()
	if runner != null:
		runner.position.x = 0.0
		var lean := clampf((lane_x(lane) - player_x) / lane_w, -1.0, 1.0)
		runner.rotation.z = 0.0 if runner.anim.begins_with("lane") else -lean * 0.05
		runner.tick(dt, ctrl.kmh())
		var target_opacity := 1.0
		if state == State.RUNNING:
			var ar = active_row()
			if ar != null:
				var dist_to_stone: float = ar.dist - player_dist
				if dist_to_stone > 3.0 and dist_to_stone < 22.0:
					for i in ar.kana.size():
						if absf(player_x - lane_x(i)) < lane_w * 0.65:
							target_opacity = 0.55
							break
		runner_opacity = move_toward(runner_opacity, target_opacity, dt * 5.0)
		runner.set_opacity(runner_opacity)
		if runner_trail != null:
			runner_trail.emitting = state == State.RUNNING and ctrl.kmh() > 6.0
			if runner_trail.emitting:
				var spd_ratio := clampf(ctrl.kmh() / 40.0, 0.5, 1.8)
				runner_trail.initial_velocity_min = 1.5 * spd_ratio
				runner_trail.initial_velocity_max = 3.5 * spd_ratio
		if speedlines_mat != null:
			var kmh := ctrl.kmh()
			var target_intensity := 0.0
			if state == State.RUNNING and kmh > 24.0:
				target_intensity = clampf((kmh - 24.0) / 36.0, 0.0, 1.0)
			speedlines_intensity = move_toward(speedlines_intensity, target_intensity, dt * 3.5)
			speedlines_mat.set_shader_parameter("intensity", speedlines_intensity)
			if ctrl.locked:
				speedlines_mat.set_shader_parameter("line_color", Color(0.35, 1.0, 0.88, 0.82))
			else:
				speedlines_mat.set_shader_parameter("line_color", Color(0.5, 0.92, 1.0, 0.75))
			if cam != null and is_instance_valid(cam):
				var vp: Vector2 = cam.unproject_position(Vector3(player_x * 0.4, 1.2, -player_dist - 20.0))
				var view_sz: Vector2 = get_viewport().get_visible_rect().size
				if view_sz.x > 0.0 and view_sz.y > 0.0:
					speedlines_mat.set_shader_parameter("center", vp / view_sz)
		if state == State.RUNNING:
			var target_idle := ctrl.kmh() < 1.0
			if ctrl.is_braking() and ctrl.speed > 0.2:
				if runner.anim != "brake" and not runner.is_one_shot():
					runner.play_once("brake", 0, true)
			else:
				if runner.is_one_shot() and runner.anim == "brake":
					runner.release_hold("idle" if target_idle else "run")
			if not runner.is_one_shot():
				if target_idle:
					runner.set_loop("idle")
				elif ctrl.is_accelerating() and ctrl.speed < ctrl.max_speed - 0.01:
					runner.set_loop("accel")
				else:
					runner.set_loop("run")
		elif state != State.PAUSED:
			if runner.is_one_shot() and runner.anim == "brake":
				runner.release_hold("idle")
			runner.set_loop("idle")
	# horizon line of the 3D camera -> place the 2D skyline on it
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var pitch := atan2(cam.position.y - 1.3, 21.0)
	var hy := vs.y * (0.5 - 0.5 * tan(pitch) / tan(deg_to_rad(cam.fov) * 0.5))
	var fh := vs.x * 420.0 / 2160.0 * 1.6
	var k := fh / 420.0
	far_rect.scale = Vector2(k, k)
	far_rect.size = Vector2(vs.x * 2.0 / k, 420.0)
	far_rect.position = Vector2(-fmod(player_x * 6.0 + 1000.0, 2160.0 * k) - vs.x * 0.2, hy - fh + 6.0)
	petals.emission_rect_extents = Vector2(vs.x * 0.6, 10)
	petals.position = Vector2(vs.x * 0.5, -20)
	_tick_shield_fx(dt)

func _update_hud() -> void:
	var tutorial := is_tutorial_active()
	var running := state == State.RUNNING and not tutorial
	var race_stats := running or (state == State.PAUSED and not tutorial)
	for stat in [timer_panel, lbl_count, hearts_box]:
		stat.visible = race_stats
	_refresh_hp_bar()
	shield_box.visible = running and not shield_thresholds.is_empty()
	if shield_box.visible:
		lbl_boss.text = (I18n.t("HUD_SHIELD_CHAIN", "護盾・連對 %d/%d") % [break_progress, break_chain]) if boss_shield_up else (I18n.t("HUD_SHIELD_BROKEN_CNT", "護盾・已破 %d/%d") % [shields_broken, shield_thresholds.size()])
		shield_box.self_modulate = Color("ffc87f") if boss_shield_up else Color.WHITE
	combo_badge.visible = running and not lbl_combo.text.is_empty()
	lbl_notice.visible = running
	lbl_float.visible = running
	judge.visible = running
	ready_box.visible = state == State.READY and not tutorial
	sel_bg.visible = select_box.visible or settings_box.visible or (shop_box != null and shop_box.visible) or (achievements_box != null and achievements_box.visible) or (endless_box != null and endless_box.visible)
	go_box.visible = running and clock() < 0.5
	res_bg.visible = (results_box.visible or review_box.visible) and not sel_bg.visible
	var playing := state == State.RUNNING or state == State.READY
	for b in [btn_accel, btn_brake]:
		b.visible = playing
	btn_pause.visible = state == State.RUNNING
	btn_voice.visible = state == State.RUNNING
	btn_lock.visible = running and speed_mode == "race"
	speedo.visible = (playing or state == State.PAUSED) and not tutorial
	var speed_fraction := clampf(ctrl.speed / ctrl.max_speed, 0.0, 1.0) if ctrl.max_speed > 0.0 else 0.0
	speedo_needle.rotation_degrees = lerpf(-135.0, 135.0, speed_fraction)
	lbl_lock_kmh.text = ("%d" % roundi(ctrl.lock_kmh())) if ctrl.locked else ""
	_set_btn_lit(btn_lock, ctrl.locked)
	_set_btn_lit(btn_accel, ctrl.is_accelerating())
	_set_btn_lit(btn_brake, ctrl.is_braking())
	if is_endless:
		lbl_time.text = "%d 分・%.0fm" % [endless_score, player_dist]
		lbl_count.text = "擊破 %d・W%d" % [correct, endless_tier + 1]
	else:
		var limit := float(lvl.get("time_limit_s", 60.0))
		lbl_time.text = "%.1f / %d" % [clock(), int(limit)]
		lbl_count.text = "%d / %d" % [correct, int(lvl.get("target_correct", 20))]
	if speed_mode == "step":
		lbl_speed.text = "%d → %d\nkm/h" % [roundi(ctrl.kmh()), roundi(ctrl.target_kmh())]
	else:
		lbl_speed.text = "%d km/h" % roundi(ctrl.kmh())
	lbl_dev.visible = dev_mode
	if dev_mode:
		var last := ""
		if logger.entries.size() > 0:
			var e: Dictionary = logger.entries[-1]
			last = "last Q%d %s %s %.2fs" % [e.q, e.target, e.result, e.reaction_s]
		lbl_dev.text = "[DEV TIMING]\nrun %.2f  pen %.1f\ndist %.1f m\nspeed %.1f km/h\n%s\navg ok %.2fs\nW%d M%d\n%s" % [
			elapsed, penalty, player_dist, ctrl.kmh(), last, logger.avg_reaction("success"), wrong, missed,
			("saved: " + last_saved_path.get_file()) if last_saved_path != "" else ""]

# ---------------------------------------------------------------- input
func change_lane(dir: int) -> void:
	var n := clampi(lane + dir, 0, lane_count - 1)
	if n != lane:
		if runner != null and not runner.is_one_shot():
			runner.play_once("lane_left" if dir < 0 else "lane_right")
		lane = n
		sfx("shift", 1.0, -4.0)

func replay_voice() -> void:
	if state == State.RUNNING:
		var r = active_row()
		if r != null:
			if is_tutorial_active() and tutorial_step == TUTORIAL_ROWS.size() - 1:
				tutorial_replayed = true
				_refresh_tutorial("已重播。\n換到對應的線，再撞上石碑。")
			play_voice(r)

func _hit(c: Control, pos: Vector2) -> bool:
	return c.visible and c.get_global_rect().grow(8.0).has_point(pos)

func _accel_touch_count() -> int:
	var n := 0
	for t in touches.values():
		if t.role == "accel": n += 1
	return n

func _brake_touch_count() -> int:
	var n := 0
	for t in touches.values():
		if t.role == "brake": n += 1
	return n

## Multi-touch: each finger is tracked by index. A finger that starts on a
## button drives that button; any other finger swipes. The accelerate finger
## can also swipe sideways to change lanes while staying on the gas.
func _touch(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if title_box != null and title_box.visible:
				start_from_title(); return
			if state == State.RUNNING and _hit(btn_pause, ev.position):
				pause_game(); return
			if state == State.RUNNING and _hit(btn_voice, ev.position):
				replay_voice(); return
			if state == State.RUNNING and _hit(btn_lock, ev.position):
				ctrl.toggle_lock(); return
			if state == State.READY:
				start_run()
			if state != State.RUNNING:
				return
			var role := "swipe"
			if _hit(btn_accel, ev.position): role = "accel"
			elif _hit(btn_brake, ev.position): role = "brake"
			touches[ev.index] = {"role": role, "anchor": ev.position}
			if role == "accel": ctrl.press()
			elif role == "brake": ctrl.brake_press()
		else:
			if not touches.has(ev.index):
				return
			var t: Dictionary = touches[ev.index]
			touches.erase(ev.index)
			if t.role == "accel" and _accel_touch_count() == 0: ctrl.release()
			elif t.role == "brake" and _brake_touch_count() == 0: ctrl.brake_release()
	elif ev is InputEventScreenDrag:
		if state != State.RUNNING or not touches.has(ev.index):
			return
		var t: Dictionary = touches[ev.index]
		if t.role == "brake":
			return
		var dx: float = ev.position.x - t.anchor.x
		var dy: float = ev.position.y - t.anchor.y
		if absf(dx) >= swipe_min and absf(dx) > absf(dy) * 1.5:
			change_lane(1 if dx > 0 else -1)
			t.anchor = ev.position

func _input(ev: InputEvent) -> void:
	if (results_box.visible or tutorial_actions.is_visible_in_tree()) and result_time <= 0.4 and ev.is_action("ui_accept"):
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		if state == State.READY or state == State.RUNNING:
			_touch(ev)
			get_viewport().set_input_as_handled()

func _setup_input_map() -> void:
	var bindings: Dictionary = {
		"game_accelerate": [
			{"type": "key", "key": KEY_SPACE},
			{"type": "key", "key": KEY_W},
			{"type": "key", "key": KEY_UP},
			{"type": "key", "key": KEY_ENTER},
			{"type": "joy_button", "button": JOY_BUTTON_A},
			{"type": "joy_button", "button": JOY_BUTTON_RIGHT_SHOULDER},
			{"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "axis_value": 1.0}
		],
		"game_brake": [
			{"type": "key", "key": KEY_S},
			{"type": "key", "key": KEY_DOWN},
			{"type": "joy_button", "button": JOY_BUTTON_B},
			{"type": "joy_button", "button": JOY_BUTTON_LEFT_SHOULDER},
			{"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_LEFT, "axis_value": 1.0}
		],
		"game_lane_left": [
			{"type": "key", "key": KEY_A},
			{"type": "key", "key": KEY_LEFT},
			{"type": "joy_button", "button": JOY_BUTTON_DPAD_LEFT}
		],
		"game_lane_right": [
			{"type": "key", "key": KEY_D},
			{"type": "key", "key": KEY_RIGHT},
			{"type": "joy_button", "button": JOY_BUTTON_DPAD_RIGHT}
		],
		"game_lock": [
			{"type": "key", "key": KEY_F},
			{"type": "joy_button", "button": JOY_BUTTON_X},
			{"type": "joy_button", "button": JOY_BUTTON_LEFT_STICK}
		],
		"game_voice": [
			{"type": "key", "key": KEY_E},
			{"type": "joy_button", "button": JOY_BUTTON_Y}
		],
		"game_pause": [
			{"type": "key", "key": KEY_ESCAPE},
			{"type": "key", "key": KEY_P},
			{"type": "joy_button", "button": JOY_BUTTON_START}
		]
	}
	for action_name: String in bindings:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for entry: Dictionary in bindings[action_name]:
			var ev: InputEvent = null
			if entry.type == "key":
				var k := InputEventKey.new()
				k.keycode = entry.key
				ev = k
			elif entry.type == "joy_button":
				var jb := InputEventJoypadButton.new()
				jb.button_index = entry.button
				ev = jb
			elif entry.type == "joy_axis":
				var ja := InputEventJoypadMotion.new()
				ja.axis = entry.axis
				ja.axis_value = entry.axis_value
				ev = ja
			if ev != null:
				InputMap.action_add_event(action_name, ev)

func _handle_joy_motion(ev: InputEventJoypadMotion) -> void:
	match ev.axis:
		JOY_AXIS_LEFT_X:
			if ev.axis_value < -0.5:
				if not joy_axis_x_steered:
					joy_axis_x_steered = true
					if state == State.RUNNING:
						change_lane(-1)
			elif ev.axis_value > 0.5:
				if not joy_axis_x_steered:
					joy_axis_x_steered = true
					if state == State.RUNNING:
						change_lane(1)
			elif absf(ev.axis_value) < 0.25:
				joy_axis_x_steered = false
		JOY_AXIS_TRIGGER_RIGHT:
			if ev.axis_value > 0.3:
				if not joy_trigger_right_held:
					joy_trigger_right_held = true
					if state == State.READY:
						start_run()
						ctrl.press()
					elif state == State.RUNNING:
						ctrl.press()
			elif ev.axis_value < 0.15:
				if joy_trigger_right_held:
					joy_trigger_right_held = false
					if state == State.RUNNING:
						ctrl.release()
		JOY_AXIS_TRIGGER_LEFT:
			if ev.axis_value > 0.3:
				if not joy_trigger_left_held:
					joy_trigger_left_held = true
					if state == State.RUNNING:
						ctrl.brake_press()
			elif ev.axis_value < 0.15:
				if joy_trigger_left_held:
					joy_trigger_left_held = false
					if state == State.RUNNING:
						ctrl.brake_release()

func _handle_joy_button(ev: InputEventJoypadButton) -> void:
	var in_result := state == State.CLEARED or state == State.FAILED
	var in_subpanel := (settings_box != null and settings_box.visible) \
		or (shop_box != null and shop_box.visible) \
		or (achievements_box != null and achievements_box.visible) \
		or (endless_box != null and endless_box.visible) \
		or (chart_box != null and chart_box.visible)
	match ev.button_index:
		JOY_BUTTON_A:
			if ev.pressed:
				if title_box != null and title_box.visible:
					start_from_title()
				elif endless_box != null and endless_box.visible:
					start_endless()
				elif chart_box != null and chart_box.visible and chart_tab == "drill" and btn_drill_start != null and btn_drill_start.has_focus():
					start_custom_drill()
				elif review_box.visible:
					if review_choices.size() > 1 and review_choices[1].visible and not review_choices[1].disabled:
						_answer_review(review_choices[1])
				elif state == State.READY:
					start_run()
					ctrl.press()
				elif state == State.RUNNING:
					ctrl.press()
				elif state == State.PAUSED:
					resume()
				elif in_result:
					if btn_kata_next.visible:
						_start_katakana()
					elif btn_next.visible:
						go_next_level()
					else:
						reset_run()
			else:
				if state == State.RUNNING:
					ctrl.release()
		JOY_BUTTON_RIGHT_SHOULDER:
			if ev.pressed:
				if select_box.visible and not in_subpanel:
					_select_kana_tab("kata")
				elif state == State.READY:
					start_run()
					ctrl.press()
				elif state == State.RUNNING:
					ctrl.press()
			else:
				if state == State.RUNNING:
					ctrl.release()
		JOY_BUTTON_B:
			if ev.pressed:
				if chart_box != null and chart_box.visible:
					hide_chart()
				elif achievements_box != null and achievements_box.visible:
					hide_achievements()
				elif shop_box != null and shop_box.visible:
					hide_shop()
				elif endless_box != null and endless_box.visible:
					hide_endless()
				elif review_box.visible:
					_close_review()
				elif state == State.RUNNING:
					ctrl.brake_press()
				elif state == State.PAUSED:
					show_select()
				elif settings_box.visible:
					hide_settings()
				elif in_result or state == State.READY:
					if is_drill:
						is_drill = false
						show_chart("drill")
					else:
						show_select()
			else:
				if state == State.RUNNING:
					ctrl.brake_release()
		JOY_BUTTON_LEFT_SHOULDER:
			if ev.pressed:
				if select_box.visible and not in_subpanel:
					_select_kana_tab("hira")
				elif state == State.RUNNING:
					ctrl.brake_press()
			else:
				if state == State.RUNNING:
					ctrl.brake_release()
		JOY_BUTTON_DPAD_UP:
			if ev.pressed:
				if state == State.READY:
					start_run()
					ctrl.press()
				elif state == State.RUNNING:
					ctrl.press()
			else:
				if state == State.RUNNING:
					ctrl.release()
		JOY_BUTTON_DPAD_DOWN:
			if ev.pressed:
				if review_box.visible:
					if review_choices.size() > 1 and review_choices[1].visible and not review_choices[1].disabled:
						_answer_review(review_choices[1])
				elif state == State.RUNNING:
					ctrl.brake_press()
			else:
				if state == State.RUNNING:
					ctrl.brake_release()
		JOY_BUTTON_DPAD_LEFT:
			if ev.pressed:
				if review_box.visible:
					if review_choices.size() > 0 and review_choices[0].visible and not review_choices[0].disabled:
						_answer_review(review_choices[0])
				elif state == State.RUNNING:
					change_lane(-1)
		JOY_BUTTON_DPAD_RIGHT:
			if ev.pressed:
				if review_box.visible:
					if review_choices.size() > 2 and review_choices[2].visible and not review_choices[2].disabled:
						_answer_review(review_choices[2])
				elif state == State.RUNNING:
					change_lane(1)
		JOY_BUTTON_X, JOY_BUTTON_LEFT_STICK:
			if ev.pressed:
				if review_box.visible:
					if review_choices.size() > 0 and review_choices[0].visible and not review_choices[0].disabled:
						_answer_review(review_choices[0])
				elif state == State.RUNNING:
					ctrl.toggle_lock()
				elif in_result or state == State.PAUSED:
					reset_run()
				elif select_box.visible and not in_subpanel:
					show_achievements()
		JOY_BUTTON_Y:
			if ev.pressed:
				if title_box != null and title_box.visible:
					show_settings()
				elif review_box.visible:
					_replay_review()
				elif state == State.RUNNING:
					replay_voice()
				elif in_result:
					if btn_review.visible:
						_open_review()
				elif select_box.visible and not in_subpanel:
					show_shop()
		JOY_BUTTON_START:
			if ev.pressed:
				if title_box != null and title_box.visible:
					start_from_title()
				elif endless_box != null and endless_box.visible:
					start_endless()
				elif state == State.RUNNING:
					pause_game()
				elif state == State.PAUSED:
					resume()
				elif select_box.visible and not in_subpanel:
					show_endless()
		JOY_BUTTON_BACK:
			if ev.pressed:
				if chart_box != null and chart_box.visible:
					hide_chart()
				elif title_box != null and title_box.visible:
					get_tree().quit()
				elif achievements_box != null and achievements_box.visible:
					hide_achievements()
				elif shop_box != null and shop_box.visible:
					hide_shop()
				elif endless_box != null and endless_box.visible:
					hide_endless()
				elif review_box.visible:
					_close_review()
				elif settings_box.visible:
					hide_settings()
				elif select_box.visible and not in_subpanel:
					fade_transition(func(): show_title(), 0.2, 0.2)
				elif state == State.RUNNING:
					pause_game()
				elif state == State.PAUSED or in_result:
					if is_drill:
						is_drill = false
						show_chart("drill")
					else:
						show_select()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventJoypadMotion:
		if absf(ev.axis_value) > 0.35:
			_set_input_device("joypad")
		_handle_joy_motion(ev)
		return
	if ev is InputEventJoypadButton:
		_set_input_device("joypad")
		_handle_joy_button(ev)
		return
	if (ev is InputEventKey and not ev.echo) or (ev is InputEventMouseButton and ev.pressed):
		_set_input_device("keyboard")
	if not (ev is InputEventKey) or ev.echo:
		return
	if review_box.visible:
		if ev.pressed and ev.keycode == KEY_ESCAPE:
			_close_review()
		elif ev.pressed and ev.keycode == KEY_E:
			_replay_review()
		elif ev.pressed and ev.keycode in [KEY_1, KEY_2, KEY_3]:
			var choice := review_choices[ev.keycode - KEY_1]
			if choice.visible and not choice.disabled:
				_answer_review(choice)
		return
	var in_result := state == State.CLEARED or state == State.FAILED
	if title_box != null and title_box.visible:
		if ev.pressed and (ev.keycode == KEY_SPACE or ev.keycode == KEY_ENTER):
			start_from_title()
			return
		elif ev.pressed and ev.keycode == KEY_ESCAPE:
			get_tree().quit()
			return
	match ev.keycode:
		KEY_SPACE:
			if ev.pressed:
				if in_result:
					if result_time > 0.4:
						if is_drill: start_custom_drill()
						else: reset_run()
				elif state == State.READY:
					start_run(); ctrl.press()
				elif state == State.RUNNING:
					ctrl.press()
			else:
				ctrl.release()
		KEY_W, KEY_UP:
			if ev.pressed:
				if state == State.READY:
					start_run(); ctrl.press()
				elif state == State.RUNNING:
					ctrl.press()
			else:
				ctrl.release()
		KEY_S, KEY_DOWN:
			if ev.pressed and state == State.RUNNING: ctrl.brake_press()
			elif not ev.pressed: ctrl.brake_release()
		KEY_A, KEY_LEFT:
			if ev.pressed and state == State.RUNNING: change_lane(-1)
		KEY_D, KEY_RIGHT:
			if ev.pressed and state == State.RUNNING: change_lane(1)
		KEY_F:
			if ev.pressed and state == State.RUNNING: ctrl.toggle_lock()
		KEY_E:
			if ev.pressed: replay_voice()
		KEY_ESCAPE, KEY_P:
			if ev.pressed:
				if state == State.RUNNING: pause_game()
				elif state == State.PAUSED: resume()
				elif ev.keycode == KEY_ESCAPE:
					if chart_box != null and chart_box.visible: hide_chart()
					elif achievements_box != null and achievements_box.visible: hide_achievements()
					elif shop_box != null and shop_box.visible: hide_shop()
					elif endless_box != null and endless_box.visible: hide_endless()
					elif settings_box.visible: hide_settings()
					elif not select_box.visible and state != State.SELECT: show_select()
		KEY_R:
			if ev.pressed and state == State.PAUSED: reset_run()
		KEY_Q:
			if ev.pressed and state == State.PAUSED: show_select()
		KEY_B:
			if ev.pressed and (in_result or state == State.READY):
				if is_drill:
					is_drill = false
					show_chart("drill")
				else:
					show_select()
		KEY_N:
			if ev.pressed and in_result: go_next_level()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var index: int = ev.keycode - KEY_1
			if ev.pressed and select_box.visible and index < level_buttons.size():
				choose_level(int(level_buttons[index].get_meta("level_index")))
		KEY_F3:
			if ev.pressed: dev_mode = not dev_mode
