package io.openbene.zenoh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtocolTest {

    @Test
    fun sanitizeRobotId_keeps_key_expression_safe() {
        assertEquals("rtr520", Protocol.sanitizeRobotId("rtr520"))
        assertEquals("robot_1", Protocol.sanitizeRobotId("robot/1"))
        assertEquals("robot", Protocol.sanitizeRobotId("  "))
    }

    @Test
    fun normalizeEndpoint_adds_tcp_prefix() {
        assertEquals("tcp/192.168.1.10:7447", Protocol.normalizeEndpoint("192.168.1.10:7447"))
        assertEquals("tcp/192.168.1.10:7447", Protocol.normalizeEndpoint("tcp/192.168.1.10:7447"))
        assertEquals("udp/192.168.1.10:7447", Protocol.normalizeEndpoint("udp/192.168.1.10:7447"))
    }

    @Test
    fun drive_command_round_trips() {
        val json = Protocol.encodeDrive(0.25, -0.5, sequence = 7, nowMs = 1000, ttlMs = 250)
        val parsed = Protocol.parseCommand(json)
        assertTrue(parsed is RobotCommand.Drive)
        parsed as RobotCommand.Drive
        assertEquals(0.25, parsed.left, 0.0001)
        assertEquals(-0.5, parsed.right, 0.0001)
        assertEquals(7L, parsed.sequence)
        assertEquals(1000L, parsed.sentAtMs)
        assertEquals(250L, parsed.ttlMs)
    }

    @Test
    fun stop_command_round_trips() {
        val parsed = Protocol.parseCommand(Protocol.encodeStop(sequence = 9, nowMs = 2000))
        assertTrue(parsed is RobotCommand.Stop)
        assertEquals(9L, parsed.sequence)
    }

    @Test
    fun video_header_has_expected_magic_and_length() {
        val jpeg = byteArrayOf(1, 2, 3, 4)
        val frame = Protocol.encodeVideoFrame(jpeg, frameId = 3, timestampNs = 1234)
        assertEquals(Protocol.VIDEO_HEADER_BYTES + jpeg.size, frame.size)
        assertArrayEquals(jpeg, frame.copyOfRange(Protocol.VIDEO_HEADER_BYTES, frame.size))
        assertEquals(0x5A, frame[0].toInt() and 0xFF)
        assertEquals(0x46, frame[1].toInt() and 0xFF)
        assertEquals(0x52, frame[2].toInt() and 0xFF)
        assertEquals(0x4D, frame[3].toInt() and 0xFF)
    }
}
