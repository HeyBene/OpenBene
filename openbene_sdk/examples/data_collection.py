"""
数据采集示例

演示如何采集训练数据（图片+传感器+控制命令）
"""

import sys
import time
sys.path.insert(0, '../src')

from openbene import OpenBene

def main():
    PHONE_IP = "192.168.1.100"

    with OpenBene(PHONE_IP) as bot:
        print("数据采集模式")
        print("=" * 40)

        # 开始采集，数据保存到 ./training_data/
        bot.start_recording(output_dir="./training_data")

        print("开始手动控制，数据会自动记录...")
        print("按 Ctrl+C 停止采集")

        try:
            # 示例：自动采集一些数据
            for i in range(3):
                print(f"\n第 {i+1}/3 轮")

                print("  前进...")
                bot.forward(0.5)
                time.sleep(2)

                print("  左转...")
                bot.turn_left(0.3)
                time.sleep(1)

                print("  右转...")
                bot.turn_right(0.3)
                time.sleep(1)

                bot.stop()
                time.sleep(0.5)

        except KeyboardInterrupt:
            print("\n用户中断")

        # 停止采集
        bot.stop_recording()

        print("\n" + "=" * 40)
        print("数据采集完成！")
        print("数据保存在: ./training_data/")
        print("  - images/: 图片文件")
        print("  - labels.csv: 标签数据")


def train_model_example():
    """
    使用采集的数据训练模型的示例代码

    这只是示意，实际训练代码需要根据你的模型来写
    """
    import pandas as pd

    # 读取标签
    df = pd.read_csv("./training_data/labels.csv")
    print(f"共 {len(df)} 个样本")
    print(df.head())

    # 输入: 图片 (images/*.jpg)
    # 输出: command, speed_left, speed_right

    # TODO: 加载图片，训练你的模型
    # for idx, row in df.iterrows():
    #     image_path = f"./training_data/images/{row['image']}"
    #     command = row['command']
    #     ...


if __name__ == "__main__":
    main()
