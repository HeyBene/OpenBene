<h1 align="center">OpenBene</h1>

<p align="center">
  <img alt="Python Version" src="https://img.shields.io/badge/python-3.8%2B-blue">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green">
  <a href="https://github.com/HeyBene/OpenBene/discussions">
    <img alt="GitHub Discussions" src="https://img.shields.io/github/discussions/HeyBene/OpenBene">
  </a>
</p>

<p align="center"><strong>语言 / Languages：</strong> <a href="README.md">English</a> | 简体中文</p>

<p align="center"><strong>Phone as Body, PC as Brain</strong> - 一个面向 OpenBot 机器人工作流的公开平台层工具库。</p>

> 范围说明：
> `OpenBene` 是公开的平台层仓库。
> ROS2、建图、定位和内部 mobility 研发内容不会直接原样公开，而是整理后按需下放。
> 边界说明见 [docs/OPENBENE_SCOPE.md](docs/OPENBENE_SCOPE.md)。

<p align="center">
  <a href="https://github.com/HeyBene/OpenBene/discussions">
    <img alt="参与讨论" src="https://img.shields.io/badge/参与讨论-GitHub_Discussions-blue?style=for-the-badge">
  </a>
</p>

## 项目概览

OpenBene 主要负责这些可复用的平台层能力：

- 机器人控制 Python SDK
- OpenBot 风格手机端控制工作流
- WebSocket 通信与自动发现
- 视频、传感器和录制支持
- 面向 ESP32 / OpenBot 的 BLE 手动控制工具

## 架构

```text
PC (Python) -> WebSocket -> 手机 App -> USB/BLE -> 机器人控制器 -> 电机
```

## 快速开始

开始前先确认：

- Python 版本为 `3.8+`
- 手机和电脑在同一个局域网
- 手机 App 页面显示 `Waiting for PC...`
- 手机 App 页面显示有效的 `Server Address`

### 1. 准备手机 App

如果当前版本附带 Android 安装包，先看这里：

- [openbot-mobile-control/releases/README.md](openbot-mobile-control/releases/README.md)

如果你是从源码侧使用手机端：

- Flutter App: [openbot-mobile-control](openbot-mobile-control)

注意：

- 始终以 App 页面显示的 `Server Address` 为准。
- iOS 需要确认已经打开 Local Network 权限。

### 2. 安装 Python SDK

```bash
cd openbene_sdk
pip install -e .
```

可选但推荐：

```bash
python -m venv .venv
```

### 3. 运行完整示例

```bash
cd openbene_sdk/examples
python full_demo.py
```

这个示例会带你完成：

- 手动输入手机 IP 连接
- 自动发现连接
- 运动控制
- 视频预览
- 传感器读取
- 数据录制

成功的标志通常是：

- 示例能自动发现手机，或者用 App 显示的 IP 成功连上
- 控制命令能传到机器人
- 示例里开始出现视频或传感器输出

### 4. 基础 Python 示例

```python
from openbene import OpenBene

bot = OpenBene.auto_connect()
print(f"已连接到 {bot.ip}:{bot.port}")

bot.forward(0.5)

import time
time.sleep(2)

bot.stop()
bot.disconnect()
```

如果自动发现失败，请使用 App 显示的地址并先运行：

```bash
cd openbene_sdk/examples
python diagnose.py <phone_ip>
```

### 5. 快速排障

1. 确认手机和电脑在同一网段。
2. 以 App 显示的 `Server Address` 为准，不要手猜 IP。
3. Windows 下先检查 WebSocket 端口：

```powershell
Test-NetConnection -ComputerName <phone_ip> -Port 8765
```

4. 如果 `PingSucceeded=True` 但 `TcpTestSucceeded=False`，先关闭 VPN / 代理 / TUN 再试。
5. iOS 需要检查：
   `Settings -> Privacy & Security -> Local Network -> OpenBene = ON`

## SDK 入口

常用示例：

```bash
python examples/basic_control.py
python examples/interactive_control.py
python examples/video_display.py
python examples/video_recording_demo.py
python examples/data_collection.py
python examples/test_udp_discovery.py
python examples/diagnose.py <phone_ip>
```

如果你要在 Windows 上通过 BLE 手动控制 ESP32 / OpenBot 固件，参考：

- [docs/WINDOWS_BLE_CONTROL_RUNBOOK.md](docs/WINDOWS_BLE_CONTROL_RUNBOOK.md)

## 项目结构

```text
OpenBene/
├── .github/                     # GitHub 配置与工作流
├── docs/                        # 公共文档
├── openbene_sdk/                # Python SDK
│   ├── src/                     # SDK 核心代码
│   ├── examples/                # 示例脚本
│   └── tests/                   # SDK 测试
├── openbot/                     # 固件 / 硬件基线
├── openbot-mobile-control/      # Flutter 手机 App
├── README.md                    # 英文 README（默认）
├── README.zh-CN.md              # 简体中文 README
├── PROJECT_CONTEXT.md           # 架构与项目上下文
└── CHANGELOG.md                 # 更新日志
```

## 文档

- [openbene_sdk/README.md](openbene_sdk/README.md) - SDK 文档
- [openbot-mobile-control/releases/README.md](openbot-mobile-control/releases/README.md) - Android 安装包与发布说明
- [docs/WINDOWS_BLE_CONTROL_RUNBOOK.md](docs/WINDOWS_BLE_CONTROL_RUNBOOK.md) - Windows BLE 控制流程
- [docs/OPENBENE_SCOPE.md](docs/OPENBENE_SCOPE.md) - 公开范围边界
- [docs/MOBILITY_SYNC_RULES.md](docs/MOBILITY_SYNC_RULES.md) - 内部 mobility 能力下放到 OpenBene 的同步规则
- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) - 架构上下文
- [CHANGELOG.md](CHANGELOG.md) - 更新日志

## 参与贡献

欢迎贡献。

- [报告 Bug](https://github.com/HeyBene/OpenBene/issues/new?template=bug_report_CN.yml)
- [提出建议](https://github.com/HeyBene/OpenBene/issues/new?template=feature_request_CN.yml)
- [贡献指南](CONTRIBUTING.md)
- [GitHub Discussions](https://github.com/HeyBene/OpenBene/discussions)

## 致谢

本项目基于：

- [OpenBot](https://github.com/isl-org/OpenBot) - Intel ISL 的开源机器人平台

## 许可证

MIT License，详见 [LICENSE](LICENSE)。
