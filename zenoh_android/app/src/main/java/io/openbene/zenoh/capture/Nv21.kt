package io.openbene.zenoh.capture

import java.nio.ByteBuffer

/**
 * Copies Camera2 YUV_420_888 planes into the NV21 layout that YuvImage wants.
 *
 * Kept separate from [CameraSource] so the stride handling can be unit tested
 * without a camera (row strides differ between vendors).
 */
object Nv21 {
    fun size(width: Int, height: Int): Int = width * height * 3 / 2

    fun writeLuma(
        buffer: ByteBuffer,
        rowStride: Int,
        pixelStride: Int,
        width: Int,
        height: Int,
        out: ByteArray,
    ) {
        val src = buffer.duplicate()
        val row = ByteArray(maxOf(rowStride, width))
        var position = 0
        for (line in 0 until height) {
            val start = line * rowStride
            if (start >= src.limit()) break
            src.position(start)
            val length = minOf(rowStride, src.remaining())
            src.get(row, 0, length)
            if (pixelStride == 1) {
                val copy = minOf(width, length)
                System.arraycopy(row, 0, out, position, copy)
                position += width
            } else {
                var source = 0
                var column = 0
                while (column < width && source < length) {
                    out[position++] = row[source]
                    source += pixelStride
                    column++
                }
            }
        }
    }

    /** NV21 interleaves V then U; Camera2 hands them over as separate planes. */
    fun writeChroma(
        vBuffer: ByteBuffer,
        vRowStride: Int,
        vPixelStride: Int,
        uBuffer: ByteBuffer,
        uRowStride: Int,
        uPixelStride: Int,
        width: Int,
        height: Int,
        out: ByteArray,
    ) {
        val chromaWidth = width / 2
        val chromaHeight = height / 2
        val v = vBuffer.duplicate()
        val u = uBuffer.duplicate()
        val vRow = ByteArray(maxOf(vRowStride, chromaWidth))
        val uRow = ByteArray(maxOf(uRowStride, chromaWidth))
        var position = width * height
        for (line in 0 until chromaHeight) {
            val vStart = line * vRowStride
            val uStart = line * uRowStride
            if (vStart >= v.limit() || uStart >= u.limit()) break
            v.position(vStart)
            val vLength = minOf(vRowStride, v.remaining())
            v.get(vRow, 0, vLength)
            u.position(uStart)
            val uLength = minOf(uRowStride, u.remaining())
            u.get(uRow, 0, uLength)

            var vIndex = 0
            var uIndex = 0
            var column = 0
            while (column < chromaWidth && vIndex < vLength && uIndex < uLength) {
                out[position++] = vRow[vIndex]
                out[position++] = uRow[uIndex]
                vIndex += vPixelStride
                uIndex += uPixelStride
                column++
            }
        }
    }
}
