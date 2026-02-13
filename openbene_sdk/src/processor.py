"""
OpenBene Image Processor Module - 图像处理器

提供图像处理抽象基类，让学生可以方便地插入自己的 CV 算法。

使用方法:
    from openbene import OpenBene, ImageProcessor
    import cv2

    class GrayscaleProcessor(ImageProcessor):
        def process(self, frame):
            return cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    with OpenBene("192.168.1.100") as bot:
        processor = GrayscaleProcessor()
        for frame in bot.video_stream():
            result = processor.process(frame)
            cv2.imshow("Processed", result)
            if cv2.waitKey(1) == ord('q'):
                break
"""

from abc import ABC, abstractmethod
from typing import Any

# Type alias for numpy array (avoid hard dependency)
try:
    import numpy as np
    Frame = np.ndarray
except ImportError:
    Frame = Any


class ImageProcessor(ABC):
    """图像处理器抽象基类。

    学生可以继承此类并实现 process() 方法来插入自己的 CV 算法。
    处理器接收 BGR 格式的 numpy 数组作为输入，返回处理后的图像。

    Attributes:
        name: 处理器名称，用于日志和调试。

    Example:
        >>> class EdgeDetector(ImageProcessor):
        ...     def process(self, frame):
        ...         gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        ...         return cv2.Canny(gray, 100, 200)
        ...
        >>> detector = EdgeDetector()
        >>> result = detector.process(frame)
    """

    def __init__(self, name: str = "ImageProcessor"):
        """初始化图像处理器。

        Args:
            name: 处理器名称，默认为 "ImageProcessor"。
        """
        self.name = name

    @abstractmethod
    def process(self, frame: Frame) -> Frame:
        """处理单帧图像。

        子类必须实现此方法来定义具体的图像处理逻辑。

        Args:
            frame: BGR 格式的输入图像 (numpy.ndarray)。
                   形状通常为 (height, width, 3)。

        Returns:
            处理后的图像 (numpy.ndarray)。
            可以是任意格式，如灰度图 (height, width) 或彩色图 (height, width, 3)。

        Example:
            >>> def process(self, frame):
            ...     # 转换为灰度图
            ...     return cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        """
        pass

    def __repr__(self) -> str:
        """返回对象的字符串表示。

        Returns:
            格式化的字符串，包含处理器名称。
        """
        return f"{self.__class__.__name__}(name='{self.name}')"


class PassthroughProcessor(ImageProcessor):
    """透传处理器，不做任何处理直接返回原图。

    可用于调试或作为处理链的占位符。

    Example:
        >>> processor = PassthroughProcessor()
        >>> output = processor.process(input_frame)
        >>> # output 与 input_frame 相同
    """

    def __init__(self):
        """初始化透传处理器。"""
        super().__init__(name="Passthrough")

    def process(self, frame: Frame) -> Frame:
        """直接返回输入帧，不做任何处理。

        Args:
            frame: BGR 格式的输入图像。

        Returns:
            与输入相同的图像。
        """
        return frame
