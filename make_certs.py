"""用 openssl 產生自簽憑證（含本機 IP 的 SAN）。

為什麼需要 https：
    Godot 4.7 的 Web 匯出一律要求 secure context（`window.isSecureContext`），
    連單執行緒版本也一樣 —— 那個檢查在 JS 裡寫死在 `if (supportsThreads)` 之外。
    瀏覽器只把 https:// 或 http://localhost 視為 secure context，
    區網 IP 走明文 http 永遠不算。

    伺服器端沒有任何設定能改變這一點，`isSecureContext` 由瀏覽器決定。

自簽憑證的信任問題：
    手機第一次連會跳「憑證無效」警告，要手動安裝並信任根憑證。
    `make_certs.py` 會一併產生 .cer 檔，手機用它匯入憑證設定就能永久信任。
"""

import ipaddress
import platform
import socket
import subprocess
import sys
from pathlib import Path

CERT_DIR = Path(__file__).resolve().parent / "build" / "certs"
KEY = CERT_DIR / "server.key"
CRT = CERT_DIR / "server.crt"
P12 = CERT_DIR / "server.p12"
CER = CERT_DIR / "server.cer"


def local_ips() -> list[str]:
    out = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith(("127.", "169.254.")):
                out.append(ip)
    except socket.gaierror:
        pass
    return sorted(set(out), key=lambda s: ipaddress.ip_address(s))


def find_openssl() -> str | None:
    """找 openssl。Windows 通常沒有，但 Git for Windows 會帶一個。"""
    exe = "openssl.exe" if platform.system() == "Windows" else "openssl"
    for candidate in [
        shutil_which(exe),
        r"C:\Program Files\Git\usr\bin\openssl.exe",
        r"C:\Program Files\Git\mingw64\bin\openssl.exe",
    ]:
        if candidate:
            return candidate
    return None


def shutil_which(name: str) -> str | None:
    import shutil

    return shutil.which(name)


def main() -> int:
    CERT_DIR.mkdir(parents=True, exist_ok=True)
    ips = local_ips()
    san_parts = ["DNS:localhost", "IP:127.0.0.1"]
    san_parts += [f"IP:{ip}" for ip in ips]

    if KEY.exists() and CRT.exists():
        print("[make_certs] 憑證已存在，略過產生。")
        print(f"[make_certs] 內容：{CRT}")
    else:
        openssl = find_openssl()
        if not openssl:
            print("[make_certs] 找不到 openssl。")
            print("[make_certs] 選項：")
            print("  1. 安裝 Git for Windows（內含 openssl）")
            print("  2. 用 Tailscale：tailscale cert <hostname>")
            print("  3. 用 Tailscale serve（免憑證，推薦）")
            return 1

        print(f"[make_certs] 使用 {openssl}")
        conf = CERT_DIR / "openssl.cnf"
        conf.write_text(
            "[req]\ndistinguished_name=dn\nx509_extensions=v3\nprompt=no\n"
            "[dn]\nCN=kana-run.local\n"
            "[v3]\n"
            "basicConstraints=CA:FALSE\n"
            "keyUsage=digitalSignature,keyEncipherment\n"
            "extendedKeyUsage=serverAuth\n"
            f"subjectAltName={','.join(san_parts)}\n",
            encoding="utf-8",
        )
        cmd = [
            openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", str(KEY), "-out", str(CRT), "-days", "825",
            "-config", str(conf),
        ]
        print("[make_certs] " + " ".join(cmd[:6]) + " …")
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print("[make_certs] 失敗：", r.stderr[:400])
            return 1

    # 給 iOS 用：.cer 可直接在「設定 → 一般 → VPN 與裝置管理」安裝
    try:
        subprocess.run(
            ["certutil", "-f", "-encode", str(CRT), str(CER)],
            capture_output=True, text=True, check=False,
        )
    except FileNotFoundError:
        pass

    print(f"[make_certs] 憑證：{CRT}")
    print(f"[make_certs] iOS 安裝檔：{CER}")
    print(f"[make_certs] 涵蓋的位址：localhost, 127.0.0.1, {', '.join(ips)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
