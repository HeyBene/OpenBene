import Foundation

/// Minimal PNG writer (no Apple frameworks) so the phone can emit depth and
/// confidence planes that any decoder can read.
///
/// Depth stays 16-bit and little endian, matching what CoreGraphics produced
/// before and what the PC decoder expects; confidence is 8-bit gray.
public enum PNGEncoder {
    public static func gray8(width: Int, height: Int, values: [UInt8]) -> Data {
        precondition(values.count == width * height, "pixel count mismatch")
        return encode(width: width, height: height, bitDepth: 8, colorType: 0) {
            var raw = [UInt8]()
            raw.reserveCapacity((width + 1) * height)
            for row in 0..<height {
                raw.append(0)
                raw.append(contentsOf: values[(row * width)..<((row + 1) * width)])
            }
            return raw
        }
    }

    public static func gray16(width: Int, height: Int, values: [UInt16]) -> Data {
        precondition(values.count == width * height, "pixel count mismatch")
        return encode(width: width, height: height, bitDepth: 16, colorType: 0) {
            var raw = [UInt8]()
            raw.reserveCapacity((width * 2 + 1) * height)
            for row in 0..<height {
                raw.append(0)
                for column in 0..<width {
                    let value = values[row * width + column].littleEndian
                    raw.append(UInt8(value & 0xFF))
                    raw.append(UInt8(value >> 8))
                }
            }
            return raw
        }
    }

    private static func encode(
        width: Int,
        height: Int,
        bitDepth: Int,
        colorType: UInt8,
        scanlines: () -> [UInt8]
    ) -> Data {
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.appendBigEndian(UInt32(width))
        header.appendBigEndian(UInt32(height))
        header.append(UInt8(bitDepth))
        header.append(colorType)
        header.append(contentsOf: [0, 0, 0])
        png.append(chunk("IHDR", header))
        png.append(chunk("IDAT", zlibStored(scanlines())))
        png.append(chunk("IEND", Data()))
        return png
    }

    private static func chunk(_ type: String, _ payload: Data) -> Data {
        var out = Data()
        out.appendBigEndian(UInt32(payload.count))
        let typeData = Data(type.utf8)
        out.append(typeData)
        out.append(payload)
        var crcInput = Data()
        crcInput.append(typeData)
        crcInput.append(payload)
        out.appendBigEndian(crc32(crcInput))
        return out
    }

    /// zlib stream with uncompressed (stored) deflate blocks.
    private static func zlibStored(_ data: [UInt8]) -> Data {
        var out = Data([0x78, 0x01])
        var index = 0
        if data.isEmpty {
            out.append(contentsOf: [0x01, 0x00, 0x00, 0xFF, 0xFF])
        }
        while index < data.count {
            let length = min(65535, data.count - index)
            let isFinal = index + length >= data.count
            out.append(isFinal ? 0x01 : 0x00)
            out.append(UInt8(length & 0xFF))
            out.append(UInt8((length >> 8) & 0xFF))
            let inverted = ~UInt16(length)
            out.append(UInt8(inverted & 0xFF))
            out.append(UInt8((inverted >> 8) & 0xFF))
            out.append(contentsOf: data[index..<(index + length)])
            index += length
        }
        out.appendBigEndian(adler32(data))
        return out
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }
}

extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
