"""
视频显示示例

演示如何接收和显示视频流
"""

import sys
import time
sys.path.insert(0, '../src')

from openbene import OpenBene

def main():
    PHONE_IP = "192.168.1.100"

    with OpenBene(PHONE_IP) as bot:
        print("启动视频显示...")
        print("按 'q' 退出")

        # 启动视频显示（OpenCV窗口）
        bot.start_video(display=True)

        # 保持运行，同时可以控制机器人
        try:
            while bot.connected:
                # 获取传感器数据
                sensors = bot.get_sensors()
                if sensors['accelerometer']:
                    accel = sensors['accelerometer']
                    print(f"\r加速度: X={accel['x']:.2f}, Y={accel['y']:.2f}, Z={accel['z']:.2f}", end="")

                time.sleep(0.5)

        except KeyboardInterrupt:
            print("\n用户中断")

        bot.stop_video()


def manual_frame_processing():
    """手动处理视频帧"""
    import cv2

    PHONE_IP = "192.168.1.100"

    with OpenBene(PHONE_IP) as bot:
        print("手动帧处理模式...")

        while True:
            frame = bot.get_frame()
            if frame is not None:
                # 可以在这里添加图像处理代码
                # 例如: 目标检测、边缘检测等

                cv2.imshow("Processed Frame", frame)

            if cv2.waitKey(30) & 0xFF == ord('q'):
                break

        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
