"""
OpenBene SDK 新API演示

展示如何使用新的工厂函数和控制方法
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

import openbene

def main():
    print("=" * 60)
    print("   OpenBene SDK 新API演示")
    print("=" * 60)

    # 连接方式选择
    print("\n连接方式:")
    print("  1. 自动发现 (推荐)")
    print("  2. 手动输入IP")

    choice = input("\n请选择 [1/2]: ").strip()

    try:
        if choice == "2":
            ip = input("请输入手机IP地址: ").strip()
            print(f"\n正在连接到 {ip}...")
            bot = openbene.openbot_rtr_tt("my_robot", ip=ip)
        else:
            print("\n正在自动搜索并连接...")
            bot = openbene.openbot_rtr_tt("my_robot")

        print(f"\n✓ 已连接!")
        print(f"  机器人名称: {bot.name}")
        print(f"  硬件类型: {bot.robot_type}")
        print(f"  地址: {bot.ip}:{bot.port}")

        print("\n" + "=" * 60)
        print("开始控制测试")
        print("=" * 60)

        # 测试带持续时间的控制方法
        print("\n1. 前进1秒...")
        bot.move_forward(speed=0.5, duration=1.0)

        print("2. 后退1秒...")
        bot.move_backward(speed=0.5, duration=1.0)

        print("3. 左转0.5秒...")
        bot.rotate_left(speed=0.4, duration=0.5)

        print("4. 右转0.5秒...")
        bot.rotate_right(speed=0.4, duration=0.5)

        print("5. 弧线运动1秒 (左轮0.3, 右轮0.5)...")
        bot.move(0.3, 0.5, duration=1.0)

        print("\n" + "=" * 60)
        print("✓ 所有测试完成!")
        print("=" * 60)

        # 断开连接
        bot.disconnect()
        print("\n已断开连接")

    except openbene.ConnectionError as e:
        print(f"\n✗ 连接失败: {e}")
        return 1

    except KeyboardInterrupt:
        print("\n\n用户中断")
        return 0

    return 0

if __name__ == "__main__":
    sys.exit(main())
