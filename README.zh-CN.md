# OpenBene

<p align="center">
  <img alt="Python Version" src="https://img.shields.io/badge/python-3.8%2B-blue">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green">
</p>

<p align="center"><strong>语言 / Languages:</strong> <a href="README.md">English</a> | 简体中文</p>

<p align="center"><strong>Phone as Body, PC as Brain</strong> - 面向 OpenBot 机器人工作流的公共平台层工具库。</p>

> 范围说明：
> `OpenBene` 是公开的平台层仓库。
> ROS2、建图、定位和其他内部 mobility 内容会在整理后按需下放。
> 参见 [docs/OPENBENE_SCOPE.md](docs/OPENBENE_SCOPE.md)。

## 概览

OpenBene 主要提供这些能力：

- 机器人控制用 Python SDK
- OpenBot 风格手机端工作流
- WebSocket 连接与自动发现
- 视频、传感器和录制支持
- 面向 ESP32 / OpenBot 的 BLE 手动控制工具

## 应用展示

<p align="center">
  <img alt="OpenBene 应用展示" src="docs/showcase/robot_app-showcase.svg" width="100%">
</p>

这张预览展示了已经导入到 `apps/robot_app/` 的机器人侧界面：

- 连接状态与 `Server Address`
- 实时 `Camera Preview`
- `Sensor Data`，包括 `Frames Sent`、`Sensor Updates`、`Battery Level`、`Accelerometer` 和 `Gyroscope`
- WebSocket、UDP 自动发现，以及 BLE / USB 控制链路

## 从这里开始

- PC 端 Python 控制：[openbene_sdk/README.md](openbene_sdk/README.md)
- 手机端 UI：[openbot-mobile-control/README.md](openbot-mobile-control/README.md)
- 导入的机器人 App：[apps/robot_app/README.md](apps/robot_app/README.md)
- 仓库地图与边界：[docs/architecture.md](docs/architecture.md)

## 工作区分层

- 主线公开内容：`openbene_sdk/`、`openbot-mobile-control/`、`apps/robot_app/`、`openbot/`、`docs/`
- 应用目录：`apps/`，用于放置独立的 Flutter 应用
- 辅助本地工作区：`openbene_mobility/`、`openbene_local/`

## 结构图

```text
OpenBene/
- docs/
- openbene_sdk/
- openbot/
- openbot-mobile-control/
- apps/
  - robot_app/
- openbene_mobility/
- openbene_local/
```

## 文档

- [docs/architecture.md](docs/architecture.md) - 架构与新手入口
- [openbene_sdk/README.md](openbene_sdk/README.md) - SDK 文档
- [apps/robot_app/README.md](apps/robot_app/README.md) - 导入的机器人 App 文档
- [openbot-mobile-control/releases/README.md](openbot-mobile-control/releases/README.md) - Android 版本与发布说明
- [docs/WINDOWS_BLE_CONTROL_RUNBOOK.md](docs/WINDOWS_BLE_CONTROL_RUNBOOK.md) - Windows BLE 控制流程
- [docs/OPENBENE_SCOPE.md](docs/OPENBENE_SCOPE.md) - 公共范围边界
- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) - 兼容指路页

## 许可证

MIT License。详见 [LICENSE](LICENSE)。
