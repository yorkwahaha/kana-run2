"""區網測試用伺服器（https）。

為什麼一定要 https：
    Godot 4.7 的 Web 匯出一律要求 secure context，也就是 `window.isSecureContext`。
    連單執行緒版本也一樣 —— 那個檢查在 index.js 裡寫死在
    `if (supportsThreads)` 區塊之外，不是關掉執行緒就能跳過的。

    瀏覽器只把 https:// 與 http://localhost 視為 secure context，
    區網 IP 走明文 http 永遠不算。伺服器端沒有任何設定能改變這點，
    `isSecureContext` 是瀏覽器根據協定決定的。

    所以要嘛上 https，要嘛用 localhost（實機做不到），本檔走前者。

自簽憑證的代價：
    手機第一次連會跳「憑證無效」。iOS 用 build/certs/server.cer 匯入
    「設定 → 一般 → VPN 與裝置管理」安裝並信任後就永久有效。
    Android 用「設定 → 安全性 → 加密與憑證 → 安裝憑證 → CA 憑證」。

用法：
    python make_certs.py          # 產生憑證（只需一次）
    python serve_web.py            # 預設 8443 (https)
    python serve_web.py 9000
    python serve_web.py 8080 http  # 退回明文（僅供除錯，Godot 會拒絕）
"""

import functools
import http.server
import socket
import socketserver
import ssl
import sys
from pathlib import Path

DEFAULT_PORT = 8443
ROOT = Path(__file__).resolve().parent
WEB_DIR = ROOT / "build" / "web"
CERT_DIR = ROOT / "build" / "certs"


class Handler(http.server.SimpleHTTPRequestHandler):
    """補上跨來源隔離標頭，並在非 localhost 時提示憑證問題。"""

    def end_headers(self):
        # 現在有 https 了，這兩個標頭會真正生效。
        # thread_support 目前是關的所以非必要，但將來若開回執行緒就需要。
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        # 平板載入時會噴幾百行，只留非 200 與主要資源。
        status = str(args[1]) if len(args) > 1 else ""
        path = str(args[0]) if args else ""
        if status.startswith("2") and not any(
            k in path for k in (".wasm", ".pck")
        ):
            return
        super().log_message(fmt, *args)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def local_ips() -> list[str]:
    """列出實體網卡的 IPv4。跳過 loopback 與 169.254。"""
    out = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith(("127.", "169.254.")):
                out.append(ip)
    except socket.gaierror:
        pass
    return sorted(set(out))


def main() -> int:
    if not WEB_DIR.is_dir():
        print(f"[serve_web] 找不到 {WEB_DIR}")
        print("[serve_web] 先跑 export-web.bat 產生 Web 版。")
        return 1

    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    want_plain = len(sys.argv) > 2 and sys.argv[2].lower() in ("http", "plain")
    scheme = "http"

    ctx = None
    crt = CERT_DIR / "server.crt"
    key = CERT_DIR / "server.key"
    if not want_plain:
        if not (crt.exists() and key.exists()):
            print(f"[serve_web] 找不到憑證：{crt}")
            print("[serve_web] 先跑：python make_certs.py")
            print("[serve_web] 或用明文模式（Godot 會拒絕）：python serve_web.py 8080 http")
            return 1
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(certfile=crt, keyfile=key)
        scheme = "https"

    handler = functools.partial(Handler, directory=str(WEB_DIR))
    httpd = Server(("", port), handler)
    if ctx is not None:
        httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)

    print(f"[serve_web] 服務 {WEB_DIR}")
    print(f"[serve_web] {scheme}://localhost:{port}/")
    for ip in local_ips():
        print(f"[serve_web] {scheme}://{ip}:{port}/   ← 平板／手機用這個")
    if ctx is not None:
        print()
        print("[serve_web] 自簽憑證：手機會跳「憑證無效」警告。")
        cer = CERT_DIR / "server.cer"
        if cer.exists():
            print(f"[serve_web]   iOS     設定 → 一般 → VPN 與裝置管理 → 匯入 {cer}")
        print("[serve_web]   Android 設定 → 安全性 → 加密與憑證 → 安裝憑證 → CA 憑證")
    else:
        print()
        print("[serve_web] ★ 明文模式：Godot 會顯示 Secure Context 錯誤，僅供除錯。")
    print("[serve_web] Ctrl+C 停止。")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[serve_web] 停止。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
