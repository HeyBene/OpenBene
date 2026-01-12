"""
OpenBene 交互式控制台

运行后可以通过输入命令来控制机器人
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from openbene import OpenBene
import time

def print_help():
    """打印帮助信息"""
    print("""
========== OpenBene 控制命令 ==========

运动控制:
  w / forward [速度] [时间]    - 前进 (默认速度0.5，时间1秒)
  s / backward [速度] [时间]   - 后退
  a / left [速度] [时间]       - 左转
  d / right [速度] [时间]      - 右转
  x / stop                     - 停止

精确控制:
  drive <左轮> <右轮> [时间]   - 双轮独立控制 (-1.0 到 1.0)

视频:
  video                        - 打开视频窗口 (按q关闭)
  video off                    - 关闭视频窗口

示例:
  w           - 以0.5速度前进1秒
  w 0.8 2     - 以0.8速度前进2秒
  drive 0.3 0.5 1.5  - 左轮0.3，右轮0.5，运行1.5秒

其他:
  help / h    - 显示帮助
  status      - 显示连接状态
  quit / q    - 退出

==========================================
""")

def main():
    print("=" * 50)
    print("   OpenBene 交互式控制台")
    print("=" * 50)

    # 连接方式选择
    print("\n连接方式:")
    print("  1. 自动发现 (推荐)")
    print("  2. 手动输入IP")

    choice = input("\n请选择 [1/2]: ").strip()

    bot = None

    try:
        if choice == "2":
            ip = input("请输入手机IP地址: ").strip()
            port = input("请输入端口 [默认8765]: ").strip()
            port = int(port) if port else 8765

            print(f"\n正在连接到 {ip}:{port}...")
            bot = OpenBene(ip, port)
            bot.connect()
        else:
            print("\n正在自动搜索机器人...")
            print("(提示: 如果搜索失败，可以选择手动输入IP)")
            # 增加发现超时，减少重试次数
            bot = OpenBene.auto_connect(timeout=30, retries=2)

        print(f"\n✓ 已连接: {bot}")
        print_help()

        # 主循环
        while True:
            try:
                cmd = input("\n> ").strip().lower()

                if not cmd:
                    continue

                parts = cmd.split()
                action = parts[0]
                args = parts[1:] if len(parts) > 1 else []

                # 获取速度和持续时间参数
                speed = float(args[0]) if len(args) > 0 else 0.5
                duration = float(args[1]) if len(args) > 1 else 1.0

                # 处理命令
                if action in ['w', 'forward']:
                    bot.forward(speed)
                    print(f"前进: 速度={speed}, 持续{duration}秒")
                    time.sleep(duration)
                    bot.stop()

                elif action in ['s', 'backward']:
                    bot.backward(speed)
                    print(f"后退: 速度={speed}, 持续{duration}秒")
                    time.sleep(duration)
                    bot.stop()

                elif action in ['a', 'left']:
                    bot.turn_left(speed)
                    print(f"左转: 速度={speed}, 持续{duration}秒")
                    time.sleep(duration)
                    bot.stop()

                elif action in ['d', 'right']:
                    bot.turn_right(speed)
                    print(f"右转: 速度={speed}, 持续{duration}秒")
                    time.sleep(duration)
                    bot.stop()

                elif action in ['x', 'stop']:
                    bot.stop()
                    print("停止")

                elif action == 'drive':
                    if len(args) >= 2:
                        left = float(args[0])
                        right = float(args[1])
                        dur = float(args[2]) if len(args) > 2 else 1.0
                        bot.drive(left, right)
                        print(f"驱动: 左轮={left}, 右轮={right}, 持续{dur}秒")
                        time.sleep(dur)
                        bot.stop()
                    else:
                        print("用法: drive <左轮速度> <右轮速度> [持续时间]")
                        print("示例: drive 0.3 0.5 1.5")

                elif action == 'video':
                    if len(args) > 0 and args[0] == 'off':
                        bot.stop_video()
                        print("视频已关闭")
                    else:
                        print("正在打开视频窗口... (按q键关闭)")
                        bot.start_video(display=True)

                elif action in ['h', 'help']:
                    print_help()

                elif action == 'status':
                    print(f"连接状态: {'已连接' if bot.connected else '未连接'}")
                    print(f"目标地址: {bot.ip}:{bot.port}")
                    sensors = bot.get_sensors()
                    if sensors.get('battery_level'):
                        print(f"电池电量: {sensors['battery_level']}%")

                elif action in ['q', 'quit', 'exit']:
                    print("正在停止并断开连接...")
                    bot.stop()
                    break

                else:
                    print(f"未知命令: {action}")
                    print("输入 'help' 查看可用命令")

            except ValueError as e:
                print(f"参数错误: {e}")
            except KeyboardInterrupt:
                print("\n\n正在停止...")
                bot.stop()
                break

    except Exception as e:
        print(f"\n连接失败: {e}")
        return 1

    finally:
        if bot:
            bot.disconnect()
            print("已断开连接")

    return 0

if __name__ == "__main__":
    sys.exit(main())
