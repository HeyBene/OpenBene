#!/usr/bin/env python3
"""
OpenBene 键盘控制

使用 WASD 键控制机器人

控制:
    W - 前进
    S - 后退
    A - 左转
    D - 右转
    SPACE/回车 - 停止
    +/- - 调整速度
    Q - 退出
"""

import sys
import time
sys.path.insert(0, '../src')

from openbene import OpenBene


class KeyboardController:
    """终端键盘控制器"""

    def __init__(self, bot: OpenBene, speed: float = 0.6):
        self.bot = bot
        self.speed = speed
        self.running = False

    def print_instructions(self):
        print("\n" + "=" * 50)
        print("键盘控制已启动")
        print("=" * 50)
        print("\n控制:")
        print("  W - 前进")
        print("  S - 后退")
        print("  A - 左转")
        print("  D - 右转")
        print("  回车/空格 - 停止")
        print("  + - 加速")
        print("  - - 减速")
        print("  Q - 退出")
        print("\n" + "=" * 50)
        print(f"当前速度: {int(self.speed * 100)}%")
        print("=" * 50 + "\n")

    def handle_command(self, key: str) -> bool:
        key = key.strip().lower()

        if key == 'w':
            print(f"→ 前进 ({int(self.speed * 100)}%)")
            self.bot.forward(self.speed)

        elif key == 's':
            print(f"← 后退 ({int(self.speed * 100)}%)")
            self.bot.backward(self.speed)

        elif key == 'a':
            print(f"↺ 左转 ({int(self.speed * 100)}%)")
            self.bot.turn_left(self.speed)

        elif key == 'd':
            print(f"↻ 右转 ({int(self.speed * 100)}%)")
            self.bot.turn_right(self.speed)

        elif key == '' or key == ' ':
            print("■ 停止")
            self.bot.stop()

        elif key == '+' or key == '=':
            self.speed = min(1.0, self.speed + 0.1)
            print(f"速度增加到 {int(self.speed * 100)}%")
            self.bot.stop()

        elif key == '-' or key == '_':
            self.speed = max(0.1, self.speed - 0.1)
            print(f"速度降低到 {int(self.speed * 100)}%")
            self.bot.stop()

        elif key == 'q':
            print("\n退出...")
            self.bot.stop()
            return False

        else:
            print(f"未知命令: '{key}' (使用 W/A/S/D/Q)")

        return True

    def run(self):
        self.print_instructions()
        self.running = True

        try:
            while self.running:
                key = input("命令> ")
                if not self.handle_command(key):
                    break

        except KeyboardInterrupt:
            print("\n\n用户中断")
            self.bot.stop()

        finally:
            self.running = False
            print("\n键盘控制已停止")


def main():
    print("\n" + "=" * 50)
    print("OpenBene 键盘控制")
    print("=" * 50)

    # 获取手机IP
    phone_ip = input("\n请输入手机IP地址: ").strip()
    if not phone_ip:
        print("未输入IP地址，退出")
        return

    try:
        print(f"\n正在连接到 {phone_ip}...")
        with OpenBene(phone_ip) as bot:
            print(f"已连接到 {phone_ip}\n")
            controller = KeyboardController(bot, speed=0.6)
            controller.run()

    except Exception as e:
        print(f"\n连接失败: {e}")
        print("请确保:")
        print("  1. 手机和电脑在同一WiFi网络")
        print("  2. 手机App已启动Server")


if __name__ == "__main__":
    main()
