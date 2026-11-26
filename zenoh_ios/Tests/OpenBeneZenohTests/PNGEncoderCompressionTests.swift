import XCTest
@testable import OpenBeneZenoh

final class PNGEncoderCompressionTests: XCTestCase {
    func testDepthPNGStaysSmallForSmoothData() {
        let width = 256, height = 192
        let values: [UInt16] = (0..<(width * height)).map { UInt16(300 + ($0 / width) * 4) }
        let data = PNGEncoder.gray16(width: width, height: height, values: values)
        // Uncompressed would be ~98 KB; smooth ramps must compress well.
        XCTAssertLessThan(data.count, 20_000, "depth PNG should be compressed")
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testRandomDataStillProducesValidPNG() {
        var generator = SystemRandomNumberGenerator()
        let values: [UInt16] = (0..<(64 * 64)).map { _ in UInt16.random(in: 0...65535, using: &generator) }
        let data = PNGEncoder.gray16(width: 64, height: 64, values: values)
        XCTAssertEqual(Array(data[12..<16]), Array("IHDR".utf8))
        XCTAssertTrue(data.contains(Data("IEND".utf8)))
    }
}
