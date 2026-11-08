"""匯出後的快取破壞：把 build/web 的 index.js / .wasm / .pck / worklet 改名成 kr2_<時間戳>.*，
並改寫 index.html 的 executable 與 <script src>，手機一定抓新檔（serve_web.py 另送 no-store 標頭）。
export-web.bat 會自動呼叫。"""
import re
import shutil
import sys
import time
from pathlib import Path

EXTENSIONS = (".js", ".wasm", ".pck", ".audio.worklet.js", ".audio.position.worklet.js")

CLOUDFLARE_HEADERS = """/*
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  Access-Control-Allow-Origin: *

/index.html
  Cache-Control: no-cache, no-store, must-revalidate

/kr2_*
  Cache-Control: public, max-age=31536000, immutable

/*.wasm
  Content-Type: application/wasm
  Cache-Control: public, max-age=31536000, immutable

/*.pck
  Content-Type: application/octet-stream
  Cache-Control: public, max-age=31536000, immutable
"""


def cachebust(web: Path) -> str:
    html = web / "index.html"
    source = html.read_text(encoding="utf-8")
    executable = re.search(r'"executable":"(index|kr2_\d+)"', source)
    if not executable:
        raise ValueError("index.html has no recognized Godot executable")
    name = executable[1]
    script_ref = rf'src="{name}\.js(\?v=\d+)?"'
    if not re.search(script_ref, source):
        raise ValueError(f"index.html does not load {name}.js")
    assets = [web / (name + ext) for ext in EXTENSIONS]
    missing = [asset.name for asset in assets if not asset.is_file()]
    if missing:
        raise ValueError(f"Missing export files: {', '.join(missing)}")

    # Ensure Cloudflare Pages isolation and caching headers
    (web / "_headers").write_text(CLOUDFLARE_HEADERS, encoding="utf-8")

    if name != "index":
        return name

    version = f"kr2_{time.time_ns()}"
    updated = re.sub(script_ref, f'src="{version}.js"', source)
    updated = updated.replace('"executable":"index"', f'"executable":"{version}"')
    for ext in (".pck", ".wasm"):
        updated = updated.replace(f'"index{ext}":', f'"{version}{ext}":')
    if '<meta http-equiv="Cache-Control"' not in updated:
        updated = updated.replace("<head>", '<head>\n<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">', 1)

    # Publish the HTML only after every referenced asset is in place.
    for asset, ext in zip(assets, EXTENSIONS):
        shutil.copyfile(asset, web / (version + ext))
    pending_html = html.with_suffix(".html.tmp")
    pending_html.write_text(updated, encoding="utf-8")
    pending_html.replace(html)

    for asset in assets:
        asset.unlink()
    for ext in EXTENSIONS:
        for old in web.glob(f"kr2_*{ext}"):
            if re.fullmatch(rf"kr2_\d+{re.escape(ext)}", old.name) and old.name != version + ext and old.is_file():
                old.unlink()
    return version


if __name__ == "__main__":
    try:
        version = cachebust(Path(__file__).resolve().parent.parent / "build" / "web")
    except (OSError, ValueError) as error:
        sys.exit(f"cache-bust: {error}")
    print("cache-bust version", version, "ok")
