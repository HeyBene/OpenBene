#!/usr/bin/env python3
"""
OpenBene 自定义图像处理示例

演示如何继承 ImageProcessor 创建自己的图像处理器。
本示例实现将摄像头画面转换为灰度图。

使用方法:
    python custom_cv_demo.py --ip 192.168.1.100
    # 或使用自动发现:
    python custom_cv_demo.py --auto

控制:
    - Q: 退出程序
    - G: 切换灰度/彩色模式
"""

import sys
import os
import argparse

# 添加 SDK 路径（开发环境）
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

import cv2
from openbene import OpenBene, ImageProcessor


class GrayscaleProcessor(ImageProcessor):
    """灰度图处理器。

    将 BGR 彩色图像转换为灰度图像。
    这是最简单的图像处理示例，学生可以基于此实现更复杂的算法。

    Example:
        >>> processor = GrayscaleProcessor()
        >>> gray_frame = processor.process(color_frame)
    """

    def __init__(self):
        """初始化灰度处理器。"""
        super().__init__(name="Grayscale")

    def process(self, frame):
        """将 BGR 图像转换为灰度图。

        Args:
            frame: BGR 格式的输入图像 (numpy.ndarray)。

        Returns:
            灰度图像 (numpy.ndarray)，形状为 (height, width)。
        """
        return cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)


class EdgeDetectionProcessor(ImageProcessor):
    """边缘检测处理器。

    使用 Canny 算法检测图像边缘。
    可以调整阈值参数来控制边缘检测的灵敏度。

    Attributes:
        low_threshold: Canny 算法的低阈值。
        high_threshold: Canny 算法的高阈值。
    """

    def __init__(self, low_threshold: int = 50, high_threshold: int = 150):
        """初始化边缘检测处理器。

        Args:
            low_threshold: Canny 低阈值，默认 50。
            high_threshold: Canny 高阈值，默认 150。
        """
        super().__init__(name="EdgeDetection")
        self.low_threshold = low_threshold
        self.high_threshold = high_threshold

    def process(self, frame):
        """检测图像边缘。

        Args:
            frame: BGR 格式的输入图像。

        Returns:
            边缘检测结果，单通道二值图像。
        """
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        edges = cv2.Canny(gray, self.low_threshold, self.high_threshold)
        return edges


def main():
    """主函数：连接机器人并显示处理后的视频流。"""
    parser = argparse.ArgumentParser(description="OpenBene 自定义图像处理示例")
    parser.add_argument("--ip", type=str, help="机器人 IP 地址")
    parser.add_argument("--auto", action="store_true", help="自动发现机器人")
    parser.add_argument("--mode", choices=["gray", "edge"], default="gray",
                        help="处理模式: gray=灰度图, edge=边缘检测")
    args = parser.parse_args()

    # 选择处理器
    if args.mode == "edge":
        processor = EdgeDetectionProcessor()
    else:
        processor = GrayscaleProcessor()

    print(f"使用处理器: {processor}")
    print("按 Q 退出, G 切换灰度/边缘模式")

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

        print(f"已连接到机器人")

        # 创建两个处理器用于切换
        gray_processor = GrayscaleProcessor()
        edge_processor = EdgeDetectionProcessor()
        current_processor = gray_processor if args.mode == "gray" else edge_processor

        # 处理视频流
        for frame in bot.video_stream():
            # 应用当前处理器
            processed = current_processor.process(frame)

            # 显示结果
            cv2.imshow("Original", frame)
            cv2.imshow(f"Processed ({current_processor.name})", processed)

            # 键盘控制
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break
            elif key == ord('g'):
                # 切换处理器
                if isinstance(current_processor, GrayscaleProcessor):
                    current_processor = edge_processor
                else:
                    current_processor = gray_processor
                print(f"切换到: {current_processor.name}")

    except KeyboardInterrupt:
        print("\n用户中断")
    except Exception as e:
        print(f"错误: {e}")
    finally:
        cv2.destroyAllWindows()
        if 'bot' in locals():
            bot.disconnect()


if __name__ == "__main__":
    main()
