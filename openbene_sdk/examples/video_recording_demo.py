#!/usr/bin/env python3
"""
OpenBene 数据录制示例

演示如何使用 DataLogger 录制训练数据。
支持两种模式：
- 图片模式：保存为 JPEG 图片序列
- 视频模式：保存为 MP4 视频文件

使用方法:
    # 图片模式
    python video_recording_demo.py --ip 192.168.1.100 --mode images

    # 视频模式
    python video_recording_demo.py --ip 192.168.1.100 --mode video

    # 自动发现
    python video_recording_demo.py --auto --mode video

控制:
    - W/S: 前进/后退
    - A/D: 左转/右转
    - R: 开始/停止录制
    - Q: 退出程序
"""

import sys
import os
import argparse
import time

# 添加 SDK 路径（开发环境）
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

import cv2
from openbene import OpenBene, DataLogger

try:
    from pynput import keyboard
    KEYBOARD_SUPPORT = True
except ImportError:
    KEYBOARD_SUPPORT = False


class RecordingController:
    """录制控制器，处理键盘输入和录制状态。"""

    def __init__(self, bot: OpenBene, logger: DataLogger):
        """初始化录制控制器。

        Args:
            bot: OpenBene 机器人实例。
            logger: DataLogger 数据记录器实例。
        """
        self.bot = bot
        self.logger = logger
        self.recording = False
        self.running = True
        self.current_speed = 0.5

    def on_press(self, key):
        """处理按键按下事件。

        Args:
            key: 按下的键。
        """
        try:
            if hasattr(key, 'char'):
                # 字母键
                if key.char == 'w':
                    self.bot.forward(self.current_speed)
                elif key.char == 's':
                    self.bot.backward(self.current_speed)
                elif key.char == 'a':
                    self.bot.turn_left(self.current_speed)
                elif key.char == 'd':
                    self.bot.turn_right(self.current_speed)
                elif key.char == 'r':
                    self.toggle_recording()
                elif key.char == 'q':
                    self.running = False
                    return False
        except AttributeError:
            pass

    def on_release(self, key):
        """处理按键释放事件。

        Args:
            key: 释放的键。
        """
        try:
            if hasattr(key, 'char') and key.char in ('w', 's', 'a', 'd'):
                self.bot.stop()
        except AttributeError:
            pass

    def toggle_recording(self):
        """切换录制状态。"""
        if self.recording:
            self.logger.stop()
            self.recording = False
            print("⏹ 停止录制")
        else:
            timestamp = time.strftime("%Y%m%d_%H%M%S")
            output_dir = f"./recordings/{timestamp}"
            self.logger.start(output_dir)
            self.recording = True
            print(f"⏺ 开始录制: {output_dir}")


def main():
    """主函数：连接机器人并开始录制。"""
    parser = argparse.ArgumentParser(description="OpenBene 数据录制示例")
    parser.add_argument("--ip", type=str, help="机器人 IP 地址")
    parser.add_argument("--auto", action="store_true", help="自动发现机器人")
    parser.add_argument("--mode", choices=["images", "video"], default="images",
                        help="录制模式: images=图片序列, video=MP4视频")
    parser.add_argument("--fps", type=float, default=30.0,
                        help="视频帧率（仅 video 模式）")
    args = parser.parse_args()

    if not KEYBOARD_SUPPORT:
        print("警告: 未安装 pynput，无法使用键盘控制")
        print("安装: pip install pynput")
        return

    print(f"录制模式: {args.mode}")
    print("\n控制说明:")
    print("  W/S: 前进/后退")
    print("  A/D: 左转/右转")
    print("  R: 开始/停止录制")
    print("  Q: 退出程序\n")

    # 连接机器人
    try:
        if args.auto:
            print("正在自动发现机器人...")
            bot = OpenBene.auto_connect()
        elif args.ip:
            bot = OpenBene(args.ip)
            bot.connect()
        else:
            print("请指定 --ip 或使用 --auto 自动发现")
            return

        print(f"已连接到机器人\n")

        # 创建数据记录器
        logger = DataLogger(
            bot.video,
            bot.sensors,
            save_format=args.mode,
            fps=args.fps
        )

        # 创建控制器
        controller = RecordingController(bot, logger)

        # 启动键盘监听
        listener = keyboard.Listener(
            on_press=controller.on_press,
            on_release=controller.on_release
        )
        listener.start()

        # 显示视频流
        print("按 R 开始录制，按 Q 退出\n")
        for frame in bot.video_stream():
            # 显示录制状态
            if controller.recording:
                status_text = f"REC {logger.frame_count} frames ({logger.elapsed_time:.1f}s)"
                cv2.putText(frame, status_text, (10, 30),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)

            cv2.imshow("OpenBene Recording", frame)

            if cv2.waitKey(1) & 0xFF == ord('q') or not controller.running:
                break

        # 清理
        if controller.recording:
            logger.stop()

        listener.stop()
        cv2.destroyAllWindows()
        bot.disconnect()

    except KeyboardInterrupt:
        print("\n用户中断")
    except Exception as e:
        print(f"错误: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
