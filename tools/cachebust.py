"""匯出後的快取破壞：在 build/web/index.html 的 index.js 與 index.pck 參照加上 ?v=<時間戳>，
讓手機瀏覽器不會沿用舊版（serve_web.py 另外送 no-store 標頭）。export-web.bat 會自動呼叫。"""
import re, sys, time
from pathlib import Path
p = Path(__file__).resolve().parent.parent / "build" / "web" / "index.html"
s = p.read_text(encoding="utf-8")
v = time.strftime("%Y%m%d%H%M%S")
s = re.sub(r'src="index\.js(\?v=\d+)?"', f'src="index.js?v={v}"', s)
s = re.sub(r'"mainPack":\s*"index\.pck(\?v=\d+)?"', f'"mainPack":"index.pck?v={v}"', s)
if '<meta http-equiv="Cache-Control"' not in s:
    s = s.replace("<head>", '<head>\n<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">', 1)
p.write_text(s, encoding="utf-8")
print("cache-bust version", v, "mainPack ok" if f"index.pck?v={v}" in s else "WARN mainPack not found")
