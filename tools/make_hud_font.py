"""Rebuild assets/fonts/hud_cjk.ttf (Noto Sans TC, OFL) as a small subset.
pip install fonttools ; download NotoSansTC[wght].ttf from github.com/google/fonts (ofl/notosanstc)
python tools/make_hud_font.py NotoSansTC[wght].ttf   -- add characters to EXTRA when HUD text changes."""
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset
EXTRA = "暫停繼續重來重播加速煞車下一關回選鎖定新紀錄＋聽音模式連擊提示答對撞錯漏題過關失敗時間重玩加速煞車換線開始羅馬拼音星秒第一關行★☆○×・ー、。！？：（）「」音樂音效語音音量評價等級完美評級"
f = instancer.instantiateVariableFont(TTFont(sys.argv[1]), {"wght": 800})
import glob, pathlib
# also every non-ASCII character used in scripts / config, so new HUD text never shows as tofu
src = "".join(pathlib.Path(p).read_text(encoding="utf-8") for p in glob.glob("scripts/*.gd") + glob.glob("config/*.json"))
used = "".join(sorted({ch for ch in src if ord(ch) > 0x7F}))
text = "".join(chr(c) for c in range(0x3040, 0x3100)) + "".join(chr(c) for c in range(0x20, 0x7F)) + EXTRA + used
o = subset.Options(); o.layout_features = ["*"]; o.name_IDs = ["*"]
s = subset.Subsetter(o); s.populate(text=text); s.subset(f)
f.save("assets/fonts/hud_cjk.ttf")
