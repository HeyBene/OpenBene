package io.openbene.zenoh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class FrameCodecTest {

    @Test
    fun packet_magic_is_zpkd_on_the_wire() {
        val frame = CaptureFrame(frameId = 1L, timestampNs = 0L, rgbJpeg = byteArrayOf(9))
        val encoded = FrameCodec.encode(frame)
        assertEquals(0x5A, encoded[0].toInt() and 0xFF)
        assertEquals(0x50, encoded[1].toInt() and 0xFF)
        assertEquals(0x4B, encoded[2].toInt() and 0xFF)
        assertEquals(0x44, encoded[3].toInt() and 0xFF)
    }

    @Test
    fun header_fields_match_the_ios_layout() {
        val encoded = FrameCodec.encode(
            CaptureFrame(
                frameId = 0x01020304L,
                timestampNs = 0x1122334455667788L,
                rgbJpeg = byteArrayOf(1, 2),
            ),
        )
        val reader = ByteBuffer.wrap(encoded).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(FrameCodec.PACKET_MAGIC, reader.int)
        assertEquals(Protocol.VERSION, reader.short.toInt())
        assertEquals(1, reader.short.toInt()) // flags: rgb only
        assertEquals(0x1122334455667788L, reader.long)
        assertEquals(0x01020304, reader.int)
        assertEquals(2, reader.int) // rgb + metadata section
        assertEquals(FrameCodec.SECTION_RGB_JPEG, reader.int)
        assertEquals(2, reader.int)
        assertEquals(1, reader.get().toInt())
        assertEquals(2, reader.get().toInt())
        assertEquals(FrameCodec.SECTION_METADATA, reader.int)
    }

    @Test
    fun capture_frame_round_trips_every_plane() {
        val pose = FloatArray(16) { it.toFloat() + 0.5f }
        val frame = CaptureFrame(
            frameId = 42L,
            timestampNs = 987_654_321L,
            rgbJpeg = byteArrayOf(1, 2, 3),
            depthPng = byteArrayOf(4, 5),
            confidencePng = byteArrayOf(6),
            pose = pose,
            metadata = FrameMetadata(
                width = 1920,
                height = 1440,
                depthWidth = 256,
                depthHeight = 192,
                fx = 1000.5,
                fy = 1000.25,
                cx = 960.0,
                cy = 720.0,
                trackingState = "normal",
                depthSource = "lidar",
                confidenceWidth = 256,
                confidenceHeight = 192,
            ),
        )

        val decoded = FrameCodec.decode(FrameCodec.encode(frame))

        assertEquals(42L, decoded.frameId)
        assertEquals(987_654_321L, decoded.timestampNs)
        assertArrayEquals(frame.rgbJpeg, decoded.rgbJpeg)
        assertArrayEquals(frame.depthPng, decoded.depthPng)
        assertArrayEquals(frame.confidencePng, decoded.confidencePng)
        assertArrayEquals(pose, decoded.pose, 0.0f)
        assertEquals(frame.metadata, decoded.metadata)
    }

    @Test
    fun flags_describe_present_planes() {
        val full = CaptureFrame(
            frameId = 1L,
            timestampNs = 1L,
            rgbJpeg = byteArrayOf(1),
            depthPng = byteArrayOf(1),
            confidencePng = byteArrayOf(1),
            pose = FloatArray(16),
        )
        assertEquals(0b1111, FrameCodec.flagsFor(full))
        assertEquals(0, FrameCodec.flagsFor(CaptureFrame(frameId = 1L, timestampNs = 1L)))
        assertEquals(1, FrameCodec.flagsFor(full.copy(depthPng = null, confidencePng = null, pose = null)))
    }

    @Test
    fun unknown_sections_are_skipped() {
        val encoded = FrameCodec.encode(
            CaptureFrame(frameId = 7L, timestampNs = 8L, rgbJpeg = byteArrayOf(2)),
        )
        val withExtra = ByteBuffer.allocate(encoded.size + 8 + 3).order(ByteOrder.LITTLE_ENDIAN)
        withExtra.put(encoded)
        withExtra.putInt(99) // unknown section type
        withExtra.putInt(3)
        withExtra.put(byteArrayOf(7, 7, 7))
        // bump the section count from 2 to 3
        val patched = withExtra.array()
        patched[20] = 3

        val decoded = FrameCodec.decode(patched)
        assertArrayEquals(byteArrayOf(2), decoded.rgbJpeg)
    }

    @Test
    fun truncated_and_corrupt_frames_are_rejected() {
        assertTrue(runCatching { FrameCodec.decode(ByteArray(10)) }.isFailure)
        val bad = FrameCodec.encode(CaptureFrame(frameId = 1L, timestampNs = 1L))
        bad[0] = 0
        assertTrue(runCatching { FrameCodec.decode(bad) }.isFailure)
    }

    @Test
    fun metadata_json_uses_ios_camel_case_keys() {
        val json = FrameMetadata(width = 8, height = 6, depthWidth = 4, depthHeight = 3, trackingState = "normal")
            .toJson()
        assertTrue(json.contains("\"depthWidth\":4"))
        assertTrue(json.contains("\"depthHeight\":3"))
        assertTrue(json.contains("\"trackingState\":\"normal\""))
        assertEquals(8, FrameMetadata.fromJson(json).width)
    }

    @Test
    fun legacy_video_frame_stays_byte_compatible() {
        val jpeg = byteArrayOf(9, 8, 7)
        val frame = Protocol.encodeVideoFrame(jpeg, frameId = 5L, timestampNs = 6L)
        assertEquals(Protocol.VIDEO_HEADER_BYTES + jpeg.size, frame.size)
        val reader = ByteBuffer.wrap(frame).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(Protocol.VIDEO_MAGIC, reader.int)
        assertEquals(Protocol.VERSION, reader.short.toInt())
        assertEquals(0, reader.short.toInt()) // flags
        assertEquals(6L, reader.long)
        assertEquals(5, reader.int)
    }

    @Test
    fun session_event_matches_ios_shape() {
        val json = SessionEvent.Start.toJson("rtr/520", "sess-1", nowMs = 1234L)
        assertTrue(json.contains("\"event\":\"start\""))
        assertTrue(json.contains("\"session_id\":\"sess-1\""))
        assertTrue(json.contains("\"robot_id\":\"rtr_520\""))
        assertTrue(json.contains("\"timestamp\":1234"))
        assertNotNull(json)
    }
}
