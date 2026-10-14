#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OpenBot 底盘 BLE 测试工具 (Windows + bleak)

扫描 (确认底盘在广播, 记下地址与信号强度):
    python tools/openbot_ble.py scan

状态自检 (连不上时先跑这个: 底盘还在广播吗? 本机是不是还占着链路?):
    python tools/openbot_ble.py state

只看遥测, 不下发任何驱动命令 (安全):
    python tools/openbot_ble.py watch --seconds 30

按时间脚本驱动; 时间的单位是秒, 到点执行, 中间自动续心跳和当前驱动命令:
    python tools/openbot_ble.py run "0:f" "1:w200" "3:c100,100" "8:c0,0"

堵转测试; 加命令的同时用手按住两个轮子, 读数必须为 0:
    python tools/openbot_ble.py run "0:w200" "1:c150,150" "12:c0,0"

命令速查 (BLE 与 USB 串口是同一套, 每条都以换行符结束):
    c<左>,<右>   左右轮 PWM, 取值 -255..255, 符号即方向
    w<毫秒>      轮速遥测间隔, 固件默认 1000
    h<毫秒>      心跳超时; 超过这个时间没再收到 h 消息, 固件就把两个轮子清零
    f            请求特性串, 回复形如 fRTR_520:v:i:s:b:wf:wb:lf:lb:ls:
    l<前>,<后>   前后灯亮度 0..255
    s<毫秒>      超声波上报间隔
    v<毫秒>      电池电压上报间隔
"""

import argparse
import asyncio
import re
import sys
import time

from bleak import BleakClient, BleakScanner

SERVICE_UUID = "61653dc3-4021-4d1e-ba83-8b4eec61d613"
CHAR_TX = "9bf1103b-834c-47cf-b149-c9e4bcf778a7"   # 底盘 -> 主机 (notify)
CHAR_RX = "06386c14-86ea-4d71-811c-48f97c58f8c9"   # 主机 -> 底盘 (write without response)

WHEEL_RE = re.compile(r"^w(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)")


class Session:
    """一条 BLE 会话: 记录并打印底盘发回来的所有文本帧。"""

    def __init__(self, client: BleakClient):
        self.client = client
        self.t0 = time.time()
        self.frames = []
        self.wheels = []

    def on_notify(self, _char, data: bytearray):
        text = data.decode("utf-8", errors="replace").strip()
        if not text:
            return
        self.frames.append(text)
        hit = WHEEL_RE.match(text)
        if hit:
            self.wheels.append((float(hit.group(1)), float(hit.group(2))))
        print("[%7.3f s] %s" % (time.time() - self.t0, text))

    async def send(self, cmd: str):
        await self.client.write_gatt_char(CHAR_RX, (cmd + "\n").encode(), response=False)

    def report_wheels(self):
        print("\n---- 轮速帧统计 ----")
        if not self.wheels:
            print("一条 w 帧都没收到 (检查是否发过 w<毫秒>, 以及底盘是否在发遥测)")
            return
        left = [w[0] for w in self.wheels]
        right = [w[1] for w in self.wheels]
        print("帧数 %d" % len(self.wheels))
        print("左轮 rpm: min %8.1f  max %8.1f  mean %8.1f" % (min(left), max(left), sum(left) / len(left)))
        print("右轮 rpm: min %8.1f  max %8.1f  mean %8.1f" % (min(right), max(right), sum(right) / len(right)))
        nonzero = sum(1 for w in self.wheels if abs(w[0]) > 0.5 or abs(w[1]) > 0.5)
        print("非零帧: %d / %d" % (nonzero, len(self.wheels)))


async def cmd_state(args):
    """连不上底盘时先看这里: 广播是否还在, 本机是否占着链路。"""
    print("1) 扫描广播, %.0f 秒 ..." % args.scan)
    found = await BleakScanner.discover(timeout=args.scan, return_adv=True)
    hits = []
    for addr, payload in found.items():
        device, adv = payload if isinstance(payload, tuple) else (payload, None)
        name = device.name or ""
        rssi = getattr(adv, "rssi", None)
        if rssi is None:
            rssi = getattr(device, "rssi", None)
        if args.name.lower() in name.lower():
            hits.append((name, addr, rssi))
    if hits:
        for name, addr, rssi in hits:
            print("   广播中: %s   %s   rssi=%s" % (name, addr, rssi))
    else:
        print("   没有扫到 %r 的广播。" % args.name)
        print("   底盘不广播的三个常见原因:")
        print("     - 没上电 (电池/开关)")
        print("     - 已经被别的设备连着: 手机上的 OpenBot App 占着连接 (ESP32 同时只接受一个连接)")
        print("     - 上一次连接没有正常结束, ESP32 以为自己还被连着, 于是不再广播")
        print("   处理: 关掉手机 App, 给底盘断电 3-5 秒再上电, 然后重跑 state")
    print("2) 本机是否还持有到它的链路 ...")
    if not hits:
        print("   没有广播, 跳过")
        return
    try:
        from winrt.windows.devices.bluetooth import BluetoothLEDevice
    except Exception as exc:
        print("   跳过 (没有 winrt 模块: %r)" % (exc,))
        return
    for name, addr, rssi in hits:
        try:
            number = int(addr.replace(":", ""), 16)
            dev = await BluetoothLEDevice.from_bluetooth_address_async(number)
            if dev is None:
                print("   %s: 本机拿不到设备对象 (没配对也没缓存过)" % addr)
            else:
                print("   %s: name=%r  connection_status=%s" % (addr, dev.name, dev.connection_status))
                dev.close()
        except Exception as exc:
            print("   %s: 查询失败 %r" % (addr, exc))
    print("   说明: DISCONNECTED 表示本机没有占着它; Connected 表示本机还连着, 需要先断开。")


async def find_device(name_prefix: str, address: str, scan_seconds: float):
    """返回一个 BLEDevice 对象。

    Windows 上必须把扫描得到的设备对象交给 BleakClient; 只给地址字符串时
    WinRT 后端会去找系统缓存, 经常报 Device ... was not found。
    """
    print("扫描 BLE 设备, %.0f 秒 ..." % scan_seconds)
    found = await BleakScanner.discover(timeout=scan_seconds, return_adv=True)
    devices = []
    for addr, payload in found.items():
        device, adv = payload if isinstance(payload, tuple) else (payload, None)
        rssi = getattr(adv, "rssi", None)
        if rssi is None:
            rssi = getattr(device, "rssi", None)
        devices.append((addr, device, rssi, device.name or ""))

    if address:
        for addr, device, rssi, name in devices:
            if addr.upper() == address.upper():
                print("按地址选中: %s  %s  rssi=%s" % (name or "(无名)", addr, rssi))
                return device
        print("这次扫描没看到 %s, 直接按地址字符串连接" % address)
        return address

    hits = [d for d in devices if name_prefix.lower() in d[3].lower()]
    named = [d for d in devices if d[3] and name_prefix.lower() not in d[3].lower()]
    unnamed = len(devices) - len(hits) - len(named)
    print("扫到 %d 个设备, 其中有名 %d 个, 无名 %d 个" % (len(devices), len(named) + len(hits), unnamed))
    for addr, device, rssi, name in sorted(named, key=lambda d: -(d[2] or -999)):
        print("  %-34s %s rssi=%s" % (name, addr, rssi))
    if not hits:
        print("\n没有找到名字里包含 %r 的设备。" % name_prefix)
        print("确认底盘已上电; 并确认手机 App 没有占着连接 (ESP32 同一时间只接受一个连接)。")
        sys.exit(2)
    hits.sort(key=lambda d: (d[2] is None, -(d[2] or 0)))
    addr, device, rssi, name = hits[0]
    print("\n选中: %s   %s   rssi=%s" % (name, addr, rssi))
    return device


async def run_session(args):
    target = await find_device(args.name, args.address, args.scan)
    session = None
    client = BleakClient(target, timeout=20)
    try:
        await client.connect()
        print("已连接 %s" % client.address)
        session = Session(client)
        await client.start_notify(CHAR_TX, session.on_notify)

        if args.heartbeat:
            await session.send("h%d" % args.heartbeat)
        if args.mode == "watch":
            await session.send("f")
            if args.interval_ms:
                await session.send("w%d" % args.interval_ms)
            print("只收遥测 %.0f 秒, 不发驱动命令 ..." % args.seconds)
            await asyncio.sleep(args.seconds)
        else:
            steps = []
            for item in args.steps:
                head, sep, cmd = item.partition(":")
                if not sep or not cmd.strip():
                    sys.exit("步骤格式应为 秒:命令, 例如 3:c100,100 ; 收到的是 %r" % item)
                steps.append((float(head), cmd.strip()))
            steps.sort(key=lambda s: s[0])
            await session.send("f")
            end_time = steps[-1][0] + args.settle
            print("开始执行 %d 个步骤, 最后一步 +%.1f 秒后结束" % (len(steps), args.settle))
            t0 = time.time()
            idx = 0
            drive = None
            next_tick = 0.0
            while True:
                elapsed = time.time() - t0
                while idx < len(steps) and steps[idx][0] <= elapsed:
                    cmd = steps[idx][1]
                    print(">>> t=%6.2f s   发送 %s" % (elapsed, cmd))
                    await session.send(cmd)
                    if cmd.startswith("c"):
                        drive = cmd
                    idx += 1
                if idx >= len(steps) and elapsed >= end_time:
                    break
                if elapsed >= next_tick:
                    if args.heartbeat:
                        await session.send("h%d" % args.heartbeat)
                    if drive:
                        await session.send(drive)
                    next_tick = elapsed + args.interval
                await asyncio.sleep(0.02)
    except KeyboardInterrupt:
        print("\n收到 Ctrl+C, 准备停车")
    finally:
        if session is not None:
            for _ in range(3):
                try:
                    await session.send("c0,0")
                    await asyncio.sleep(0.1)
                except Exception:
                    break
            session.report_wheels()
            try:
                await client.disconnect()
                print("已断开连接")
            except Exception:
                print("断开时出错, 建议给底盘断电重启一次")


def main():
    parser = argparse.ArgumentParser(description="OpenBot 底盘 BLE 测试工具")
    parser.add_argument("mode", choices=["scan", "state", "watch", "run"])
    parser.add_argument("steps", nargs="*", help="run 模式下的步骤, 形如 3:c100,100")
    parser.add_argument("--name", default="OpenBot", help="BLE 名字关键字, 默认 OpenBot")
    parser.add_argument("--address", default=None, help="直接指定 BLE 地址, 跳过名字匹配")
    parser.add_argument("--scan", type=float, default=8.0, help="扫描时长, 秒")
    parser.add_argument("--seconds", type=float, default=30.0, help="watch 模式持续时长, 秒")
    parser.add_argument("--interval-ms", type=int, default=200, help="发给底盘的 w<毫秒>, 0 表示不改")
    parser.add_argument("--interval", type=float, default=0.25, help="run 模式续心跳与重发命令的周期, 秒")
    parser.add_argument("--heartbeat", type=int, default=750, help="心跳超时毫秒, 0 表示不启用")
    parser.add_argument("--settle", type=float, default=2.0, help="最后一步之后再等几秒")
    args = parser.parse_args()

    if args.mode == "scan":
        asyncio.run(find_device(args.name, None, args.scan))
        return
    if args.mode == "state":
        asyncio.run(cmd_state(args))
        return
    if args.mode == "run" and not args.steps:
        sys.exit("run 模式需要至少一个步骤, 例如: run \"1:w200\" \"2:c120,120\" \"5:c0,0\"")
    asyncio.run(run_session(args))


if __name__ == "__main__":
    main()
