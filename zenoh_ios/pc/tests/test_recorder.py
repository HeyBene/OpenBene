import json
from pathlib import Path

from mcap.reader import make_reader

from openbene_receiver.protocol import CaptureFrame, FrameMetadata, encode_capture_frame, encode_legacy_video
from openbene_receiver.recorder import RecordingController
from openbene_receiver.receiver import OpenBeneReceiver


def _frame(frame_id: int, timestamp_ns: int) -> CaptureFrame:
    return CaptureFrame(
        frame_id=frame_id,
        timestamp_ns=timestamp_ns,
        rgb_jpeg=b"\xff\xd8rgb",
        depth_png=b"\x89PNGdepth",
        confidence_png=b"\x89PNHconf",
        pose=tuple(float(i) for i in range(16)),
        metadata=FrameMetadata(width=640, height=480, depth_width=256, depth_height=192),
        flags=0b1111,
    )


def test_records_frames_and_json_to_mcap(tmp_path: Path):
    path = tmp_path / "run.mcap"
    recording = RecordingController(tmp_path)
    recording.start(path)
    receiver = OpenBeneReceiver(recording=recording)

    for frame_id in (1, 2, 3):
        receiver.handle_sample(
            "openbene/rtr520/frame",
            encode_capture_frame(_frame(frame_id, 1_700_000_000_000_000_000 + frame_id)),
            received_ns=1_700_000_000_000_000_000,
        )
    receiver.handle_sample(
        "openbene/rtr520/video",
        encode_legacy_video(b"\xff\xd8legacy", 9, 1_700_000_000_000_000_010),
    )
    receiver.handle_sample(
        "openbene/rtr520/status",
        json.dumps({"version": 1, "robot_id": "rtr520", "state": "online"}).encode(),
    )
    summary = recording.stop()

    assert summary["frames"] == 3
    assert summary["legacy_frames"] == 1
    assert summary["gaps"] == 0
    assert summary["decode_errors"] == 0
    assert path.exists()
    assert path.with_suffix(".mcap.meta.json").exists()

    with path.open("rb") as handle:
        reader = make_reader(handle)
        stats = reader.get_summary()
        topics = sorted(channel.topic for channel in stats.channels.values())
        messages = list(reader.iter_messages())

    assert "/openbene/rtr520/frame/meta" in topics
    assert "/openbene/rtr520/frame/rgb" in topics
    assert "/openbene/rtr520/frame/depth" in topics
    assert "/openbene/rtr520/frame/confidence" in topics
    assert "/openbene/rtr520/video" in topics
    assert "/openbene/rtr520/status" in topics

    meta_messages = [m for _, channel, m in messages if channel.topic == "/openbene/rtr520/frame/meta"]
    assert len(meta_messages) == 3
    first = json.loads(meta_messages[0].data)
    assert first["frame_id"] == 1
    assert first["sizes"]["rgb"] == len(b"\xff\xd8rgb")
    assert first["metadata"]["width"] == 640
    assert len(first["pose"]) == 16


def test_no_recording_until_started(tmp_path: Path):
    recording = RecordingController(tmp_path)
    receiver = OpenBeneReceiver(recording=recording)

    receiver.handle_sample("openbene/rtr520/frame", encode_capture_frame(_frame(1, 1_700_000_000_000_000_000)))
    assert recording.active is False
    assert list(tmp_path.glob("*.mcap")) == []

    recording.start()
    receiver.handle_sample("openbene/rtr520/frame", encode_capture_frame(_frame(2, 1_700_000_000_000_000_001)))
    summary = recording.stop()
    assert summary["frames"] == 1
    assert list(tmp_path.glob("*.mcap"))


def test_detects_gaps_and_monotonic_clock(tmp_path: Path):
    recording = RecordingController(tmp_path)
    recording.start(tmp_path / "gaps.mcap")
    receiver = OpenBeneReceiver(recording=recording)
    receiver.handle_sample(
        "openbene/rtr520/frame",
        encode_capture_frame(_frame(1, 5_000_000)),
        received_ns=1_700_000_000_000_000_000,
    )
    receiver.handle_sample(
        "openbene/rtr520/frame",
        encode_capture_frame(_frame(4, 5_100_000)),
        received_ns=1_700_000_000_100_000_000,
    )
    recording.stop()

    assert receiver.stats.gaps == 2
    with (tmp_path / "gaps.mcap").open("rb") as handle:
        messages = list(make_reader(handle).iter_messages())
    log_times = sorted(message.log_time for _, _, message in messages)
    assert log_times[0] >= 1_700_000_000_000_000_000


def test_bad_payload_counts_decode_error(tmp_path: Path):
    receiver = OpenBeneReceiver(recording=RecordingController(tmp_path))
    receiver.handle_sample("openbene/rtr520/frame", b"not-a-frame")
    receiver.handle_sample("openbene/rtr520/status", b"{not json")
    receiver.handle_sample("other/robot/status", b"{}")

    assert receiver.stats.decode_errors == 2
    assert receiver.stats.ignored == 1
    assert receiver.stats.primary_robot == "rtr520"
