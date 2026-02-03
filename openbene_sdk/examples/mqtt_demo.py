#!/usr/bin/env python3
"""
OpenBene MQTT 基础示例

演示如何使用 MQTTConnection 进行基本的发布/订阅操作。

使用方法:
    python mqtt_demo.py

测试 Broker:
    - 公共测试: test.mosquitto.org
    - 本地测试: docker run -p 1883:1883 eclipse-mosquitto
"""

import time
import logging
from openbene import MQTTConnection, MQTTTopics

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def basic_publish_subscribe():
    """基础发布/订阅示例"""
    print("\n=== 基础发布/订阅示例 ===\n")

    # 使用公共测试 Broker
    broker = "test.mosquitto.org"
    device_id = "demo_bot"

    # 创建连接
    mqtt = MQTTConnection(broker)

    try:
        # 连接到 Broker
        mqtt.connect()
        print(f"已连接到 {broker}")

        # 定义消息处理回调
        def on_sensor_data(message):
            print(f"收到传感器数据: {message}")

        def on_control_command(message):
            print(f"收到控制命令: {message}")

        # 订阅主题
        mqtt.subscribe(
            MQTTTopics.sensors(device_id),
            qos=1,
            callback=on_sensor_data
        )
        mqtt.subscribe(
            MQTTTopics.control(device_id),
            qos=1,
            callback=on_control_command
        )
        print(f"已订阅主题: {mqtt.subscribed_topics}")

        # 发布消息
        print("\n发布测试消息...")

        # 发布传感器数据
        mqtt.publish(
            MQTTTopics.sensors(device_id),
            {
                "type": "sensor_data",
                "data": {
                    "accelerometer": {"x": 0.1, "y": 0.2, "z": 9.8},
                    "battery_level": 85.5
                }
            },
            qos=1
        )

        # 发布控制命令
        mqtt.publish(
            MQTTTopics.control(device_id),
            {"cmd": "drive", "val": [0.5, 0.5]},
            qos=1
        )

        # 等待接收消息
        print("等待接收消息 (3秒)...")
        time.sleep(3)

    finally:
        mqtt.disconnect()
        print("已断开连接")


def context_manager_example():
    """使用上下文管理器的示例"""
    print("\n=== 上下文管理器示例 ===\n")

    broker = "test.mosquitto.org"

    with MQTTConnection(broker) as mqtt:
        print(f"已连接: {mqtt}")

        # 注册全局回调
        def global_callback(topic, message):
            print(f"[{topic}] {message}")

        mqtt.on_message(global_callback)

        # 订阅所有 openbene 主题
        mqtt.subscribe("openbene/#", qos=0)

        # 发布测试消息
        mqtt.publish("openbene/test/status", {"status": "online"})

        time.sleep(2)

    print("连接已自动关闭")


def will_message_example():
    """遗嘱消息示例"""
    print("\n=== 遗嘱消息 (LWT) 示例 ===\n")

    broker = "test.mosquitto.org"
    device_id = "lwt_demo"

    mqtt = MQTTConnection(broker, client_id="lwt_client")

    # 设置遗嘱消息（必须在 connect 之前）
    mqtt.set_will(
        MQTTTopics.lwt(device_id),
        {"status": "offline", "reason": "unexpected_disconnect"},
        qos=1,
        retain=True
    )

    try:
        mqtt.connect()
        print("已连接，遗嘱消息已设置")

        # 发布上线状态
        mqtt.publish(
            MQTTTopics.status(device_id),
            {"status": "online"},
            retain=True
        )

        print("设备在线，按 Ctrl+C 断开...")
        while True:
            time.sleep(1)

    except KeyboardInterrupt:
        print("\n正常断开（遗嘱消息不会发送）")
        mqtt.disconnect()


def qos_example():
    """QoS 等级示例"""
    print("\n=== QoS 等级示例 ===\n")

    broker = "test.mosquitto.org"

    with MQTTConnection(broker) as mqtt:
        topic_base = "openbene/qos_test"

        # QoS 0: 最多一次（可能丢失）
        mqtt.publish(f"{topic_base}/qos0", {"qos": 0, "msg": "At most once"}, qos=0)
        print("QoS 0: 消息已发送（最多一次，不保证送达）")

        # QoS 1: 至少一次（可能重复）
        mqtt.publish(f"{topic_base}/qos1", {"qos": 1, "msg": "At least once"}, qos=1)
        print("QoS 1: 消息已发送（至少一次，保证送达）")

        # QoS 2: 正好一次（最可靠）
        mqtt.publish(f"{topic_base}/qos2", {"qos": 2, "msg": "Exactly once"}, qos=2)
        print("QoS 2: 消息已发送（正好一次，最可靠）")

        time.sleep(1)


def main():
    """运行所有示例"""
    print("=" * 50)
    print("OpenBene MQTT 示例程序")
    print("=" * 50)

    try:
        # 运行基础示例
        basic_publish_subscribe()

        # 运行上下文管理器示例
        context_manager_example()

        # 运行 QoS 示例
        qos_example()

        print("\n" + "=" * 50)
        print("所有示例运行完成！")
        print("=" * 50)

        # 遗嘱消息示例需要手动中断，单独提示
        print("\n提示: 运行 will_message_example() 测试遗嘱消息功能")

    except Exception as e:
        logger.error(f"示例运行失败: {e}")
        raise


if __name__ == "__main__":
    main()
