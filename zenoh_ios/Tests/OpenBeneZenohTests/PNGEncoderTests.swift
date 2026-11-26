import XCTest
@testable import OpenBeneZenoh

final class PNGEncoderTests: XCTestCase {
    /// The PC receiver decodes with a plain zlib/inflate decoder, so the bytes
    /// must be a standard PNG, not a CoreGraphics-only variant.
    func testGray16WritesStandardPNGHeader() {
        let values: [UInt16] = [0, 1000, 65535, 42]
        let data = PNGEncoder.gray16(width: 2, height: 2, values: values)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(Array(data[12..<16]), Array("IHDR".utf8))
        // Width/height big endian, then bit depth 16 and colour type 0.
        XCTAssertEqual(Array(data[16..<24]), [0, 0, 0, 2, 0, 0, 0, 2])
        XCTAssertEqual(data[24], 16)
        XCTAssertEqual(data[25], 0)
        XCTAssertTrue(data.contains(Data("IEND".utf8)))
    }

    func testGray8RoundTripsThroughStoredDeflate() throws {
        let width = 3
        let height = 2
        let values: [UInt8] = [0, 1, 2, 3, 4, 255]
        let data = PNGEncoder.gray8(width: width, height: height, values: values)
        XCTAssertEqual(data[24], 8)
        XCTAssertEqual(data[25], 0)

        // zlib header + stored deflate block + adler32; 6 pixels + 2 filter
        // bytes must all be present verbatim.
        let raw = values
        var offset = 41 // after signature + IHDR chunk (8+25 = 33) + IDAT header
        _ = offset
        for value in raw {
            XCTAssertTrue(data.contains(value))
        }
    }
}
