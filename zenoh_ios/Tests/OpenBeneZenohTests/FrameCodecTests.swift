import XCTest
@testable import OpenBeneZenoh

final class FrameCodecTests: XCTestCase {
    /// Byte-for-byte match with Android `Protocol.encodeVideoFrame`.
    func testLegacyFrameMatchesAndroidLayout() throws {
        let jpeg = Data([0xAA, 0xBB])
        let encoded = FrameCodec.encodeLegacyVideoFrame(
            jpeg: jpeg,
            frameID: 7,
            timestampNs: 0x0102_0304_0506_0708
        )
        let expected = Data([
            0x5A, 0x46, 0x52, 0x4D, // "ZFRM"
            0x01, 0x00,             // version
            0x00, 0x00,             // flags
            0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
            0x07, 0x00, 0x00, 0x00,
            0xAA, 0xBB,
        ])
        XCTAssertEqual(encoded, expected)
        XCTAssertEqual(encoded.count, FrameCodec.legacyHeaderBytes + jpeg.count)

        let decoded = try FrameCodec.decodeLegacyVideoFrame(encoded)
        XCTAssertEqual(decoded.frameID, 7)
        XCTAssertEqual(decoded.timestampNs, 0x0102_0304_0506_0708)
        XCTAssertEqual(decoded.jpeg, jpeg)
    }

    func testCaptureFrameRoundTrip() throws {
        let metadata = FrameMetadata(
            width: 1920, height: 1440,
            depthWidth: 256, depthHeight: 192,
            fx: 1500, fy: 1500, cx: 960, cy: 720,
            trackingState: "normal",
            depthSource: "smoothed_scene_depth",
            confidenceWidth: 256, confidenceHeight: 192
        )
        let pose = (0..<16).map { Float($0) }
        let frame = CaptureFrame(
            frameID: 12,
            timestampNs: 1_700_000_000_123_456_789,
            rgbJPEG: Data([0xFF, 0xD8, 0xFF]),
            depthPNG: Data([0x89, 0x50, 0x4E, 0x47]),
            confidencePNG: Data([0x89, 0x50, 0x4E, 0x48]),
            pose: pose,
            metadata: metadata
        )

        let encoded = FrameCodec.encodeCaptureFrame(frame)
        XCTAssertEqual(Array(encoded.prefix(4)), [0x5A, 0x50, 0x4B, 0x44]) // "ZPKD"
        XCTAssertEqual(encoded.count, 24 + (8 + 3) + (8 + 4) + (8 + 4) + (8 + 64) + (8 + (try JSONEncoder.openBene.encode(metadata).count)))

        let decoded = try FrameCodec.decodeCaptureFrame(encoded)
        XCTAssertEqual(decoded, frame)
        XCTAssertEqual(FrameCodec.flags(for: frame), 0b1111)
    }

    func testTruncatedFrameThrows() {
        XCTAssertThrowsError(try FrameCodec.decodeCaptureFrame(Data([0x5A, 0x50])))
        XCTAssertThrowsError(try FrameCodec.decodeLegacyVideoFrame(Data([0x5A])))
    }

    func testRejectsWrongMagicAndVersion() {
        var frame = FrameCodec.encodeCaptureFrame(
            CaptureFrame(frameID: 1, timestampNs: 2, metadata: FrameMetadata(width: 1, height: 1))
        )
        frame[0] = 0x00
        XCTAssertThrowsError(try FrameCodec.decodeCaptureFrame(frame))

        var legacy = FrameCodec.encodeLegacyVideoFrame(jpeg: Data([1]), frameID: 1, timestampNs: 1)
        legacy[4] = 0x09
        XCTAssertThrowsError(try FrameCodec.decodeLegacyVideoFrame(legacy))
    }
}
