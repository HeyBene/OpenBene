# Windows 端交接说明

iOS App（`com.openbene.zenohdemo`）不做任何改动。Windows 上只需要运行本仓库的电脑端，
协议、画面、控制、录制与 macOS 完全一致。

## 需要带走的文件

整个 `zenoh_ios/` 目录即可，缺一不可的是：

```text
zenoh_ios/scripts/run_pc.py          一键启动（Windows / macOS / Linux 通用）
zenoh_ios/scripts/run-pc.cmd         Windows 双击即可运行
zenoh_ios/pc/                        Python 接收端、录制、网页控制台
zenoh_ios/scripts/run-pc.sh          macOS 原脚本，可选
```

不需要带 `pc/.venv`、`.tools/`、`runs/`：Windows 上首次运行会自动重建。

## 前置条件

- Python 3.10+（安装时勾选 “Add python.exe to PATH”）。
- 手机与 Windows 电脑连同一个 Wi-Fi。
- 首次运行需要联网下载 `zenohd` 1.1.0（x86_64 Windows 版）和两个 Python 包
  （`eclipse-zenoh`、`mcap`）。

## 运行

在仓库根目录（`OpenBene_git/`）执行：

```powershell
python zenoh_ios\scripts\run_pc.py
```

或者双击 `zenoh_ios\scripts\run-pc.cmd`。脚本会依次完成：

1. 建 `zenoh_ios/pc/.venv` 并安装依赖；
2. 下载并解压 `zenoh_ios/.tools/zenohd.exe`；
3. 启动路由器（监听 `tcp/0.0.0.0:7447`）；
4. 启动接收端 + 网页控制台（`http://127.0.0.1:8080/`）；
5. 打印手机要填的地址，例如 `192.168.1.20:7447`；
6. 用默认浏览器打开控制台。

按 `Ctrl+C` 结束，录制文件在 `zenoh_ios/runs/`。

可选参数（环境变量）：

```powershell
$env:PORT=7447
$env:VIEW_PORT=8080
$env:DURATION=60          # 60 秒后自动退出
$env:OPEN_BROWSER=0       # 不自动开浏览器
$env:PYTHON=C:\Python312\python.exe
$env:ZENOHD=C:\tools\zenohd.exe
```

## 手机端

App 里「电脑地址」填 Windows 电脑的局域网 IP 加端口，例如 `192.168.1.20:7447`，
点「连接电脑」。采集设置里可选 5/10/15/30 fps、画面宽度 640/960/1280 px、
RGB/深度/置信度/位姿/IMU 传感器。iPhone 12 Pro 实测：15 fps 与 30 fps 均可达标，
单帧编码约 5 ms。

## 防火墙

第一次启动时 Windows 会弹窗，需要允许 `zenohd.exe` 在**专用网络**上接收 TCP 7447。
也可以管理员 PowerShell 手动添加：

```powershell
New-NetFirewallRule -DisplayName "OpenBene Zenoh" -Direction Inbound `
  -Protocol TCP -LocalPort 7447 -Action Allow -Profile Private
```

## 验证

- 浏览器打开 `http://127.0.0.1:8080/`，能看到 RGB、深度、置信度画面和帧率。
- 终端如果直接跑接收端，会每 2 秒打印一行：

```text
[stats]  15.0 fps  frames=1234  gaps=0  errors=0  mbps= 1.80  planes=rgb,depth,confidence,pose
```

  `gaps` 为帧号跳号数，0 表示没有丢帧；`mbps` 是实际带宽。
- 在网页上「开始录制」后，`zenoh_ios/runs/` 会出现 `.mcap` 和 `.mcap.meta.json`。

## 录制内容

```text
/openbene/<robot>/frame/meta        JSON  帧号、时间戳、pose、尺寸、内参、跟踪状态
/openbene/<robot>/frame/rgb         JPEG
/openbene/<robot>/frame/depth       PNG   16 位毫米
/openbene/<robot>/frame/confidence  PNG   0/1/2
/openbene/<robot>/status|telemetry|sensors|cmd|session  JSON
```

可直接用 Foxglove 或任意 MCAP 读取库打开。

## 主题与端口速查

| 用途 | 值 |
| --- | --- |
| 路由器监听 | `tcp/0.0.0.0:7447` |
| 接收端连接 | `tcp/127.0.0.1:7447` |
| 网页控制台 | `http://127.0.0.1:8080/` |
| 手机 → 电脑 | `openbene/<robot>/frame`、`status`、`telemetry`、`sensors` |
| 电脑 → 手机 | `openbene/<robot>/cmd` |

## 常见问题

- **手机连不上**：确认防火墙放行 TCP 7447；确认处于同一网段；部分路由器开启
  “AP 隔离”会禁止客户端互访；确认 7447 没有被别的程序占用。
- **端口被占用**：设置 `$env:PORT=7450`，重启脚本，手机地址端口同步改。
- **画面不刷新**：看终端 `[stats]` 行的帧率与 `gaps`；`live` 状态在
  `http://127.0.0.1:8080/state.json` 里。
- **ARM64 Windows**：官方只提供 x86_64 的 `zenohd`，脚本会下载 x64 版，Windows 会
  自动用兼容层运行，无需额外处理。
