"""
自动驾驶示例

演示如何结合视觉模型实现自动驾驶
"""

import sys
import time
sys.path.insert(0, '../src')

from openbene import OpenBene

# 需要安装 OpenCV
try:
    import cv2
    import numpy as np
except ImportError:
    print("请安装OpenCV: pip install opencv-python")
    sys.exit(1)


class SimpleAutopilot:
    """
    简单的自动驾驶示例
    使用颜色追踪来跟随红色物体
    """

    def __init__(self, bot: OpenBene):
        self.bot = bot
        self.running = False

        # 红色物体的HSV范围
        self.lower_red = np.array([0, 100, 100])
        self.upper_red = np.array([10, 255, 255])

    def process_frame(self, frame):
        """处理一帧图像，返回控制命令"""
        height, width = frame.shape[:2]

        # 转换到HSV
        hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)

        # 检测红色
        mask = cv2.inRange(hsv, self.lower_red, self.upper_red)

        # 查找轮廓
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        if contours:
            # 找最大的红色区域
            largest = max(contours, key=cv2.contourArea)
            area = cv2.contourArea(largest)

            if area > 500:  # 忽略小噪点
                # 计算中心点
                M = cv2.moments(largest)
                if M['m00'] > 0:
                    cx = int(M['m10'] / M['m00'])
                    cy = int(M['m01'] / M['m00'])

                    # 画出检测结果
                    cv2.circle(frame, (cx, cy), 10, (0, 255, 0), -1)
                    cv2.drawContours(frame, [largest], -1, (0, 255, 0), 2)

                    # 根据位置决定动作
                    center_x = width // 2
                    tolerance = width // 6

                    if cx < center_x - tolerance:
                        return frame, "left", 0.3
                    elif cx > center_x + tolerance:
                        return frame, "right", 0.3
                    else:
                        return frame, "forward", 0.4

        return frame, "stop", 0

    def run(self):
        """运行自动驾驶"""
        print("自动驾驶模式启动")
        print("追踪红色物体...")
        print("按 'q' 退出")

        self.running = True

        while self.running and self.bot.connected:
            frame = self.bot.get_frame()
            if frame is None:
                time.sleep(0.03)
                continue

            # 处理帧
            display_frame, action, speed = self.process_frame(frame)

            # 执行动作
            if action == "left":
                self.bot.turn_left(speed)
            elif action == "right":
                self.bot.turn_right(speed)
            elif action == "forward":
                self.bot.forward(speed)
            else:
                self.bot.stop()

            # 显示状态
            cv2.putText(display_frame, f"Action: {action}",
                        (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)

            cv2.imshow("Autopilot", display_frame)

            if cv2.waitKey(30) & 0xFF == ord('q'):
                break

        self.bot.stop()
        cv2.destroyAllWindows()


def main():
    PHONE_IP = "192.168.1.100"

    with OpenBene(PHONE_IP) as bot:
        autopilot = SimpleAutopilot(bot)
        autopilot.run()


if __name__ == "__main__":
    main()
