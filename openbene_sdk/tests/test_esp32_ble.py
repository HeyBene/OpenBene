import sys
from pathlib import Path
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1] / "src"
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene.esp32_ble import OpenBotBleClient
from openbene.esp32_ble import clamp_pwm
from openbene.esp32_ble import is_openbot_device_name
from openbene.esp32_ble import make_ctrl_cmd
from openbene.esp32_ble import make_feature_cmd
from openbene.esp32_ble import make_heartbeat_cmd
from openbene.esp32_ble import make_sensor_stream_cmd
from openbene.esp32_ble import parse_esp_message


class Esp32BleTests(unittest.TestCase):
    def test_clamp_pwm_limits_range(self) -> None:
        self.assertEqual(clamp_pwm(300), 255)
        self.assertEqual(clamp_pwm(-300), -255)
        self.assertEqual(clamp_pwm(42), 42)

    def test_make_ctrl_cmd_uses_expected_wire_format(self) -> None:
        self.assertEqual(make_ctrl_cmd(120, -90), b"c120,-90\n")

    def test_make_heartbeat_cmd_uses_expected_wire_format(self) -> None:
        self.assertEqual(make_heartbeat_cmd(300), b"h300\n")

    def test_make_sensor_stream_cmd_uses_expected_wire_format(self) -> None:
        self.assertEqual(make_sensor_stream_cmd("w", 500), b"w500\n")
        self.assertEqual(make_feature_cmd(), b"f\n")

    def test_is_openbot_device_name_matches_supported_names(self) -> None:
        self.assertTrue(is_openbot_device_name("OpenBot RTR_520"))
        self.assertTrue(is_openbot_device_name("My openbot robot"))
        self.assertFalse(is_openbot_device_name("Headphones"))

    def test_handle_notification_parses_bare_ble_payloads(self) -> None:
        client = OpenBotBleClient("AA:BB:CC:DD:EE:FF")
        seen: list[dict[str, object]] = []
        client.add_message_callback(seen.append)

        client._handle_notification(None, bytearray(b"w12.5,10.0"))

        self.assertEqual(len(seen), 1)
        self.assertEqual(seen[0]["type"], "wheel")
        self.assertAlmostEqual(float(seen[0]["rpm_left"]), 12.5)
        self.assertAlmostEqual(float(seen[0]["rpm_right"]), 10.0)

    def test_handle_notification_parses_newline_terminated_ble_payloads(self) -> None:
        client = OpenBotBleClient("AA:BB:CC:DD:EE:FF")
        seen: list[dict[str, object]] = []
        client.add_message_callback(seen.append)

        client._handle_notification(None, bytearray(b"w12.5,10.0\n"))

        self.assertEqual(len(seen), 1)
        self.assertEqual(seen[0]["type"], "wheel")
        self.assertAlmostEqual(float(seen[0]["rpm_left"]), 12.5)
        self.assertAlmostEqual(float(seen[0]["rpm_right"]), 10.0)

    def test_parse_wheel_message(self) -> None:
        payload = parse_esp_message("w12.5,10.0")
        self.assertEqual(payload["type"], "wheel")
        self.assertAlmostEqual(float(payload["rpm_left"]), 12.5)
        self.assertAlmostEqual(float(payload["rpm_right"]), 10.0)

    def test_parse_feature_message(self) -> None:
        payload = parse_esp_message("fRTR_520:v:i:s:wf:wb:")
        self.assertEqual(payload["type"], "features")
        self.assertEqual(payload["robot_type"], "RTR_520")
        self.assertEqual(payload["capabilities"], ["v", "i", "s", "wf", "wb"])

    def test_parse_unknown_message_falls_back_to_raw(self) -> None:
        payload = parse_esp_message("zhello")
        self.assertEqual(payload["type"], "unknown")
        self.assertEqual(payload["raw"], "zhello")


if __name__ == "__main__":
    unittest.main()
