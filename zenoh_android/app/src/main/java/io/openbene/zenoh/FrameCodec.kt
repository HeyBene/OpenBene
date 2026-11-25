package io.openbene.zenoh

import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Geometry and provenance for one synchronized capture frame. */
data class FrameMetadata(
    val width: Int = 0,
    val height: Int = 0,
    val depthWidth: Int = 0,
    val depthHeight: Int = 0,
    val fx: Double = 0.0,
    val fy: Double = 0.0,
    val cx: Double = 0.0,
    val cy: Double = 0.0,
    val trackingState: String = "unknown",
    val depthSource: String = "none",
    val confidenceWidth: Int = 0,
    val confidenceHeight: Int = 0,
) {
    fun toJson(): String = JSONObject()
        .put("width", width)
        .put("height", height)
        .put("depthWidth", depthWidth)
        .put("depthHeight", depthHeight)
        .put("fx", fx)
        .put("fy", fy)
        .put("cx", cx)
        .put("cy", cy)
        .put("trackingState", trackingState)
        .put("depthSource", depthSource)
        .put("confidenceWidth", confidenceWidth)
        .put("confidenceHeight", confidenceHeight)
        .toString()

    companion object {
        /** Mirrors the Swift decoder: missing keys fall back to defaults. */
        fun fromJson(raw: String): FrameMetadata = try {
            val root = JSONObject(raw)
            FrameMetadata(
                width = root.optInt("width", 0),
                height = root.optInt("height", 0),
                depthWidth = root.optInt("depthWidth", 0),
                depthHeight = root.optInt("depthHeight", 0),
                fx = root.optDouble("fx", 0.0),
                fy = root.optDouble("fy", 0.0),
                cx = root.optDouble("cx", 0.0),
                cy = root.optDouble("cy", 0.0),
                trackingState = root.optString("trackingState", "unknown"),
                depthSource = root.optString("depthSource", "none"),
                confidenceWidth = root.optInt("confidenceWidth", 0),
                confidenceHeight = root.optInt("confidenceHeight", 0),
            )
        } catch (error: Exception) {
            FrameMetadata()
        }
    }
}

/**
 * One capture frame, wire compatible with `zenoh_ios/FrameCodec.swift`.
 *
 * [frameId] is a 32-bit counter on the wire; [pose] is a column-major 4x4
 * camera-to-world matrix. Depth is PNG with uint16 millimetres, confidence is
 * mono8 PNG.
 */
data class CaptureFrame(
    val frameId: Long,
    val timestampNs: Long,
    val rgbJpeg: ByteArray? = null,
    val depthPng: ByteArray? = null,
    val confidencePng: ByteArray? = null,
    val pose: FloatArray? = null,
    val metadata: FrameMetadata = FrameMetadata(),
)

class FrameCodecException(message: String) : Exception(message)

/**
 * Binary framing shared with the iOS SDK and the PC receiver.
 *
 * `ZFRM` (20-byte header, then JPEG) is the legacy Android payload published
 * on `.../video`.
 *
 * `ZPKD` adds sections so RGB, depth, confidence, pose and metadata travel in
 * one message: magic(4) | version(2) | flags(2) | timestamp_ns(8) |
 * frame_id(4) | section_count(4), then repeated type(4) | length(4) | payload.
 * Unknown section types are skipped so newer senders stay readable.
 */
object FrameCodec {
    // Little-endian encoding of "ZPKD" on the wire.
    const val PACKET_MAGIC = 0x444B505A
    const val PACKET_HEADER_BYTES = 24
    const val MAX_SECTION_BYTES = 64 * 1024 * 1024

    const val SECTION_RGB_JPEG = 1
    const val SECTION_DEPTH_PNG = 2
    const val SECTION_CONFIDENCE_PNG = 3
    const val SECTION_POSE = 4
    const val SECTION_METADATA = 5

    fun flagsFor(frame: CaptureFrame): Int {
        var flags = 0
        if (frame.rgbJpeg != null) flags = flags or (1 shl 0)
        if (frame.depthPng != null) flags = flags or (1 shl 1)
        if (frame.confidencePng != null) flags = flags or (1 shl 2)
        if (frame.pose?.size == 16) flags = flags or (1 shl 3)
        return flags
    }

    fun encode(frame: CaptureFrame): ByteArray {
        val sections = ArrayList<Pair<Int, ByteArray>>(5)
        frame.rgbJpeg?.let { sections.add(SECTION_RGB_JPEG to it) }
        frame.depthPng?.let { sections.add(SECTION_DEPTH_PNG to it) }
        frame.confidencePng?.let { sections.add(SECTION_CONFIDENCE_PNG to it) }
        frame.pose?.takeIf { it.size == 16 }?.let { pose ->
            val payload = ByteBuffer.allocate(pose.size * 4).order(ByteOrder.LITTLE_ENDIAN)
            pose.forEach { payload.putFloat(it) }
            sections.add(SECTION_POSE to payload.array())
        }
        sections.add(SECTION_METADATA to frame.metadata.toJson().toByteArray(Charsets.UTF_8))

        val total = PACKET_HEADER_BYTES + sections.sumOf { it.second.size + 8 }
        val buffer = ByteBuffer.allocate(total).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(PACKET_MAGIC)
        buffer.putShort(Protocol.VERSION.toShort())
        buffer.putShort(flagsFor(frame).toShort())
        buffer.putLong(frame.timestampNs)
        buffer.putInt(frame.frameId.toInt())
        buffer.putInt(sections.size)
        sections.forEach { (type, payload) ->
            buffer.putInt(type)
            buffer.putInt(payload.size)
            buffer.put(payload)
        }
        return buffer.array()
    }

    fun decode(bytes: ByteArray): CaptureFrame {
        if (bytes.size < PACKET_HEADER_BYTES) {
            throw FrameCodecException(
                "Frame truncated: need $PACKET_HEADER_BYTES bytes, have ${bytes.size}",
            )
        }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        val magic = buffer.int
        if (magic != PACKET_MAGIC) {
            throw FrameCodecException("Bad frame magic 0x${Integer.toHexString(magic)}")
        }
        val version = buffer.short.toInt() and 0xFFFF
        if (version != Protocol.VERSION) {
            throw FrameCodecException("Unsupported frame version $version")
        }
        buffer.short // flags
        val timestampNs = buffer.long
        val frameId = buffer.int.toLong() and 0xFFFFFFFFL
        val sectionCount = buffer.int
        if (sectionCount < 0 || sectionCount > bytes.size / 8) {
            throw FrameCodecException("Implausible section count $sectionCount")
        }

        var rgb: ByteArray? = null
        var depth: ByteArray? = null
        var confidence: ByteArray? = null
        var pose: FloatArray? = null
        var metadata = FrameMetadata()

        repeat(sectionCount) {
            if (buffer.remaining() < 8) {
                throw FrameCodecException("Section header truncated at offset ${buffer.position()}")
            }
            val type = buffer.int
            val length = buffer.int
            if (length < 0 || length > MAX_SECTION_BYTES || length > buffer.remaining()) {
                throw FrameCodecException("Malformed frame section $type with length $length")
            }
            val payload = ByteArray(length)
            buffer.get(payload)
            when (type) {
                SECTION_RGB_JPEG -> rgb = payload
                SECTION_DEPTH_PNG -> depth = payload
                SECTION_CONFIDENCE_PNG -> confidence = payload
                SECTION_POSE -> {
                    if (payload.size != 64) {
                        throw FrameCodecException("Malformed frame section $type with length $length")
                    }
                    val floats = FloatArray(16)
                    val reader = ByteBuffer.wrap(payload).order(ByteOrder.LITTLE_ENDIAN)
                    for (index in floats.indices) floats[index] = reader.float
                    pose = floats
                }

                SECTION_METADATA -> metadata = FrameMetadata.fromJson(
                    payload.toString(Charsets.UTF_8),
                )
                // Unknown sections are intentionally skipped for forward compatibility.
            }
        }

        return CaptureFrame(
            frameId = frameId,
            timestampNs = timestampNs,
            rgbJpeg = rgb,
            depthPng = depth,
            confidencePng = confidence,
            pose = pose,
            metadata = metadata,
        )
    }
}
