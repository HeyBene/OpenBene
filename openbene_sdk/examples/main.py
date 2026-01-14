#!/usr/bin/env python3
"""
OpenBene 控制面板

交互式入口脚本，整合所有功能：
- 基础控制 (前进/后退/转向)
- 赛车模式 (WASD 实时控制)
- 视频显示
- 数据采集
- 传感器查看

运行方式：
    python main.py
"""

import subprocess
import sys
import time

sys.path.insert(0, '../src')

# 自动安装 pynput（如果未安装）
PYNPUT_AVAILABLE = False
try:
    from pynput import keyboard
    PYNPUT_AVAILABLE = True
except ImportError:
    pass

from openbene import OpenBene


def clear_screen():
    """清屏"""
    import os
    os.system('cls' if os.name == 'nt' else 'clear')


def print_header(bot: OpenBene):
    """打印头部信息"""
    print("=" * 50)
    print("OpenBene 控制面板")
    print("=" * 50)
    status = "已连接" if bot.connected else "未连接"
    print(f"当前连接: {bot.ip}:{bot.port} ({status})")
    print("=" * 50)


def print_menu():
    """打印主菜单"""
    print("\n请选择功能:")
    print("  1. 基础控制 (前进/后退/转向)")
    print("  2. 赛车模式 (WASD 实时控制)")
    print("  3. 视频显示")
    print("  4. 数据采集")
    print("  5. 传感器查看")
    print("  6. 设置")
    print("  0. 退出")
    print()


# ==================== 功能模块 ====================

def basic_control(bot: OpenBene):
    """基础控制模式"""
    print("\n" + "=" * 40)
    print("基础控制模式")
    print("=" * 40)
    print("命令:")
    print("  w - 前进    s - 后退")
    print("  a - 左转    d - 右转")
    print("  x - 停止    q - 返回")
    print()

    speed = 0.5
    duration = 0.5

    while True:
        try:
            cmd = input(f"[速度:{speed:.1f}] 输入命令: ").strip().lower()

            if cmd == 'q':
                bot.stop()
                break
            elif cmd == 'w':
                print("前进...")
                bot.move_forward(speed, duration)
            elif cmd == 's':
                print("后退...")
                bot.move_backward(speed, duration)
            elif cmd == 'a':
                print("左转...")
                bot.rotate_left(speed, duration)
            elif cmd == 'd':
                print("右转...")
                bot.rotate_right(speed, duration)
            elif cmd == 'x':
                print("停止")
                bot.stop()
            elif cmd.startswith('speed '):
                try:
                    speed = float(cmd.split()[1])
                    speed = max(0.1, min(1.0, speed))
                    print(f"速度设置为: {speed:.1f}")
                except:
                    print("格式: speed 0.5")
            elif cmd.startswith('duration '):
                try:
                    duration = float(cmd.split()[1])
                    print(f"持续时间设置为: {duration:.1f}秒")
                except:
                    print("格式: duration 0.5")
            else:
                print("未知命令，输入 q 返回")
        except KeyboardInterrupt:
            bot.stop()
            break


def racing_mode(bot: OpenBene):
    """赛车模式（WASD实时控制）"""
    if not PYNPUT_AVAILABLE:
        print("\n赛车模式需要 pynput 库")
        print("正在自动安装...")
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "pynput"])
            print("安装完成，请重新运行程序")
        except:
            print("安装失败，请手动运行: pip install pynput")
        return

    # 导入赛车控制器
    try:
        from racing_control import RacingController
        controller = RacingController(bot, base_speed=0.7)
        controller.run()
    except ImportError:
        print("\n未找到 racing_control.py")
        print("请确保 racing_control.py 在同一目录下")


def video_display(bot: OpenBene):
    """视频显示"""
    try:
        import cv2
    except ImportError:
        print("\n视频显示需要 OpenCV")
        print("请运行: pip install opencv-python")
        return

    print("\n" + "=" * 40)
    print("视频显示模式")
    print("=" * 40)
    print("按 Q 键退出")
    print()

    try:
        for frame in bot.video_stream():
            cv2.imshow("OpenBene Camera", frame)
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break
    except KeyboardInterrupt:
        pass
    finally:
        cv2.destroyAllWindows()
        print("视频显示已停止")


def data_collection(bot: OpenBene):
    """数据采集模式"""
    print("\n" + "=" * 40)
    print("数据采集模式")
    print("=" * 40)

    output_dir = input("输出目录 (默认 ./dataset): ").strip()
    if not output_dir:
        output_dir = "./dataset"

    print(f"\n正在录制到: {output_dir}")
    print("使用 WASD 控制机器人采集数据")
    print("按 Ctrl+C 停止录制")
    print()

    bot.start_recording(output_dir)

    try:
        speed = 0.5
        while True:
            cmd = input("命令 (w/s/a/d/x/q): ").strip().lower()
            if cmd == 'q':
                break
            elif cmd == 'w':
                bot.forward(speed)
            elif cmd == 's':
                bot.backward(speed)
            elif cmd == 'a':
                bot.turn_left(speed)
            elif cmd == 'd':
                bot.turn_right(speed)
            elif cmd == 'x':
                bot.stop()
    except KeyboardInterrupt:
        pass
    finally:
        bot.stop_recording()
        print(f"\n录制完成: {bot.recorder.frame_count} 帧")


def sensor_view(bot: OpenBene):
    """传感器查看"""
    print("\n" + "=" * 40)
    print("传感器数据")
    print("=" * 40)
    print("按 Ctrl+C 停止")
    print()

    try:
        while True:
            sensors = bot.get_sensors()
            accel = sensors.get('accelerometer')
            gyro = sensors.get('gyroscope')
            battery = sensors.get('battery_level')

            print("\r", end="")
            if accel:
                print(f"加速度: X={accel['x']:+.2f} Y={accel['y']:+.2f} Z={accel['z']:+.2f}  ", end="")
            if gyro:
                print(f"陀螺仪: X={gyro['x']:+.2f} Y={gyro['y']:+.2f} Z={gyro['z']:+.2f}  ", end="")
            if battery is not None:
                print(f"电量: {battery:.0f}%  ", end="")

            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\n")


def settings_menu(bot: OpenBene):
    """设置菜单"""
    print("\n" + "=" * 40)
    print("设置")
    print("=" * 40)
    print(f"当前连接: {bot.ip}:{bot.port}")
    print(f"机器人名称: {bot.name}")
    print(f"机器人类型: {bot.robot_type}")
    print()
    print("(设置功能开发中...)")
    input("按回车返回...")


# ==================== 主程序 ====================

def main():
    """主程序入口"""
    clear_screen()
    print("=" * 50)
    print("OpenBene 控制面板")
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

            while True:
                clear_screen()
                print_header(bot)
                print_menu()

                try:
                    choice = input("选择 [0-6]: ").strip()

                    if choice == '0':
                        print("\n再见!")
                        break
                    elif choice == '1':
                        basic_control(bot)
                    elif choice == '2':
                        racing_mode(bot)
                    elif choice == '3':
                        video_display(bot)
                    elif choice == '4':
                        data_collection(bot)
                    elif choice == '5':
                        sensor_view(bot)
                    elif choice == '6':
                        settings_menu(bot)
                    else:
                        print("无效选择，请输入 0-6")
                        time.sleep(1)

                except KeyboardInterrupt:
                    print("\n\n按 0 退出程序")
                    time.sleep(1)

    except Exception as e:
        print(f"\n连接失败: {e}")
        print("请确保:")
        print("  1. 手机和电脑在同一WiFi网络")
        print("  2. 手机App已启动并显示IP地址")


if __name__ == "__main__":
    main()
