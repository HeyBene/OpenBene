#!/usr/bin/env python3
"""
ESP32 BLE Debug Tool for OpenBot RTR_520
=========================================
直接通过 BLE 连接到 ESP32，绕过手机 App，
用于排查电机无法运动的底层问题。

功能：
  1. 扫描并连接 OpenBot BLE 设备
  2. 读取 ESP32 上报的所有传感器数据（电压、车速、声呐、保险杠）
  3. 请求 f 特征包，验证固件车型与功能列表
  4. 发送增量驱动命令，确认 ESP32 是否收到并执行
  5. 检测心跳超时、保险杠急停等可能阻止运动的状态

使用方法：
  pip install bleak
  python esp32_ble_debug.py

注意：运行需要 Bluetooth 权限，Windows 需要 Windows 10 v1903+ 及 BLE 适配器
"""

import asyncio
import sys
import time
import re
from typing import Optional

try:
    from bleak import BleakScanner, BleakClient
    from bleak.backends.device import BLEDevice
except ImportError:
    print("[!] 需要安装 bleak: pip install bleak")
    sys.exit(1)

# ── OpenBot ESP32 BLE UUID（与 bluetooth_service.dart 和 openbot.ino 一致）──
SERVICE_UUID    = "61653dc3-4021-4d1e-ba83-8b4eec61d613"
CHAR_RX_UUID    = "06386c14-86ea-4d71-811c-48f97c58f8c9"  # 写往 ESP32
CHAR_TX_UUID    = "9bf1103b-834c-47cf-b149-c9e4bcf778a7"  # ESP32 通知

# ── 控制常量 ──
MAX_PWM = 255          # ESP32 期望 -255 ～ 255 整数


# ═══════════════════════════════════════════════════════════
# 工具函数
# ═══════════════════════════════════════════════════════════

def parse_esp_message(raw: str) -> dict:
    """
    解析 ESP32 发来的传感器行。
    协议（来自 openbot.ino sendData 调用）：
      v<val>          电压, e.g. "v11.54"
      w<left>,<right> 车轮 RPM
      s<dist>         声呐距离 cm
      b<id>           保险杠碰撞 id
      f<type>:<caps>  特征包, e.g. "fRTR_520:v:i:s:b:wf:wb:lf:lb:ls:"
    """
    if not raw:
        return {}

    header = raw[0]
    body   = raw[1:]

    if header == 'v':
        return {"type": "voltage", "voltage": float(body)}

    if header == 'w':
        parts = body.split(',')
        if len(parts) >= 2:
            return {"type": "wheel", "rpm_left": float(parts[0]), "rpm_right": float(parts[1])}

    if header == 's':
        return {"type": "sonar", "distance_cm": int(body)}

    if header == 'b':
        return {"type": "bumper", "collision_id": body}

    if header == 'f':
        colon_idx = body.find(':')
        robot_type = body[:colon_idx] if colon_idx != -1 else body
        caps = body[colon_idx+1:].rstrip(':').split(':') if colon_idx != -1 else []
        return {"type": "features", "robot_type": robot_type, "capabilities": caps}

    return {"type": "unknown", "raw": raw}


def make_ctrl_cmd(left: int, right: int) -> bytes:
    """生成控制命令，格式 c<left>,<right>\n"""
    return f"c{left},{right}\n".encode()


# ═══════════════════════════════════════════════════════════
# 主扫描 + 连接逻辑
# ═══════════════════════════════════════════════════════════

async def scan_openbot_devices(timeout: float = 8.0) -> list[BLEDevice]:
    """扫描名称包含 'OpenBot' 的 BLE 设备"""
    print(f"[BLE] 扫描中（{timeout:.0f}s）…")
    devices = await BleakScanner.discover(timeout=timeout)
    bots = [d for d in devices if d.name and "openbot" in d.name.lower()]
    return bots


async def run_debug(device: BLEDevice):
    """连接设备并运行完整诊断流程"""

    print(f"\n[BLE] 连接 → {device.name} ({device.address})")

    received_lines: list[str] = []
    _buf = ""

    def notification_handler(sender, data: bytearray):
        nonlocal _buf
        text = data.decode(errors="replace").replace("\x00", "")
        _buf += text
        while "\n" in _buf:
            line, _buf = _buf.split("\n", 1)
            line = line.strip()
            if line:
                received_lines.append(line)
                parsed = parse_esp_message(line)
                _log_parsed(parsed, line)

    def _log_parsed(p: dict, raw: str):
        t = p.get("type", "?")
        if t == "voltage":
            v = p["voltage"]
            status = "✓ 正常" if v > 9.0 else ("⚠ 低压" if v > 6.0 else "✗ 极低/未接电")
            print(f"  [电压]   {v:.2f} V  {status}")
        elif t == "wheel":
            print(f"  [车速]   左={p['rpm_left']:.1f} RPM  右={p['rpm_right']:.1f} RPM")
        elif t == "sonar":
            d = p["distance_cm"]
            flag = "  ⚠ <10cm 会触发 STOP（检查前方障碍物）" if d < 10 else ""
            print(f"  [声呐]   {d} cm{flag}")
        elif t == "bumper":
            print(f"  [保险杠] 碰撞 id={p['collision_id']}  ← 急停触发，需解除！")
        elif t == "features":
            print(f"  [特征]   车型={p['robot_type']}  能力={p['capabilities']}")
            if p["robot_type"] != "RTR_520":
                print(f"           ⚠⚠ 固件车型不是 RTR_520！"
                      f"请确认 openbot.ino 中 #define OPENBOT RTR_520 已烧录")
        else:
            print(f"  [原始]   {raw}")

    async with BleakClient(device.address) as client:
        print(f"[BLE] 已连接  MTU={client.mtu_size}")

        # ── 1. 枚举服务/特征 ──
        print("\n── 步骤 1/5：枚举 BLE 服务 ──")
        found_openbot_service = False
        found_rx = False
        found_tx = False
        for svc in client.services:
            s_id = svc.uuid.lower()
            if s_id == SERVICE_UUID:
                found_openbot_service = True
                print(f"  ✓ OpenBot 服务: {svc.uuid}")
            for char in svc.characteristics:
                c_id = char.uuid.lower()
                props = char.properties
                if c_id == CHAR_RX_UUID:
                    found_rx = True
                    print(f"  ✓ RX（写入控制）: {char.uuid}  属性={props}")
                if c_id == CHAR_TX_UUID:
                    found_tx = True
                    print(f"  ✓ TX（接收通知）: {char.uuid}  属性={props}")

        if not found_openbot_service:
            print("  ✗ 未找到 OpenBot 服务 UUID！")
            print("    可能原因：固件未以 RTR_520 编译（没有 HAS_BLUETOOTH=1）")
            print("    → 请确认 openbot.ino #define OPENBOT RTR_520 并重新烧录")
            return
        if not found_rx:
            print("  ✗ 未找到 RX 写入特征")
            return
        if not found_tx:
            print("  ⚠ 未找到 TX 通知特征（无法接收传感器数据）")

        # ── 2. 启用 TX 通知 ──
        print("\n── 步骤 2/5：启用传感器通知 ──")
        if found_tx:
            await client.start_notify(CHAR_TX_UUID, notification_handler)
            print("  ✓ TX 通知已开启")

        # ── 3. 请求特征包（f 命令）──
        print("\n── 步骤 3/5：请求固件特征 ──")
        await client.write_gatt_char(CHAR_RX_UUID, b"f\n", response=False)
        await asyncio.sleep(0.5)

        # ── 4. 启用电压 + 车速报告 ──
        print("\n── 步骤 4/5：启用传感器上报（500ms 间隔）──")
        await client.write_gatt_char(CHAR_RX_UUID, b"v500\n", response=False)
        await asyncio.sleep(0.1)
        await client.write_gatt_char(CHAR_RX_UUID, b"w500\n", response=False)
        await asyncio.sleep(0.1)
        await client.write_gatt_char(CHAR_RX_UUID, b"s500\n", response=False)
        print("  ✓ 等待传感器数据（2 秒）…")
        await asyncio.sleep(2.0)

        # ── 5. 发送测试驱动命令，验证 ESP32 是否执行 ──
        print("\n── 步骤 5/5：发送驱动命令测试 ──")
        print("  ⚠ 车辆将会运动！请确保小车放置安全！")
        print("  按 Enter 继续，Ctrl+C 跳过…")
        try:
            # 非阻塞等待：asyncio 无法直接 input()，使用 run_in_executor
            loop = asyncio.get_event_loop()
            await loop.run_in_executor(None, input)
        except (KeyboardInterrupt, EOFError):
            print("  跳过驱动测试")
        else:
            rpm_before_left = 0.0
            rpm_before_right = 0.0

            # 记录当前 RPM 基线
            for line in received_lines[-10:]:
                p = parse_esp_message(line)
                if p.get("type") == "wheel":
                    rpm_before_left  = p["rpm_left"]
                    rpm_before_right = p["rpm_right"]

            # 发送 10% 速度前进
            speed_10 = int(0.10 * MAX_PWM)
            cmd_10 = make_ctrl_cmd(speed_10, speed_10)
            print(f"  → 发送 c{speed_10},{speed_10} (10% 速度)…")
            await client.write_gatt_char(CHAR_RX_UUID, cmd_10, response=False)
            await asyncio.sleep(1.5)

            # 停止
            await client.write_gatt_char(CHAR_RX_UUID, b"c0,0\n", response=False)

            # 检查 RPM 变化
            rpm_after_left = rpm_before_left
            rpm_after_right = rpm_before_right
            for line in received_lines[-10:]:
                p = parse_esp_message(line)
                if p.get("type") == "wheel":
                    rpm_after_left  = p["rpm_left"]
                    rpm_after_right = p["rpm_right"]

            print(f"\n  10% 测试结果：")
            if max(rpm_after_left, rpm_after_right) > 0.5:
                print(f"  ✓ 车轮已转动：左={rpm_after_left:.1f} RPM  右={rpm_after_right:.1f} RPM")
            else:
                print(f"  ✗ 车轮未转动（RPM ≈ 0）→ 10% 占空比不足以启动 520 电机")
                print(f"    建议：在手机 App 中选择 'RTR_520' 驱动档（gain=1.2, minStart=22%）")

            # 22% 速度前进（与 App RTR_520 profile minStart 对应）
            speed_22 = int(0.22 * MAX_PWM)
            cmd_22 = make_ctrl_cmd(speed_22, speed_22)
            print(f"\n  → 发送 c{speed_22},{speed_22} (22% 速度 = RTR_520 profile minStart)…")
            await client.write_gatt_char(CHAR_RX_UUID, cmd_22, response=False)
            await asyncio.sleep(1.5)
            await client.write_gatt_char(CHAR_RX_UUID, b"c0,0\n", response=False)
            await asyncio.sleep(0.5)

            for line in received_lines[-5:]:
                p = parse_esp_message(line)
                if p.get("type") == "wheel":
                    print(f"  22% 测试结果：左={p['rpm_left']:.1f} RPM  右={p['rpm_right']:.1f} RPM")
                    if max(p["rpm_left"], p["rpm_right"]) > 0.5:
                        print(f"  ✓ 确认：RTR_520 需要 ≥22% 占空比才能启动")
                    break

        # ── 最终报告 ──
        print("\n══════ 诊断报告 ══════")
        _print_summary(received_lines)

        if found_tx:
            await client.stop_notify(CHAR_TX_UUID)


def _print_summary(lines: list[str]):
    has_voltage  = False
    has_wheel    = False
    has_features = False
    has_bumper   = False
    last_v = None
    robot_type = None
    capabilities = []
    bumper_events = []

    for line in lines:
        p = parse_esp_message(line)
        t = p.get("type")
        if t == "voltage":
            has_voltage = True
            last_v = p["voltage"]
        elif t == "wheel":
            has_wheel = True
        elif t == "features":
            has_features = True
            robot_type = p["robot_type"]
            capabilities = p["capabilities"]
        elif t == "bumper":
            has_bumper = True
            bumper_events.append(p["collision_id"])

    print(f"  固件特征包收到: {'✓' if has_features else '✗ (f 命令无响应？)'}",
          f" → 车型={robot_type}" if robot_type else "")
    if robot_type and robot_type != "RTR_520":
        print(f"  ⚠⚠ 车型应为 RTR_520，当前固件报告 {robot_type}")
        print(f"     → 请重新烧录 openbot.ino（已修复为 #define OPENBOT RTR_520）")
    print(f"  电压上报: {'✓ ' + str(round(last_v,2)) + 'V' if has_voltage else '✗'}")
    print(f"  车轮速度上报: {'✓ 传感器正常' if has_wheel else '✗ 或 RPM 全为 0'}")
    if has_bumper:
        print(f"  ⚠ 保险杠急停事件: {bumper_events}  ← 这会阻止运动！")

    print()
    print("── 可能导致 RTR_520 不动的原因（按优先级）──")
    print("  1. 固件未烧录 RTR_520：")
    print("       openbot.ino Line 65 已修复为 #define OPENBOT RTR_520")
    print("       → 用 Arduino IDE 以 ESP32 Dev Module 板型重新烧录")
    print()
    print("  2. App 驱动档未切换为 RTR_520：")
    print("       手机 App 连接页面 → 选 'RTR_520' 驱动档")
    print("       （gain=1.2，minStart=22%，克服 520 电机静摩擦）")
    print()
    print("  3. 心跳超时（断连后 ctrl=0）：")
    print("       PC SDK 需发送 h1000（1秒心跳间隔）")
    print("       否则固件 1s 无命令时自动归零")
    print()
    print("  4. 声呐 STOP_DISTANCE 触发（<10cm 前方有障碍物）：")
    if has_voltage and last_v is not None and last_v < 9.0:
        print(f"  5. ⚠ 电压 {last_v:.2f}V 偏低（<9V），电机驱动力不足！请充电")
    else:
        print("  5. 电压正常（若未满足 9V 阈值则电机供电不足）")


# ═══════════════════════════════════════════════════════════
# 入口
# ═══════════════════════════════════════════════════════════

async def main():
    print("═" * 55)
    print("  OpenBot RTR_520 ESP32 BLE 诊断工具")
    print("═" * 55)

    # 1. 扫描
    bots = await scan_openbot_devices(timeout=8.0)

    if not bots:
        print("\n[!] 未发现 OpenBot BLE 设备")
        print("    可能原因：")
        print("    a) 固件编译为 DIY（无 BLE） → 须重烧 RTR_520")
        print("    b) 设备未开机或超出范围")
        print("    c) 已有其他设备连接（BLE 单连接限制）")
        return

    print(f"\n发现 {len(bots)} 台 OpenBot 设备：")
    for i, d in enumerate(bots):
        print(f"  [{i}] {d.name}  地址={d.address}  RSSI={d.rssi} dBm")

    if len(bots) == 1:
        chosen = bots[0]
    else:
        idx = input("选择设备编号 [0]: ").strip()
        chosen = bots[int(idx) if idx else 0]

    await run_debug(chosen)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[中断] 已退出")
