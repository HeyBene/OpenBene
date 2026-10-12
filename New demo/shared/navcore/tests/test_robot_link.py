import unittest

from openbene_nav.robot_link import OpenBotProtocol, RecordingLink, Telemetry


class ProtocolTests(unittest.TestCase):
    def test_ctrl_cmd_scales_to_pwm(self):
        self.assertEqual(OpenBotProtocol.ctrl_cmd(1.0, -1.0), b"c255,-255\n")
        self.assertEqual(OpenBotProtocol.ctrl_cmd(0.0, 0.0), b"c0,0\n")
        self.assertEqual(OpenBotProtocol.ctrl_cmd(0.5, 0.25), b"c128,64\n")

    def test_ctrl_cmd_clamps_out_of_range_speeds(self):
        self.assertEqual(OpenBotProtocol.ctrl_cmd(4.0, -4.0), b"c255,-255\n")

    def test_housekeeping_commands(self):
        self.assertEqual(OpenBotProtocol.heartbeat_cmd(500), b"h500\n")
        self.assertEqual(OpenBotProtocol.feature_cmd(), b"f\n")
        self.assertEqual(OpenBotProtocol.sensor_stream_cmd("w", 250), b"w250\n")
        with self.assertRaises(ValueError):
            OpenBotProtocol.sensor_stream_cmd("ww", 250)

    def test_parse_line_voltage(self):
        message = OpenBotProtocol.parse_line("v8.31\r\n")
        self.assertEqual(message["type"], "voltage")
        self.assertAlmostEqual(message["voltage"], 8.31)

    def test_parse_line_wheel(self):
        message = OpenBotProtocol.parse_line("w120.5,-30")
        self.assertEqual(message["type"], "wheel")
        self.assertAlmostEqual(message["rpm_left"], 120.5)
        self.assertAlmostEqual(message["rpm_right"], -30.0)

    def test_parse_line_sonar_bumper_features(self):
        self.assertEqual(OpenBotProtocol.parse_line("s42")["distance_cm"], 42.0)
        self.assertEqual(OpenBotProtocol.parse_line("b12")["collision_id"], "12")
        self.assertEqual(
            OpenBotProtocol.parse_line("frtr_520:sonar:ble:")["features"], "rtr_520:sonar:ble:"
        )

    def test_parse_line_unknown(self):
        self.assertEqual(OpenBotProtocol.parse_line("zzz")["type"], "unknown")
        self.assertEqual(OpenBotProtocol.parse_line(""), {})

    def test_apply_message_updates_telemetry(self):
        telemetry = Telemetry()
        OpenBotProtocol.apply_message(telemetry, OpenBotProtocol.parse_line("s35"), now_s=1.0)
        OpenBotProtocol.apply_message(telemetry, OpenBotProtocol.parse_line("w10,12"), now_s=1.1)
        self.assertAlmostEqual(telemetry.sonar_cm, 35.0)
        self.assertAlmostEqual(telemetry.rpm_left, 10.0)
        self.assertTrue(telemetry.obstacle(40.0))
        self.assertFalse(telemetry.obstacle(20.0))

    def test_rpm_to_speed(self):
        speed = OpenBotProtocol.rpm_to_speed(60.0, 0.0325)
        self.assertAlmostEqual(speed, 2.0 * 3.141592653589793 * 0.0325, places=6)


class RecordingLinkTests(unittest.TestCase):
    def test_records_commands(self):
        link = RecordingLink()
        link.drive(0.5, -0.5)
        link.stop()
        self.assertEqual(len(link.commands), 2)
        self.assertEqual(link.last_command["type"], "stop")
        self.assertAlmostEqual(link.commands[0]["left"], 0.5)

    def test_clamps_commands(self):
        link = RecordingLink()
        link.drive(9.0, -9.0)
        self.assertAlmostEqual(link.commands[0]["left"], 1.0)
        self.assertAlmostEqual(link.commands[0]["right"], -1.0)


if __name__ == "__main__":
    unittest.main()
