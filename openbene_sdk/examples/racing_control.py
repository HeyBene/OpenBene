#!/usr/bin/env python3
"""
OpenBene 赛车风格实时控制

像 QQ飞车/极速飞车 一样的控制体验:
- 实时响应: 按下即动，松开即停
- 圆弧转弯: 差速控制实现平滑转弯
- 漂移效果: 按住 Shift 急转

控制:
    W - 前进
    S - 后退
    A - 左转 (边走边转)
    D - 右转 (边走边转)
    Shift+A/D - 漂移
    +/- - 调速
    ESC - 退出
"""

import sys
import threading
import time

sys.path.insert(0, '../src')

try:
    from pynput import keyboard
except ImportError:
    print("需要安装 pynput 库:")
    print("  pip install pynput")
    print("或者:")
    print("  cd openbene_sdk && pip install -e \".[keyboard]\"")
    sys.exit(1)

from openbene import OpenBene


class RacingController:
    """赛车风格实时控制器"""

    def __init__(self, bot: OpenBene, base_speed: float = 0.7):
        self.bot = bot
        self.base_speed = base_speed
        self.pressed_keys = set()
        self.running = False

        # 转向参数 (可调整以获得不同的手感)
        self.turn_ratio = 0.4       # 圆弧转弯时内轮速度比例 (0-1)
        self.drift_ratio = -0.3     # 漂移时内轮反转比例 (负值)
        self.spin_speed = 0.6       # 原地转向速度

    def calculate_motors(self) -> tuple:
        """根据当前按键计算电机速度"""
        keys = self.pressed_keys
        speed = self.base_speed

        # 检测漂移模式 (Shift 键)
        drift = 'shift' in keys

        # 检测方向键
        forward = 'w' in keys
        backward = 's' in keys
        left = 'a' in keys
        right = 'd' in keys

        # 无按键则停止
        if not (forward or backward or left or right):
            return 0, 0

        # 计算基础速度
        if forward:
            base = speed
        elif backward:
            base = -speed
        else:
            base = 0

        # 初始化电机速度
        left_motor = base
        right_motor = base

        # 转向计算
        if left:
            if drift and base != 0:
                # 漂移左转：左轮反转，形成急转
                left_motor = base * self.drift_ratio
            elif base != 0:
                # 圆弧左转：左轮减速
                left_motor = base * self.turn_ratio
            else:
                # 原地左转
                left_motor = -speed * self.spin_speed
                right_motor = speed * self.spin_speed

        elif right:
            if drift and base != 0:
                # 漂移右转：右轮反转
                right_motor = base * self.drift_ratio
            elif base != 0:
                # 圆弧右转：右轮减速
                right_motor = base * self.turn_ratio
            else:
                # 原地右转
                left_motor = speed * self.spin_speed
                right_motor = -speed * self.spin_speed

        # 限制范围
        left_motor = max(-1.0, min(1.0, left_motor))
        right_motor = max(-1.0, min(1.0, right_motor))

        return left_motor, right_motor

    def update_loop(self):
        """持续更新电机状态的线程"""
        last_left, last_right = 0, 0
        last_print_time = 0

        while self.running:
            left, right = self.calculate_motors()

            # 只在变化时发送命令 (减少网络开销)
            if (left, right) != (last_left, last_right):
                if left == 0 and right == 0:
                    self.bot.stop()
                else:
                    self.bot.drive(left, right)
                last_left, last_right = left, right

                # 显示状态 (每 0.2 秒最多一次)
                now = time.time()
                if now - last_print_time > 0.2:
                    if left == 0 and right == 0:
                        status = "停止"
                    else:
                        status = f"L:{left:+.2f} R:{right:+.2f}"
                        if 'shift' in self.pressed_keys:
                            status += " [漂移]"
                    print(f"\r速度 {int(self.base_speed * 100)}% | {status}      ", end='', flush=True)
                    last_print_time = now

            time.sleep(0.03)  # ~30 FPS 更新率

    def on_press(self, key):
        """按键按下事件"""
        try:
            k = key.char.lower()
            self.pressed_keys.add(k)

            # 调速
            if k == '+' or k == '=':
                self.base_speed = min(1.0, self.base_speed + 0.1)
                print(f"\r速度调整到 {int(self.base_speed * 100)}%                  ")
            elif k == '-' or k == '_':
                self.base_speed = max(0.1, self.base_speed - 0.1)
                print(f"\r速度调整到 {int(self.base_speed * 100)}%                  ")

        except AttributeError:
            # 特殊键
            if key == keyboard.Key.shift or key == keyboard.Key.shift_l or key == keyboard.Key.shift_r:
                self.pressed_keys.add('shift')
            elif key == keyboard.Key.esc:
                self.running = False
                return False  # 停止监听器

    def on_release(self, key):
        """按键释放事件"""
        try:
            k = key.char.lower()
            self.pressed_keys.discard(k)
        except AttributeError:
            if key == keyboard.Key.shift or key == keyboard.Key.shift_l or key == keyboard.Key.shift_r:
                self.pressed_keys.discard('shift')

    def print_instructions(self):
        """打印控制说明"""
        print("\n" + "=" * 50)
        print("🏎️  赛车风格实时控制")
        print("=" * 50)
        print("\n控制方式:")
        print("  W     - 前进")
        print("  S     - 后退")
        print("  A     - 左转 (边走边转 = 圆弧)")
        print("  D     - 右转 (边走边转 = 圆弧)")
        print("  W+A   - 前进同时左转")
        print("  W+D   - 前进同时右转")
        print("\n高级控制:")
        print("  Shift+A - 漂移左转")
        print("  Shift+D - 漂移右转")
        print("  +/-     - 调整速度")
        print("  ESC     - 退出")
        print("\n" + "=" * 50)
        print(f"当前速度: {int(self.base_speed * 100)}%")
        print("=" * 50 + "\n")

    def run(self):
        """启动控制"""
        self.print_instructions()
        self.running = True

        # 启动更新线程
        update_thread = threading.Thread(target=self.update_loop, daemon=True)
        update_thread.start()

        print("控制已启动，按 ESC 退出...\n")

        # 启动键盘监听 (主线程)
        try:
            with keyboard.Listener(
                on_press=self.on_press,
                on_release=self.on_release
            ) as listener:
                listener.join()
        except KeyboardInterrupt:
            pass
        finally:
            self.running = False
            self.bot.stop()
            print("\n\n控制已停止")


def main():
    print("\n" + "=" * 50)
    print("OpenBene 赛车控制")
    print("=" * 50)

    # 获取手机IP
    phone_ip = input("\n请输入手机IP地址: ").strip()
    if not phone_ip:
        print("未输入IP地址，退出")
        return

    try:
        print(f"\n正在连接到 {phone_ip}...")
        with OpenBene(phone_ip) as bot:
            print(f"已连接到 {phone_ip}")

            # 获取初始速度
            speed_input = input("初始速度 (0.1-1.0, 默认0.7): ").strip()
            if speed_input:
                try:
                    speed = float(speed_input)
                    speed = max(0.1, min(1.0, speed))
                except ValueError:
                    speed = 0.7
            else:
                speed = 0.7

            controller = RacingController(bot, base_speed=speed)
            controller.run()

    except Exception as e:
        print(f"\n连接失败: {e}")
        print("请确保:")
        print("  1. 手机和电脑在同一WiFi网络")
        print("  2. 手机App已启动并显示IP地址")


if __name__ == "__main__":
    main()
