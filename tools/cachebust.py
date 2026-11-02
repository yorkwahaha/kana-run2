"""匯出後的快取破壞：把 build/web 的 index.js / .wasm / .pck / worklet 改名成 kr2_<時間戳>.*，
並改寫 index.html 的 executable 與 <script src>，手機一定抓新檔（serve_web.py 另送 no-store 標頭）。
export-web.bat 會自動呼叫。"""
import re, time
from pathlib import Path
web = Path(__file__).resolve().parent.parent / "build" / "web"
v = "kr2_" + time.strftime("%Y%m%d%H%M%S")
for old in web.glob("kr2_*"):
    old.unlink()
for ext in (".js", ".wasm", ".pck", ".audio.worklet.js", ".audio.position.worklet.js"):
    src = web / ("index" + ext)
    if src.exists():
        src.replace(web / (v + ext))
p = web / "index.html"
s = p.read_text(encoding="utf-8")
s = re.sub(r'src="index\.js(\?v=\d+)?"', f'src="{v}.js"', s)
s = s.replace('"executable":"index"', f'"executable":"{v}"')
s = s.replace('"index.pck":', f'"{v}.pck":').replace('"index.wasm":', f'"{v}.wasm":')
if '<meta http-equiv="Cache-Control"' not in s:
    s = s.replace("<head>", '<head>\n<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">', 1)
p.write_text(s, encoding="utf-8")
print("cache-bust version", v, "ok" if f'"executable":"{v}"' in s else "WARN executable not replaced")
