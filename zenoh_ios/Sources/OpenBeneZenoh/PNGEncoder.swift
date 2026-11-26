import Foundation
#if canImport(Compression)
import Compression
#endif

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
        out.reserveCapacity(payload.count + 12)
        out.appendBigEndian(UInt32(payload.count))
        let typeData = Data(type.utf8)
        out.append(typeData)
        out.append(payload)
        out.appendBigEndian(crc32(typeData, payload))
        return out
    }

    /// zlib stream. Uses the Compression framework when available (depth goes
    /// from ~98 KB to ~12 KB per frame) and falls back to stored blocks.
    private static func zlibStored(_ data: [UInt8]) -> Data {
        if let deflated = deflate(data) {
            var out = Data([0x78, 0x01])
            out.append(deflated)
            out.appendBigEndian(adler32(data))
            return out
        }
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

    private static func deflate(_ data: [UInt8]) -> Data? {
        #if canImport(Compression)
        guard !data.isEmpty else { return nil }
        let capacity = data.count + data.count / 2 + 64
        var buffer = [UInt8](repeating: 0, count: capacity)
        let written = data.withUnsafeBufferPointer { source in
            buffer.withUnsafeMutableBufferPointer { destination in
                compression_encode_buffer(
                    destination.baseAddress!, capacity,
                    source.baseAddress!, data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0, written < data.count else { return nil }
        return Data(buffer[0..<written])
        #else
        return nil
        #endif
    }

    /// Table driven CRC-32. The bit-at-a-time version cost ~8 operations per
    /// byte, which dominated the frame time on the phone.
    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB88320 : value >> 1
        }
        return value
    }

    private static func crc32(_ first: Data, _ second: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        crcTable.withUnsafeBufferPointer { table in
            for part in [first, second] {
                part.withUnsafeBytes { raw in
                    for byte in raw {
                        crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)]
                    }
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        data.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var index = 0
            let count = buffer.count
            // 5552 is the largest block that cannot overflow before reduction.
            while index < count {
                let end = min(index + 5552, count)
                while index < end {
                    a &+= UInt32(base[index])
                    b &+= a
                    index += 1
                }
                a %= 65521
                b %= 65521
            }
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
