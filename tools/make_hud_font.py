"""Rebuild assets/fonts/hud_cjk.ttf (Noto Sans TC, OFL) as a small subset.
pip install fonttools ; download NotoSansTC[wght].ttf from github.com/google/fonts (ofl/notosanstc)
python tools/make_hud_font.py NotoSansTC[wght].ttf   -- add characters to EXTRA when HUD text changes."""
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset
EXTRA = "下一關回選鎖定新紀錄＋聽音模式連擊提示答對撞錯漏題過關失敗時間重玩加速煞車換線開始羅馬拼音星秒第一關行★☆○×・ー、。！？：（）「」"
f = instancer.instantiateVariableFont(TTFont(sys.argv[1]), {"wght": 800})
text = "".join(chr(c) for c in range(0x3040, 0x3100)) + "".join(chr(c) for c in range(0x20, 0x7F)) + EXTRA
o = subset.Options(); o.layout_features = ["*"]; o.name_IDs = ["*"]
s = subset.Subsetter(o); s.populate(text=text); s.subset(f)
f.save("assets/fonts/hud_cjk.ttf")
