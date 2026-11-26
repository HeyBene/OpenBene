import json
from pathlib import Path
from urllib.request import Request, urlopen

from mcap.reader import make_reader

from openbene_receiver.protocol import CaptureFrame, FrameMetadata, encode_capture_frame
from openbene_receiver.recorder import RecordingController
from openbene_receiver.receiver import OpenBeneReceiver
from openbene_receiver.viewer import LiveViewer


def _frame(frame_id: int) -> CaptureFrame:
    return CaptureFrame(
        frame_id=frame_id,
        timestamp_ns=1_700_000_000_000_000_000 + frame_id,
        rgb_jpeg=b"\xff\xd8rgb",
        depth_png=b"\x89PNGdepth",
        confidence_png=b"\x89PNHconf",
        metadata=FrameMetadata(width=640, height=480, depth_width=256, depth_height=192,
                               tracking_state="normal", depth_source="scene_depth"),
    )


def _post(url: str, payload: dict | None = None) -> dict:
    body = json.dumps(payload).encode() if payload is not None else None
    request = Request(url, data=body, method="POST",
                      headers={"Content-Type": "application/json"} if body else {})
    return json.loads(urlopen(request).read())


def test_live_view_serves_frames_and_controls_recording(tmp_path: Path):
    recording = RecordingController(tmp_path)
    viewer = LiveViewer(port=0, recording=recording)
    url = viewer.start()
    receiver = OpenBeneReceiver(recording=recording, viewer=viewer)
    try:
        receiver.handle_sample("openbene/rtr520/frame", encode_capture_frame(_frame(1)))

        state = json.loads(urlopen(url + "state.json").read())
        assert state["frames"] == 1
        assert state["sizes"]["rgb"] > 0
        assert state["recording"]["active"] is False
        assert state["stats"]["robot"] == "rtr520"

        image = urlopen(url + "frame.jpg")
        assert image.status == 200
        assert image.headers["Content-Type"] == "image/jpeg"
        assert image.read().startswith(b"\xff\xd8")

        started = _post(url + "record/start")
        assert started["active"] is True

        receiver.handle_sample("openbene/rtr520/frame", encode_capture_frame(_frame(2)))
        status = json.loads(urlopen(url + "state.json").read())
        assert status["recording"]["active"] is True
        assert status["recording"]["frames"] == 1

        stopped = _post(url + "record/stop")
        assert stopped["active"] is False
    finally:
        viewer.stop()

    files = list(tmp_path.glob("*.mcap"))
    assert len(files) == 1
    with files[0].open("rb") as handle:
        topics = [channel.topic for _, channel, _ in make_reader(handle).iter_messages()]
    assert "/openbene/rtr520/frame/meta" in topics
    assert len(topics) == 4  # meta + rgb + depth + confidence for frame 2


def test_sensor_samples_reach_the_viewer(tmp_path: Path):
    recording = RecordingController(tmp_path)
    viewer = LiveViewer(port=0, recording=recording)
    url = viewer.start()
    receiver = OpenBeneReceiver(recording=recording, viewer=viewer)
    try:
        sample = json.dumps(
            {
                "version": 1,
                "type": "sensor_data",
                "data": {
                    "accelerometer": {"x": 0.1, "y": 0.2, "z": 9.8},
                    "gyroscope": {"x": 0.01, "y": 0.02, "z": 0.03},
                    "battery_level": 0.9,
                },
                "timestamp": 1,
            }
        ).encode()
        receiver.handle_sample("openbene/rtr520/sensors", sample)

        state = json.loads(urlopen(url + "state.json").read())
        assert state["imu"]["latest"]["accelerometer"] == [0.1, 0.2, 9.8]
        assert state["imu"]["latest"]["gyroscope"] == [0.01, 0.02, 0.03]
        assert state["imu"]["latest"]["battery"] == 0.9
        assert len(state["imu"]["history"]) == 1
    finally:
        viewer.stop()


def test_command_endpoint_publishes_drive_and_stop():
    sent: list[tuple[float, float]] = []
    viewer = LiveViewer(port=0, command_publisher=lambda left, right: sent.append((left, right)))
    url = viewer.start()
    try:
        result = _post(url + "cmd/drive", {"left": 0.4, "right": -0.2})
        assert result == {"left": 0.4, "right": -0.2}
        assert sent == [(0.4, -0.2)]

        state = json.loads(urlopen(url + "state.json").read())
        assert state["command_enabled"] is True
        assert state["last_sent"] == {"left": 0.4, "right": -0.2}

        _post(url + "cmd/stop")
        assert sent[-1] == (0.0, 0.0)

        # Values are clamped before they reach the robot.
        _post(url + "cmd/drive", {"left": 5, "right": -9})
        assert sent[-1] == (1.0, -1.0)
    finally:
        viewer.stop()
