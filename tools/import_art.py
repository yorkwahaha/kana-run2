"""Copy + downsize the hand-made art (屁卡手, box: /workspace/kana-run-2.0/art) into res://art/.
Run on the box:  python3 tools/import_art.py /workspace/kana-run-2.0/art
- big props / backgrounds are shrunk to a sensible on-screen size (web pck size)
- runner sheets are scaled x0.75 (anchors scaled too) and their JSON is baked into
  scripts/art_manifest.gd (JSON files are not exported by default)
- every texture gets a .import with lossy compression (+mipmaps for 3D)"""
import sys, os, json, shutil, glob
from PIL import Image
SRC = sys.argv[1] if len(sys.argv) > 1 else "/workspace/kana-run-2.0/art"
A = SRC + "/assets"
OUT = "art"
shutil.rmtree(OUT, ignore_errors=True)
files = []  # (res path, mipmaps, lossy)

def put(src, dst, max_side=None, scale=None, mip=False, lossy=True, rgb=False):
    im = Image.open(src)
    im = im.convert("RGB" if rgb else "RGBA")
    if scale:
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    if max_side and max(im.size) > max_side:
        f = max_side / max(im.size)
        im = im.resize((round(im.width * f), round(im.height * f)), Image.LANCZOS)
    p = f"{OUT}/{dst}"
    os.makedirs(os.path.dirname(p), exist_ok=True)
    im.save(p)
    files.append((p, mip, lossy))
    return im.size

# --- stage (zone 1)
put(f"{A}/batch01/bg/z1_bg_0_sky.webp", "stage/sky.png", rgb=True)
put(f"{A}/batch02/bg/z1_far_skyline.png", "stage/far_skyline.png")
put(f"{A}/batch01/bg/z1_track_tile.webp", "stage/track_tile.png", max_side=512, mip=True, rgb=True)
put(f"{A}/batch02/bg/z1_near_sidewalk_tile.png", "stage/sidewalk_tile.png", max_side=512, mip=True)
props = {}
for n in ["house_a", "house_b", "shop", "wall", "sakura_big", "sakura_small"]:
    props[n] = put(f"{A}/batch03/bg/z1_prop_{n}.png", f"stage/props/{n}.png", max_side=640, mip=True)
for n in ["bench", "planter", "shrub", "lamp", "vending", "fence"]:
    props[n] = put(f"{A}/batch07/props/z1_prop_{n}.png", f"stage/props/{n}.png", max_side=512, mip=True)
# --- tablet + shield vfx
put(f"{A}/batch01/tablet/tablet_normal.png", "tablet/tablet_normal.png", mip=True)
put(f"{A}/batch01/tablet/tablet_shield_overlay.png", "tablet/tablet_shield_overlay.png", mip=True)
put(f"{A}/batch01/tablet/tablet_shatter.png", "tablet/tablet_shatter.png", scale=0.5, mip=True)
for n in ["appear", "loop", "hit", "break"]:
    put(f"{A}/batch01/vfx/boss_shield_{n}.png", f"vfx/boss_shield_{n}.png", scale=0.5, mip=True)
put(f"{A}/batch02/particles/sparks_atlas.png", "vfx/sparks_atlas.png", lossy=False)
put(f"{A}/batch02/particles/petals_atlas.png", "vfx/petals_atlas.png", lossy=False)
put(f"{A}/batch02/particles/speedlines_atlas.png", "vfx/speedlines_atlas.png", lossy=False)
# --- HUD (no-text versions)
ui = {
 "btn_accel_normal": "batch02/ui_notext/btn_accel_icon_normal.png", "btn_accel_pressed": "batch02/ui_notext/btn_accel_icon_pressed.png",
 "btn_brake_normal": "batch02/ui_notext/btn_brake_icon_normal.png", "btn_brake_pressed": "batch02/ui_notext/btn_brake_icon_pressed.png",
 "btn_lock_off": "batch02/ui_notext/btn_lock_off.png", "btn_lock_on": "batch02/ui_notext/btn_lock_on.png", "btn_lock_pressed": "batch02/ui_notext/btn_lock_pressed.png",
 "btn_pause_normal": "batch01/ui/btn_pause_normal.png", "btn_pause_pressed": "batch01/ui/btn_pause_pressed.png",
 "btn_primary_normal": "batch02/ui_notext/btn_primary_normal.png", "btn_primary_pressed": "batch02/ui_notext/btn_primary_pressed.png", "btn_primary_disabled": "batch02/ui_notext/btn_primary_disabled.png",
 "btn_secondary_normal": "batch02/ui_notext/btn_secondary_normal.png", "btn_secondary_pressed": "batch02/ui_notext/btn_secondary_pressed.png", "btn_secondary_disabled": "batch02/ui_notext/btn_secondary_disabled.png",
 "hp_frame": "batch02/ui_notext/hp_frame.png", "hp_fill": "batch01/ui/hp_fill.png", "hp_lag": "batch01/ui/hp_lag.png", "icon_heart": "batch02/ui_notext/icon_heart.png",
 "timer_panel": "batch01/ui/timer_panel.png", "icon_timer": "batch01/ui/icon_timer.png", "combo_badge": "batch01/ui/combo_badge.png",
 "speedo_panel": "batch01/ui/speedo_panel.png", "speedo_needle": "batch01/ui/speedo_needle.png",
 "shield_counter_panel": "batch01/ui/shield_counter_panel.png", "shield_pip_empty": "batch01/ui/shield_pip_empty.png", "shield_pip_full": "batch01/ui/shield_pip_full.png",
 "judge_ok": "batch01/ui/judge_ok.png", "judge_ng": "batch01/ui/judge_ng.png",
}
for k, v in ui.items():
    put(f"{A}/{v}", f"ui/{k}.png", lossy=False)
for f in glob.glob(f"{A}/batch04/pause/*.png") + glob.glob(f"{A}/batch04/countdown/*.png"):
    put(f, "ui/" + os.path.basename(f), lossy=False)
for f in glob.glob(f"{A}/batch04/stage_select/*.png") + glob.glob(f"{A}/batch04/results/*.png"):
    b = os.path.basename(f)
    if "star_" in b and ("_56" in b or "_96" in b): continue
    put(f, "ui/" + b, lossy=False)
put(f"{A}/batch04/stage_select/select_bg_1080x2340.webp", "ui/select_bg.png", max_side=1400, rgb=True)
put(f"{A}/batch04/results/result_bg_1080x2340.webp", "ui/result_bg.png", max_side=1400, rgb=True)
# --- runner sheets (x0.75)
RS = 0.75
runner = {}
for j in sorted(glob.glob(f"{A}/batch07/*/runner_*_sheet.json")):
    d = json.load(open(j))
    n = d["name"]
    sz = put(j.replace(".json", ".png"), f"runner/{n}.png", scale=RS)
    runner[n] = {"fw": round(d["frame_w"] * RS), "fh": round(d["frame_h"] * RS), "frames": d["frames"], "cols": d["cols"],
                 "rows": d["rows"], "fps": d["fps"], "loop": bool(d.get("loop", False)),
                 "ax": d["ground_anchor"]["x"] * RS, "ay": d["ground_anchor"]["y"] * RS}
# return frames into the run loop (asset_list.csv, v7 rows)
ret = {"brake": 9, "lane_left": 4, "lane_right": 9, "hit_correct": 0, "hit_wrong": 10, "hit_shield": 11}
for k, v in ret.items():
    runner[k]["return_frame"] = v
# --- app icon
put(f"{A}/batch04/app_icon/icon_master_1024.png", "icon/icon_512.png", max_side=512, rgb=True, lossy=False)
# --- fonts (license next to them)
os.makedirs(f"{OUT}/fonts", exist_ok=True)
shutil.copy(f"{SRC}/fonts/OFL.txt", f"{OUT}/fonts/OFL-ZenMaruGothic.txt")

# .import files: lossy for big art, mipmaps for 3D
for p, mip, lossy in files:
    with open(p + ".import", "w") as f:
        f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n')
        f.write(f"compress/mode={1 if lossy else 0}\ncompress/lossy_quality=0.8\n")
        f.write(f"mipmaps/generate={'true' if mip else 'false'}\n")
        f.write("process/fix_alpha_border=true\ndetect_3d/compress_to=0\n")

# manifest
L = ["extends RefCounted", "## Generated by tools/import_art.py - every runtime art file is preloaded here (web export).", ""]
def const_dict(name, mapping):
    L.append(f"const {name} := {{")
    for k, v in mapping.items():
        L.append(f'\t"{k}": preload("res://{v}"),')
    L.append("}")
L.append('const SKY := preload("res://art/stage/sky.png")')
L.append('const FAR := preload("res://art/stage/far_skyline.png")')
L.append('const TRACK := preload("res://art/stage/track_tile.png")')
L.append('const SIDEWALK := preload("res://art/stage/sidewalk_tile.png")')
L.append('const TABLET := preload("res://art/tablet/tablet_normal.png")')
L.append('const TABLET_SHIELD := preload("res://art/tablet/tablet_shield_overlay.png")')
L.append('const TABLET_SHATTER := preload("res://art/tablet/tablet_shatter.png")')
L.append('const FONT_KANA := preload("res://art/fonts/kana_main.ttf")')
L.append('const ICON := preload("res://art/icon/icon_512.png")')
const_dict("PROPS", {k: f"art/stage/props/{k}.png" for k in props})
L.append("const PROP_SIZE := " + json.dumps({k: list(v) for k, v in props.items()}))
const_dict("SHIELD", {n: f"art/vfx/boss_shield_{n}.png" for n in ["appear", "loop", "hit", "break"]})
const_dict("VFX", {n: f"art/vfx/{n}_atlas.png" for n in ["sparks", "petals", "speedlines"]})
uifiles = sorted(os.path.basename(p)[:-4] for p, _, _ in files if p.startswith("art/ui/"))
const_dict("UI", {k: f"art/ui/{k}.png" for k in uifiles})
const_dict("RUNNER_TEX", {k: f"art/runner/{k}.png" for k in runner})
L.append("const RUNNER := " + json.dumps(runner))
open("scripts/art_manifest.gd", "w").write("\n".join(L) + "\n")
print(len(files), "textures; runner", list(runner))

# kana font: Zen Maru Gothic Bold (OFL), subset to kana + a few marks
from fontTools import subset
opts = subset.Options(); opts.layout_features = ["*"]
fnt = subset.load_font(f"{SRC}/fonts/ZenMaruGothic-Bold.ttf", opts)
sub = subset.Subsetter(opts)
sub.populate(text="".join(chr(c) for c in range(0x3040, 0x3100)) + "?！!〜ー・0123456789")
sub.subset(fnt)
subset.save_font(fnt, f"{OUT}/fonts/kana_main.ttf", opts)
