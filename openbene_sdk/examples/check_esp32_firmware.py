#!/usr/bin/env python3
"""
ESP32 串口诊断工具
把 ESP32 用 USB 连到电脑后运行此脚本。
自动找端口 → 读启动信息 → 判断固件类型。
"""
import serial
import serial.tools.list_ports
import time

def find_esp32_port():
    ports = list(serial.tools.list_ports.comports())
    print("检测到的串口：")
    for i, p in enumerate(ports):
        print(f"  [{i}] {p.device}  {p.description}")

    esp_ports = [p for p in ports if any(
        k in p.description.lower() for k in
        ['cp210', 'ch340', 'ch341', 'ftdi', 'usb serial', 'uart', 'esp']
    )]

    if not ports:
        print("\n[!] 没有找到任何串口，请检查 USB 连接和驱动")
        return None

    if len(esp_ports) == 1:
        print(f"\n自动选择: {esp_ports[0].device}")
        return esp_ports[0].device

    idx = input("\n输入端口编号 [0]: ").strip()
    return ports[int(idx) if idx else 0].device


def read_and_diagnose(port):
    print(f"\n[串口] 连接 {port} @ 115200...")
    try:
        ser = serial.Serial(port, 115200, timeout=2)
    except Exception as e:
        print(f"[!] 无法打开串口: {e}")
        return

    # ESP32 标准复位：RTS 对应 EN 脚，拉低再释放即复位
    # DTR 保持 False 避免进入 bootloader
    print("[串口] 正在重启 ESP32（RTS/EN 复位）...")
    ser.setDTR(False)
    ser.setRTS(True)   # EN = LOW → 进入复位
    time.sleep(0.2)
    ser.setRTS(False)  # EN = HIGH → 释放，开始启动
    ser.reset_input_buffer()

    print("[串口] 等待启动信息（8 秒）...\n")
    output_lines = []

    deadline = time.time() + 8.0
    while time.time() < deadline:
        try:
            line = ser.readline().decode('utf-8', errors='replace').strip()
            if line:
                print(f"  >> {line}")
                output_lines.append(line)
        except:
            break

    ser.close()

    # ── 诊断结论 ──
    print("\n──────── 诊断结论 ────────")
    all_text = ' '.join(output_lines).upper()

    if not output_lines:
        print("✗ 没有收到任何输出")
        print("  可能原因：")
        print("  a) ESP32 没有上电或 USB 线只充电不传数据")
        print("  b) 端口选错了")
        print("  c) 固件还在烧录中（等 10 秒再试）")
        return

    if 'WAITING A CLIENT CONNECTION' in all_text:
        print("✓ 固件：RTR_520（含 BLE）")
        print("  ESP32 正在广播蓝牙，手机 App 应该能搜到 'OpenBot: RTR_520'")
        print("  如果还搜不到：断电重启 ESP32 → 手机设置里删除旧配对 → 重新扫描")

    elif any(k in all_text for k in ['RTR_520', 'RTR520', 'BLE', 'BLUETOOTH']):
        print("✓ 固件：RTR_520（含 BLE）")
        print("  蓝牙已启动，请尝试重新扫描")

    elif 'R' in output_lines and len(output_lines) <= 3:
        print("✗ 固件：疑似 DIY / Arduino Nano 固件（无 BLE）")
        print("  ESP32 只打印了 'r'（ready 信号），没有 BLE 初始化输出")
        print("  → 需要用 Arduino IDE 重新烧录 RTR_520 固件")
        print("    1. 打开 openbot.ino")
        print("    2. 第 65 行改为：#define OPENBOT RTR_520")
        print("    3. 工具 → 开发板 → 选 'ESP32 Dev Module'")
        print("    4. 上传")

    else:
        print("? 无法自动判断，原始输出已打印在上方")
        print("  关键字：是否有 'Waiting a client connection' 或 'BLE'？")
        print("  如果都没有 → 固件可能是 DIY 版本，需要重新烧录")


if __name__ == '__main__':
    port = find_esp32_port()
    if port:
        read_and_diagnose(port)
