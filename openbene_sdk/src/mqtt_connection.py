"""
OpenBene MQTT Connection Module - MQTT协议连接管理

提供与智能家居设备的MQTT通信功能。

使用方法:
    from openbene.mqtt_connection import MQTTConnection

    mqtt = MQTTConnection("broker.example.com")
    mqtt.connect()
    mqtt.subscribe("openbene/bot1/sensors", callback=handle_sensors)
    mqtt.publish("openbene/bot1/control", {"cmd": "drive", "val": [0.5, 0.5]})
    mqtt.disconnect()
"""

import json
import logging
import time
import threading
import uuid
from typing import Optional, Callable, Dict, Any, List

# Try importing MQTT support
try:
    import paho.mqtt.client as mqtt
    MQTT_SUPPORT = True
except ImportError:
    MQTT_SUPPORT = False
    mqtt = None

# Configure logging
logger = logging.getLogger(__name__)


class MQTTConnectionError(Exception):
    """MQTT连接失败异常"""
    pass


class MQTTConnection:
    """
    MQTT连接管理器

    负责与MQTT Broker建立和维护连接，支持发布/订阅模式。

    Attributes:
        broker: MQTT Broker地址
        port: MQTT端口
        connected: 是否已连接
    """

    DEFAULT_PORT = 1883
    DEFAULT_TLS_PORT = 8883
    TIMEOUT = 5.0

    def __init__(
        self,
        broker: str,
        port: int = None,
        client_id: str = None,
        username: str = None,
        password: str = None,
        keepalive: int = 60,
        use_tls: bool = False
    ):
        """
        初始化MQTT连接器

        Args:
            broker: MQTT Broker地址
            port: 端口号，None时根据use_tls自动选择 (1883/8883)
            client_id: 客户端ID，None时自动生成
            username: 用户名（可选）
            password: 密码（可选）
            keepalive: 心跳间隔（秒），默认60
            use_tls: 是否使用TLS加密，默认False
        """
        if not MQTT_SUPPORT:
            raise ImportError("需要安装paho-mqtt库: pip install paho-mqtt")

        self.broker = broker
        self.port = port or (self.DEFAULT_TLS_PORT if use_tls else self.DEFAULT_PORT)
        self.client_id = client_id or f"openbene-{uuid.uuid4().hex[:8]}"
        self.username = username
        self.password = password
        self.keepalive = keepalive
        self.use_tls = use_tls
        self.connected = False

        # MQTT客户端
        self._client: Optional[mqtt.Client] = None
        self._connect_event = threading.Event()
        self._lock = threading.Lock()

        # 消息回调
        self._message_callbacks: List[Callable[[str, Dict[str, Any]], None]] = []
        self._topic_callbacks: Dict[str, List[Callable[[Dict[str, Any]], None]]] = {}

        # 订阅的主题
        self._subscriptions: Dict[str, int] = {}  # topic -> qos

    def connect(self, timeout: float = TIMEOUT) -> bool:
        """
        连接到MQTT Broker

        Args:
            timeout: 连接超时时间（秒）

        Returns:
            True if 连接成功

        Raises:
            MQTTConnectionError: 连接失败
        """
        logger.info(f"正在连接到MQTT Broker {self.broker}:{self.port}...")

        # 创建客户端
        self._client = mqtt.Client(client_id=self.client_id)

        # 设置回调
        self._client.on_connect = self._on_connect
        self._client.on_disconnect = self._on_disconnect
        self._client.on_message = self._on_message

        # 设置认证
        if self.username:
            self._client.username_pw_set(self.username, self.password)

        # 设置TLS
        if self.use_tls:
            self._client.tls_set()

        # 连接
        self._connect_event.clear()
        try:
            self._client.connect(self.broker, self.port, self.keepalive)
            self._client.loop_start()
        except Exception as e:
            raise MQTTConnectionError(f"连接失败: {e}")

        # 等待连接完成
        if not self._connect_event.wait(timeout):
            self._client.loop_stop()
            raise MQTTConnectionError(f"连接超时: {self.broker}:{self.port}")

        if not self.connected:
            raise MQTTConnectionError(f"连接被拒绝: {self.broker}:{self.port}")

        logger.info(f"已连接到MQTT Broker {self.broker}:{self.port}")
        return True

    def disconnect(self) -> None:
        """断开MQTT连接"""
        if self._client:
            self._client.loop_stop()
            self._client.disconnect()
            self._client = None

        self.connected = False
        logger.info(f"已断开MQTT连接: {self.broker}")

    def publish(
        self,
        topic: str,
        message: dict,
        qos: int = 0,
        retain: bool = False
    ) -> bool:
        """
        发布消息到指定主题

        Args:
            topic: 主题名称
            message: 消息字典（将被转换为JSON）
            qos: QoS等级 (0, 1, 2)
            retain: 是否保留消息

        Returns:
            True if 发布成功

        Raises:
            MQTTConnectionError: 未连接时抛出
        """
        if not self.connected:
            raise MQTTConnectionError("未连接，请先调用 connect()")

        payload = json.dumps(message)
        result = self._client.publish(topic, payload, qos=qos, retain=retain)

        if result.rc == mqtt.MQTT_ERR_SUCCESS:
            logger.debug(f"发布到 {topic}: {message}")
            return True
        else:
            logger.error(f"发布失败: {topic}, rc={result.rc}")
            return False

    def subscribe(
        self,
        topic: str,
        qos: int = 0,
        callback: Callable[[Dict[str, Any]], None] = None
    ) -> bool:
        """
        订阅主题

        Args:
            topic: 主题名称（支持通配符 + 和 #）
            qos: QoS等级 (0, 1, 2)
            callback: 该主题专用的回调函数（可选）

        Returns:
            True if 订阅成功
        """
        if not self.connected:
            raise MQTTConnectionError("未连接，请先调用 connect()")

        result, _ = self._client.subscribe(topic, qos)

        if result == mqtt.MQTT_ERR_SUCCESS:
            with self._lock:
                self._subscriptions[topic] = qos
                if callback:
                    if topic not in self._topic_callbacks:
                        self._topic_callbacks[topic] = []
                    self._topic_callbacks[topic].append(callback)

            logger.info(f"已订阅: {topic} (QoS={qos})")
            return True
        else:
            logger.error(f"订阅失败: {topic}, rc={result}")
            return False

    def unsubscribe(self, topic: str) -> bool:
        """
        取消订阅主题

        Args:
            topic: 主题名称

        Returns:
            True if 取消成功
        """
        if not self.connected:
            return False

        result, _ = self._client.unsubscribe(topic)

        if result == mqtt.MQTT_ERR_SUCCESS:
            with self._lock:
                self._subscriptions.pop(topic, None)
                self._topic_callbacks.pop(topic, None)

            logger.info(f"已取消订阅: {topic}")
            return True
        else:
            logger.error(f"取消订阅失败: {topic}, rc={result}")
            return False

    def on_message(self, callback: Callable[[str, Dict[str, Any]], None]) -> None:
        """
        注册全局消息回调

        Args:
            callback: 回调函数，接收 (topic, message) 参数
        """
        self._message_callbacks.append(callback)

    def remove_callback(self, callback: Callable) -> None:
        """
        移除消息回调

        Args:
            callback: 要移除的回调函数
        """
        if callback in self._message_callbacks:
            self._message_callbacks.remove(callback)

        # 也从主题回调中移除
        with self._lock:
            for topic in self._topic_callbacks:
                if callback in self._topic_callbacks[topic]:
                    self._topic_callbacks[topic].remove(callback)

    def set_will(
        self,
        topic: str,
        message: dict,
        qos: int = 0,
        retain: bool = False
    ) -> None:
        """
        设置遗嘱消息 (Last Will and Testament)

        当客户端异常断开时，Broker会自动发布此消息。
        必须在 connect() 之前调用。

        Args:
            topic: 遗嘱消息主题
            message: 遗嘱消息内容
            qos: QoS等级
            retain: 是否保留
        """
        if self._client is None:
            # 预先创建客户端以设置遗嘱
            self._client = mqtt.Client(client_id=self.client_id)

        payload = json.dumps(message)
        self._client.will_set(topic, payload, qos=qos, retain=retain)
        logger.debug(f"已设置遗嘱消息: {topic}")

    def _on_connect(self, client, userdata, flags, rc):
        """连接回调"""
        if rc == 0:
            self.connected = True
            logger.debug("MQTT连接成功")

            # 重新订阅之前的主题（用于重连）
            with self._lock:
                for topic, qos in self._subscriptions.items():
                    client.subscribe(topic, qos)
        else:
            self.connected = False
            error_messages = {
                1: "协议版本错误",
                2: "客户端ID无效",
                3: "服务器不可用",
                4: "用户名或密码错误",
                5: "未授权",
            }
            error_msg = error_messages.get(rc, f"未知错误 ({rc})")
            logger.error(f"MQTT连接失败: {error_msg}")

        self._connect_event.set()

    def _on_disconnect(self, client, userdata, rc):
        """断开连接回调"""
        self.connected = False
        if rc != 0:
            logger.warning(f"MQTT意外断开: rc={rc}")
        else:
            logger.debug("MQTT正常断开")

    def _on_message(self, client, userdata, msg):
        """消息接收回调"""
        try:
            topic = msg.topic
            payload = json.loads(msg.payload.decode('utf-8'))

            logger.debug(f"收到消息 [{topic}]: {payload}")

            # 调用全局回调
            for callback in self._message_callbacks:
                try:
                    callback(topic, payload)
                except Exception as e:
                    logger.error(f"全局回调错误: {e}")

            # 调用主题专用回调
            with self._lock:
                # 精确匹配
                if topic in self._topic_callbacks:
                    for callback in self._topic_callbacks[topic]:
                        try:
                            callback(payload)
                        except Exception as e:
                            logger.error(f"主题回调错误: {e}")

                # 通配符匹配
                for sub_topic, callbacks in self._topic_callbacks.items():
                    if self._topic_matches(sub_topic, topic) and sub_topic != topic:
                        for callback in callbacks:
                            try:
                                callback(payload)
                            except Exception as e:
                                logger.error(f"通配符回调错误: {e}")

        except json.JSONDecodeError as e:
            logger.warning(f"JSON解析错误: {e}, payload={msg.payload}")
        except Exception as e:
            logger.error(f"消息处理错误: {e}")

    def _topic_matches(self, pattern: str, topic: str) -> bool:
        """检查主题是否匹配订阅模式"""
        pattern_parts = pattern.split('/')
        topic_parts = topic.split('/')

        i = 0
        for i, p in enumerate(pattern_parts):
            if p == '#':
                return True
            if i >= len(topic_parts):
                return False
            if p != '+' and p != topic_parts[i]:
                return False

        return i + 1 == len(topic_parts)

    @property
    def is_connected(self) -> bool:
        """是否已连接"""
        return self.connected

    @property
    def subscribed_topics(self) -> List[str]:
        """已订阅的主题列表"""
        with self._lock:
            return list(self._subscriptions.keys())

    def __repr__(self):
        status = "已连接" if self.connected else "未连接"
        return f"MQTTConnection({self.broker}:{self.port}, {status})"

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.disconnect()


# 预定义的主题模板
class MQTTTopics:
    """MQTT主题命名规范"""

    @staticmethod
    def control(device_id: str) -> str:
        """控制命令主题"""
        return f"openbene/{device_id}/control"

    @staticmethod
    def status(device_id: str) -> str:
        """设备状态主题"""
        return f"openbene/{device_id}/status"

    @staticmethod
    def sensors(device_id: str) -> str:
        """传感器数据主题"""
        return f"openbene/{device_id}/sensors"

    @staticmethod
    def video(device_id: str) -> str:
        """视频帧主题"""
        return f"openbene/{device_id}/video"

    @staticmethod
    def lwt(device_id: str) -> str:
        """遗嘱消息主题"""
        return f"openbene/{device_id}/lwt"

    @staticmethod
    def smarthome_set(room: str, device: str) -> str:
        """智能家居设置命令"""
        return f"smarthome/{room}/{device}/set"

    @staticmethod
    def smarthome_state(room: str, device: str) -> str:
        """智能家居状态反馈"""
        return f"smarthome/{room}/{device}/state"
