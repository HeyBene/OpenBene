#!/usr/bin/env python3
"""
OpenBene MQTT 智能家居示例

演示如何使用 MQTTConnection 控制智能家居设备。

使用场景:
    - 智能灯控制
    - 温度传感器监控
    - 多设备联动
    - Home Assistant 集成

使用方法:
    python mqtt_smart_home.py
"""

import time
import json
import logging
from typing import Dict, Any
from openbene import MQTTConnection, MQTTTopics

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SmartLight:
    """智能灯设备"""

    def __init__(self, mqtt: MQTTConnection, room: str, name: str):
        self.mqtt = mqtt
        self.room = room
        self.name = name
        self.state = "off"
        self.brightness = 100

        # 订阅控制主题
        self.control_topic = MQTTTopics.smarthome_set(room, name)
        self.state_topic = MQTTTopics.smarthome_state(room, name)

        mqtt.subscribe(self.control_topic, qos=1, callback=self._handle_command)
        logger.info(f"智能灯 {room}/{name} 已初始化")

    def _handle_command(self, message: Dict[str, Any]):
        """处理控制命令"""
        if "state" in message:
            self.state = message["state"]
        if "brightness" in message:
            self.brightness = message["brightness"]

        logger.info(f"灯 {self.name}: state={self.state}, brightness={self.brightness}")

        # 发布状态更新
        self._publish_state()

    def _publish_state(self):
        """发布当前状态"""
        self.mqtt.publish(
            self.state_topic,
            {
                "device": self.name,
                "type": "light",
                "state": self.state,
                "brightness": self.brightness
            },
            retain=True
        )

    def turn_on(self, brightness: int = 100):
        """开灯"""
        self.state = "on"
        self.brightness = brightness
        self._publish_state()

    def turn_off(self):
        """关灯"""
        self.state = "off"
        self._publish_state()


class TemperatureSensor:
    """温度传感器"""

    def __init__(self, mqtt: MQTTConnection, room: str, name: str):
        self.mqtt = mqtt
        self.room = room
        self.name = name
        self.temperature = 25.0
        self.humidity = 50.0

        self.state_topic = MQTTTopics.smarthome_state(room, name)
        logger.info(f"温度传感器 {room}/{name} 已初始化")

    def update(self, temperature: float, humidity: float):
        """更新传感器数据"""
        self.temperature = temperature
        self.humidity = humidity

        self.mqtt.publish(
            self.state_topic,
            {
                "device": self.name,
                "type": "sensor",
                "temperature": temperature,
                "humidity": humidity,
                "unit": "celsius"
            }
        )
        logger.info(f"传感器 {self.name}: {temperature}°C, {humidity}%")


class SmartHomeController:
    """智能家居控制器"""

    def __init__(self, broker: str, username: str = None, password: str = None):
        self.mqtt = MQTTConnection(
            broker,
            client_id="smarthome_controller",
            username=username,
            password=password
        )
        self.devices = {}

        # 设置遗嘱消息
        self.mqtt.set_will(
            "smarthome/controller/status",
            {"status": "offline"},
            retain=True
        )

    def connect(self):
        """连接到 Broker"""
        self.mqtt.connect()
        logger.info("智能家居控制器已连接")

        # 发布上线状态
        self.mqtt.publish(
            "smarthome/controller/status",
            {"status": "online"},
            retain=True
        )

        # 注册全局消息监听
        self.mqtt.on_message(self._on_message)

        # 订阅所有智能家居消息
        self.mqtt.subscribe("smarthome/#", qos=1)

    def disconnect(self):
        """断开连接"""
        self.mqtt.publish(
            "smarthome/controller/status",
            {"status": "offline"},
            retain=True
        )
        self.mqtt.disconnect()
        logger.info("智能家居控制器已断开")

    def _on_message(self, topic: str, message: Dict[str, Any]):
        """处理所有消息"""
        logger.debug(f"收到消息 [{topic}]: {message}")

    def add_light(self, room: str, name: str) -> SmartLight:
        """添加智能灯"""
        light = SmartLight(self.mqtt, room, name)
        self.devices[f"{room}/{name}"] = light
        return light

    def add_sensor(self, room: str, name: str) -> TemperatureSensor:
        """添加温度传感器"""
        sensor = TemperatureSensor(self.mqtt, room, name)
        self.devices[f"{room}/{name}"] = sensor
        return sensor

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, *args):
        self.disconnect()


def demo_basic_smart_home():
    """基础智能家居示例"""
    print("\n=== 智能家居基础示例 ===\n")

    broker = "test.mosquitto.org"

    with SmartHomeController(broker) as controller:
        # 添加设备
        living_room_light = controller.add_light("living_room", "main_light")
        bedroom_light = controller.add_light("bedroom", "ceiling_light")
        living_room_sensor = controller.add_sensor("living_room", "temp_sensor")

        # 模拟设备操作
        print("\n--- 开启客厅灯 ---")
        living_room_light.turn_on(brightness=80)
        time.sleep(1)

        print("\n--- 开启卧室灯 ---")
        bedroom_light.turn_on(brightness=50)
        time.sleep(1)

        print("\n--- 更新温度传感器 ---")
        living_room_sensor.update(temperature=26.5, humidity=55.0)
        time.sleep(1)

        print("\n--- 关闭所有灯 ---")
        living_room_light.turn_off()
        bedroom_light.turn_off()
        time.sleep(1)

        print("\n示例完成！")


def demo_home_assistant_compatible():
    """Home Assistant 兼容格式示例"""
    print("\n=== Home Assistant 兼容示例 ===\n")

    broker = "test.mosquitto.org"

    with MQTTConnection(broker, client_id="ha_demo") as mqtt:
        # Home Assistant 自动发现格式
        # 参考: https://www.home-assistant.io/docs/mqtt/discovery/

        device_id = "openbene_demo"

        # 发布设备配置（Home Assistant 自动发现）
        config_topic = f"homeassistant/switch/{device_id}/config"
        config_payload = {
            "name": "OpenBene Robot",
            "unique_id": device_id,
            "command_topic": f"openbene/{device_id}/control",
            "state_topic": f"openbene/{device_id}/status",
            "payload_on": json.dumps({"cmd": "start"}),
            "payload_off": json.dumps({"cmd": "stop"}),
            "device": {
                "identifiers": [device_id],
                "name": "OpenBene Robot",
                "model": "RTR-TT",
                "manufacturer": "OpenBene"
            }
        }

        mqtt.publish(config_topic, config_payload, retain=True)
        print(f"已发布 Home Assistant 配置: {config_topic}")

        # 发布状态
        mqtt.publish(
            f"openbene/{device_id}/status",
            {"state": "online"},
            retain=True
        )
        print("已发布状态")

        time.sleep(2)


def demo_automation_scenario():
    """自动化场景示例：温度联动"""
    print("\n=== 自动化场景示例 ===\n")

    broker = "test.mosquitto.org"

    # 阈值设置
    TEMP_HIGH = 28.0
    TEMP_LOW = 18.0

    with MQTTConnection(broker, client_id="automation_demo") as mqtt:
        # 模拟空调控制
        def check_temperature(message):
            temp = message.get("temperature", 25)

            if temp > TEMP_HIGH:
                print(f"温度 {temp}°C > {TEMP_HIGH}°C，开启空调制冷")
                mqtt.publish(
                    "smarthome/living_room/ac/set",
                    {"state": "on", "mode": "cool", "temperature": 24}
                )
            elif temp < TEMP_LOW:
                print(f"温度 {temp}°C < {TEMP_LOW}°C，开启空调制热")
                mqtt.publish(
                    "smarthome/living_room/ac/set",
                    {"state": "on", "mode": "heat", "temperature": 22}
                )
            else:
                print(f"温度 {temp}°C 在舒适范围内")

        # 订阅温度传感器
        mqtt.subscribe(
            "smarthome/living_room/temp_sensor/state",
            callback=check_temperature
        )

        # 模拟温度变化
        print("模拟温度变化...")

        for temp in [25, 29, 17, 23]:
            mqtt.publish(
                "smarthome/living_room/temp_sensor/state",
                {"temperature": temp, "humidity": 50}
            )
            time.sleep(1.5)

        print("\n自动化场景演示完成！")


def main():
    """运行所有示例"""
    print("=" * 50)
    print("OpenBene 智能家居 MQTT 示例")
    print("=" * 50)

    try:
        # 基础示例
        demo_basic_smart_home()

        # Home Assistant 兼容示例
        demo_home_assistant_compatible()

        # 自动化场景示例
        demo_automation_scenario()

        print("\n" + "=" * 50)
        print("所有智能家居示例运行完成！")
        print("=" * 50)

    except Exception as e:
        logger.error(f"示例运行失败: {e}")
        raise


if __name__ == "__main__":
    main()
