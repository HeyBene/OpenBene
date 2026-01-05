"""
基础控制示例

演示如何连接机器人并发送控制命令
"""

import sys
import time
sys.path.insert(0, '../src')

from openbene import OpenBene

def main():
    # 替换为你手机的IP地址
    PHONE_IP = "192.168.1.100"

    print(f"连接到手机: {PHONE_IP}")

    # 方式1: 直接使用
    bot = OpenBene(PHONE_IP)
    bot.connect()

    print("开始控制...")

    # 前进2秒
    print("前进...")
    bot.forward(0.5)
    time.sleep(2)

    # 左转1秒
    print("左转...")
    bot.turn_left(0.3)
    time.sleep(1)

    # 右转1秒
    print("右转...")
    bot.turn_right(0.3)
    time.sleep(1)

    # 后退1秒
    print("后退...")
    bot.backward(0.3)
    time.sleep(1)

    # 停止
    print("停止")
    bot.stop()

    bot.disconnect()
    print("完成!")


def main_context_manager():
    """使用上下文管理器（推荐）"""
    PHONE_IP = "192.168.1.100"

    with OpenBene(PHONE_IP) as bot:
        bot.forward(0.5)
        time.sleep(2)
        bot.stop()


if __name__ == "__main__":
    main()
