package io.openbene.zenoh

import io.openbene.zenoh.ble.OpenBotFrames
import io.openbene.zenoh.capture.CameraIntrinsics
import io.openbene.zenoh.capture.Nv21
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.ByteBuffer

class CaptureTest {

    @Test
    fun chassis_command_matches_the_flutter_app() {
        assertEquals("c128,-255", OpenBotFrames.control(128, -255))
        assertEquals("c0,0", OpenBotFrames.control(0, 0))
    }

    @Test
    fun chassis_command_is_newline_terminated_and_chunked() {
        val chunks = OpenBotFrames.chunks("c128,-255")
        assertEquals(1, chunks.size)
        assertEquals("c128,-255\n", String(chunks[0], Charsets.UTF_8))

        val long = OpenBotFrames.chunks("x".repeat(45))
        assertEquals(listOf(20, 20, 6), long.map { it.size })
    }

    @Test
    fun chassis_uuids_match_the_firmware() {
        assertEquals("61653dc3-4021-4d1e-ba83-8b4eec61d613", OpenBotFrames.SERVICE_UUID.toString())
        assertEquals("06386c14-86ea-4d71-811c-48f97c58f8c9", OpenBotFrames.RX_UUID.toString())
        assertEquals("9bf1103b-834c-47cf-b149-c9e4bcf778a7", OpenBotFrames.TX_UUID.toString())
    }

    @Test
    fun luma_copy_handles_tightly_packed_rows() {
        val buffer = ByteBuffer.wrap(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8))
        val out = ByteArray(Nv21.size(4, 2))
        Nv21.writeLuma(buffer, rowStride = 4, pixelStride = 1, width = 4, height = 2, out = out)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8), out.copyOfRange(0, 8))
    }

    @Test
    fun luma_copy_drops_row_padding() {
        val buffer = ByteBuffer.wrap(byteArrayOf(1, 2, 3, 4, 99, 99, 5, 6, 7, 8, 99, 99))
        val out = ByteArray(Nv21.size(4, 2))
        Nv21.writeLuma(buffer, rowStride = 6, pixelStride = 1, width = 4, height = 2, out = out)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8), out.copyOfRange(0, 8))
    }

    @Test
    fun luma_copy_handles_interleaved_planes() {
        // Semi-planar Y with pixelStride 2 (Y + padding per pixel).
        val buffer = ByteBuffer.wrap(byteArrayOf(1, 0, 2, 0, 3, 0, 4, 0))
        val out = ByteArray(Nv21.size(4, 1))
        Nv21.writeLuma(buffer, rowStride = 8, pixelStride = 2, width = 4, height = 1, out = out)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), out.copyOfRange(0, 4))
    }

    @Test
    fun chroma_copy_interleaves_v_then_u() {
        val v = ByteBuffer.wrap(byteArrayOf(11, 12))
        val u = ByteBuffer.wrap(byteArrayOf(21, 22))
        val out = ByteArray(Nv21.size(4, 2))
        Nv21.writeChroma(
            vBuffer = v, vRowStride = 2, vPixelStride = 1,
            uBuffer = u, uRowStride = 2, uPixelStride = 1,
            width = 4, height = 2, out = out,
        )
        assertArrayEquals(byteArrayOf(11, 21, 12, 22), out.copyOfRange(8, 12))
    }

    @Test
    fun intrinsics_scale_with_the_analysis_resolution() {
        val base = CameraIntrinsics(
            fx = 1400.0, fy = 1400.0, cx = 960.0, cy = 720.0,
            width = 1920, height = 1440, source = "camera2_calibration",
        )
        val scaled = base.scaledTo(1280, 960)
        assertEquals(1280, scaled.width)
        assertEquals(960, scaled.height)
        assertEquals(1400.0 * 1280 / 1920, scaled.fx, 1e-9)
        assertEquals(960.0 * 1280 / 1920, scaled.cx, 1e-9)
        assertEquals("camera2_calibration", scaled.source)
    }

    @Test
    fun nv21_buffer_is_one_and_a_half_bytes_per_pixel() {
        assertEquals(1280 * 720 * 3 / 2, Nv21.size(1280, 720))
    }
}
