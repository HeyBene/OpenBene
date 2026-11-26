#!/usr/bin/env python3
"""One command for the OpenBene Zenoh PC side, on Windows and macOS.

    python zenoh_ios/scripts/run_pc.py

Prepares the Python receiver environment, downloads the bundled `zenohd`
router on first run, starts the router and the receiver with the live
console, prints the address the iPhone should use, then waits for Ctrl+C.

The iPhone app is unchanged: it connects to `tcp/<this PC>:7447` and streams
the same ZPKD frames the macOS version receives.

Environment variables:
    PORT=7447            router port the phone connects to
    VIEW_PORT=8080       live console port
    OPEN_BROWSER=0       do not open a browser window
    DURATION=            stop automatically after N seconds
    PYTHON= ZENOHD=      use your own interpreter / router binary
"""

from __future__ import annotations

import os
import platform
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
TOOLS = HERE / ".tools"
RUNS = HERE / "runs"
ZENOH_VERSION = "1.1.0"


def say(message: str = "") -> None:
    try:
        print(message, flush=True)
    except UnicodeEncodeError:  # legacy Windows console code pages
        print(message.encode("ascii", "replace").decode("ascii"), flush=True)


def fail(message: str) -> "NoReturn":  # noqa: F821 - typing only
    say(f"error: {message}")
    sys.exit(1)


def venv_python(venv: Path) -> Path:
    if os.name == "nt":
        return venv / "Scripts" / "python.exe"
    return venv / "bin" / "python"


def prepare_python() -> Path:
    configured = os.environ.get("PYTHON")
    venv = HERE / "pc" / ".venv"
    python = Path(configured) if configured else venv_python(venv)
    if not python.exists():
        say("准备 Python 接收端环境（首次运行需要联网安装 eclipse-zenoh / mcap）...")
        subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
        python = venv_python(venv)
    probe = subprocess.run(
        [str(python), "-c", "import zenoh, mcap, openbene_receiver"],
        capture_output=True,
    )
    if probe.returncode != 0:
        subprocess.run([str(python), "-m", "pip", "install", "-q", "--upgrade", "pip"],
                       capture_output=True)
        result = subprocess.run([str(python), "-m", "pip", "install", "-q", "-e", str(HERE / "pc")])
        if result.returncode != 0:
            fail("安装 Python 依赖失败；请检查网络后重试")
    return python


def zenoh_target() -> str:
    system = platform.system()
    machine = platform.machine().lower()
    if system == "Windows":
        # Zenoh publishes only an x86_64 Windows build; Windows on ARM runs it
        # through the x64 emulation layer.
        return "x86_64-pc-windows-msvc"
    if system == "Darwin":
        return "aarch64-apple-darwin" if machine in ("arm64", "aarch64") else "x86_64-apple-darwin"
    if machine in ("arm64", "aarch64"):
        return "aarch64-unknown-linux-gnu"
    return "x86_64-unknown-linux-gnu"


def prepare_router() -> Path:
    configured = os.environ.get("ZENOHD")
    if configured:
        return Path(configured)
    name = "zenohd.exe" if os.name == "nt" else "zenohd"
    router = TOOLS / name
    if router.exists():
        return router

    target = zenoh_target()
    url = (
        f"https://github.com/eclipse-zenoh/zenoh/releases/download/{ZENOH_VERSION}/"
        f"zenoh-{ZENOH_VERSION}-{target}-standalone.zip"
    )
    say(f"准备 zenohd {ZENOH_VERSION}（{target}，首次运行需要联网下载）...")
    TOOLS.mkdir(parents=True, exist_ok=True)
    archive = TOOLS / "zenoh.zip"
    try:
        urllib.request.urlretrieve(url, archive)
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(TOOLS)
        archive.unlink(missing_ok=True)
    except Exception as error:
        fail(f"下载 zenohd 失败（{error}）；请手动安装后设置 ZENOHD=/path/to/zenohd")
    # The zip keeps the binary both at the root and under deps/.
    if not router.exists():
        fallback = TOOLS / "deps" / name
        if fallback.exists():
            shutil.copy2(fallback, router)
    if not router.exists():
        fail(f"压缩包里没有找到 {name}")
    if os.name != "nt":
        router.chmod(0o755)
    return router


def port_open(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(0.4)
        return probe.connect_ex((host, port)) == 0


def free_port(start: int, host: str) -> int:
    port = start
    while port_open(host, port) and port < start + 50:
        port += 1
    return port


def _usable_lan_ip(address: str | None) -> bool:
    if not address or address.startswith(("127.", "169.254.")):
        return False
    # 198.18.0.0/15 is used by VPN clients and benchmarks, not by home Wi-Fi.
    return not address.startswith(("198.18.", "198.19."))


def detect_ip() -> str | None:
    candidates: list[str] = []
    if platform.system() == "Darwin":
        for interface in ("en0", "en1", "en2", "en3"):
            result = subprocess.run(
                ["ipconfig", "getifaddr", interface], capture_output=True, text=True
            )
            if result.returncode == 0:
                candidates.append(result.stdout.strip())
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("192.168.255.255", 1))
            candidates.append(probe.getsockname()[0])
    except OSError:
        pass
    try:
        candidates.append(socket.gethostbyname(socket.gethostname()))
    except OSError:
        pass
    return next((address for address in candidates if _usable_lan_ip(address)), None)


def wait_until(check, seconds: float) -> bool:
    deadline = time.time() + seconds
    while time.time() < deadline:
        if check():
            return True
        time.sleep(0.25)
    return False


def main() -> int:
    port = int(os.environ.get("PORT", "7447"))
    view_port = int(os.environ.get("VIEW_PORT", "8080"))
    duration = os.environ.get("DURATION", "")
    open_browser = os.environ.get("OPEN_BROWSER", "1") != "0"

    RUNS.mkdir(parents=True, exist_ok=True)
    python = prepare_python()
    router_binary = prepare_router()

    view_port = free_port(view_port, "127.0.0.1")
    router = None
    if port_open("127.0.0.1", port):
        say(f"端口 {port} 已有监听，直接复用（若它不是 zenohd，请换 PORT=...）")
    else:
        log = RUNS / "zenohd.log"
        with log.open("w") as handle:
            router = subprocess.Popen(
                [str(router_binary), "--listen", f"tcp/0.0.0.0:{port}"],
                cwd=str(TOOLS),
                stdout=handle,
                stderr=subprocess.STDOUT,
            )
        if not wait_until(lambda: port_open("127.0.0.1", port), 12):
            fail(f"zenohd 在端口 {port} 上没有就绪（日志：{log}）")

    receiver_log = (RUNS / "receiver.log").open("w")
    receiver = subprocess.Popen(
        [str(python), "-m", "openbene_receiver.cli",
         "--endpoint", f"tcp/127.0.0.1:{port}",
         "--record-dir", str(RUNS),
         "--view", "--view-port", str(view_port), "--stats"]
        + (["--duration", duration] if duration else []),
        cwd=str(HERE / "pc"),
        stdout=receiver_log,
        stderr=subprocess.STDOUT,
    )

    url = f"http://127.0.0.1:{view_port}/"

    def viewer_ready() -> bool:
        if receiver.poll() is not None:
            fail(f"接收端启动失败，请查看 {RUNS / 'receiver.log'}")
        try:
            with urllib.request.urlopen(url + "state.json", timeout=1):
                return True
        except Exception:
            return False

    if not wait_until(viewer_ready, 15):
        fail(f"预览页没有就绪（日志：{RUNS / 'receiver.log'}）")

    lan = detect_ip()
    say()
    say("==============================================================")
    say(" OpenBene Zenoh 已在运行")
    say("==============================================================")
    say(f" 电脑端预览   : {url}")
    say(f" 手机填写地址 : {lan or '<电脑IP>'}:{port}")
    say(" 录制         : 默认关闭，在网页上点「开始录制」")
    say(f" 录制目录     : {RUNS}")
    say(" 结束全部     : 在本终端按 Ctrl+C")
    say("==============================================================")
    say()
    if os.name == "nt":
        say(f"若手机连不上，请允许 Windows 防火墙放行 zenohd 的 TCP {port} 入站。")

    if open_browser:
        try:
            import webbrowser
            webbrowser.open(url)
        except Exception:
            pass

    try:
        receiver.wait()
    except KeyboardInterrupt:
        pass
    finally:
        receiver_log.close()
        for process in (receiver, router):
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()

    say()
    recordings = sorted(RUNS.glob("*.mcap"), key=lambda item: item.stat().st_mtime, reverse=True)
    say("已停止。录制文件（若有）在 {}：".format(RUNS))
    if recordings:
        for item in recordings[:5]:
            say(f"  {item}")
    else:
        say("  （本次没有开始录制）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
