import Foundation

/// Geometry and provenance for one synchronized capture frame.
public struct FrameMetadata: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var depthWidth: Int
    public var depthHeight: Int
    public var fx: Double
    public var fy: Double
    public var cx: Double
    public var cy: Double
    public var trackingState: String
    public var depthSource: String
    public var confidenceWidth: Int
    public var confidenceHeight: Int

    public init(
        width: Int,
        height: Int,
        depthWidth: Int = 0,
        depthHeight: Int = 0,
        fx: Double = 0,
        fy: Double = 0,
        cx: Double = 0,
        cy: Double = 0,
        trackingState: String = "unknown",
        depthSource: String = "none",
        confidenceWidth: Int = 0,
        confidenceHeight: Int = 0
    ) {
        self.width = width
        self.height = height
        self.depthWidth = depthWidth
        self.depthHeight = depthHeight
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.trackingState = trackingState
        self.depthSource = depthSource
        self.confidenceWidth = confidenceWidth
        self.confidenceHeight = confidenceHeight
    }
}

/// One capture frame as produced by the iOS capture pipeline.
public struct CaptureFrame: Equatable, Sendable {
    public var frameID: UInt32
    public var timestampNs: UInt64
    public var rgbJPEG: Data?
    public var depthPNG: Data?
    public var confidencePNG: Data?
    /// Column-major 4x4 camera-to-world matrix (ARKit convention), 16 floats.
    public var pose: [Float]?
    public var metadata: FrameMetadata

    public init(
        frameID: UInt32,
        timestampNs: UInt64,
        rgbJPEG: Data? = nil,
        depthPNG: Data? = nil,
        confidencePNG: Data? = nil,
        pose: [Float]? = nil,
        metadata: FrameMetadata
    ) {
        self.frameID = frameID
        self.timestampNs = timestampNs
        self.rgbJPEG = rgbJPEG
        self.depthPNG = depthPNG
        self.confidencePNG = confidencePNG
        self.pose = pose
        self.metadata = metadata
    }
}

public enum FrameCodecError: Error, Equatable, LocalizedError {
    case truncated(needed: Int, available: Int)
    case badMagic(UInt32)
    case unsupportedVersion(UInt16)
    case malformedSection(type: UInt32, length: UInt32)

    public var errorDescription: String? {
        switch self {
        case .truncated(let needed, let available):
            return "Frame truncated: need \(needed) bytes, have \(available)"
        case .badMagic(let magic):
            return "Bad frame magic 0x\(String(magic, radix: 16))"
        case .unsupportedVersion(let version):
            return "Unsupported frame version \(version)"
        case .malformedSection(let type, let length):
            return "Malformed frame section \(type) with length \(length)"
        }
    }
}

/// Binary framing shared with `zenoh_android`.
///
/// `ZFRM` is the Android-era payload: a 20-byte header followed by raw JPEG.
///
///     magic(4) | version(2) | flags(2) | timestamp_ns(8) | frame_id(4) | JPEG
///
/// `ZPKD` carries the richer iOS capture frame. All integers are little endian:
///
///     magic(4) | version(2) | flags(2) | timestamp_ns(8) | frame_id(4) | section_count(4)
///     repeated: type(4) | length(4) | payload(length)
///
/// Section types: 1 JPEG, 2 depth PNG, 3 confidence PNG, 4 pose float32[16],
/// 5 metadata JSON.
public enum FrameCodec {
    public static let legacyMagic: UInt32 = 0x4D52_465A // "ZFRM" on the wire
    public static let packetMagic: UInt32 = 0x444B_505A // "ZPKD" on the wire
    public static let legacyHeaderBytes = 20
    public static let packetHeaderBytes = 24
    public static let maxSectionBytes = 64 * 1024 * 1024

    public enum Section: UInt32, CaseIterable, Sendable {
        case rgbJPEG = 1
        case depthPNG = 2
        case confidencePNG = 3
        case pose = 4
        case metadata = 5
    }

    // MARK: - Legacy single-image frame

    public static func encodeLegacyVideoFrame(
        jpeg: Data,
        frameID: UInt32,
        timestampNs: UInt64,
        flags: UInt16 = 0
    ) -> Data {
        var data = Data(capacity: legacyHeaderBytes + jpeg.count)
        data.appendLE(legacyMagic)
        data.appendLE(OpenBeneProtocol.version)
        data.appendLE(flags)
        data.appendLE(timestampNs)
        data.appendLE(frameID)
        data.append(jpeg)
        return data
    }

    public static func decodeLegacyVideoFrame(_ data: Data) throws -> (frameID: UInt32, timestampNs: UInt64, jpeg: Data) {
        guard data.count >= legacyHeaderBytes else {
            throw FrameCodecError.truncated(needed: legacyHeaderBytes, available: data.count)
        }
        var reader = ByteReader(data: data)
        let magic: UInt32 = try reader.readLE()
        guard magic == legacyMagic else { throw FrameCodecError.badMagic(magic) }
        let version: UInt16 = try reader.readLE()
        guard version == OpenBeneProtocol.version else { throw FrameCodecError.unsupportedVersion(version) }
        _ = try reader.readLE() as UInt16 // flags
        let timestampNs: UInt64 = try reader.readLE()
        let frameID: UInt32 = try reader.readLE()
        return (frameID, timestampNs, data.subdata(in: reader.offset..<data.count))
    }

    // MARK: - Multi-plane capture packet

    public static func encodeCaptureFrame(_ frame: CaptureFrame) -> Data {
        var sections: [(Section, Data)] = []
        if let rgbJPEG = frame.rgbJPEG { sections.append((.rgbJPEG, rgbJPEG)) }
        if let depthPNG = frame.depthPNG { sections.append((.depthPNG, depthPNG)) }
        if let confidencePNG = frame.confidencePNG { sections.append((.confidencePNG, confidencePNG)) }
        if let pose = frame.pose, pose.count == 16 {
            sections.append((.pose, pose.withUnsafeBufferPointer { Data(buffer: $0) }))
        }
        if let metadata = try? JSONEncoder.openBene.encode(frame.metadata) {
            sections.append((.metadata, metadata))
        }

        var data = Data(capacity: packetHeaderBytes + sections.reduce(0) { $0 + $1.1.count + 8 })
        data.appendLE(packetMagic)
        data.appendLE(OpenBeneProtocol.version)
        data.appendLE(flags(for: frame))
        data.appendLE(frame.timestampNs)
        data.appendLE(frame.frameID)
        data.appendLE(UInt32(sections.count))
        for (section, payload) in sections {
            data.appendLE(section.rawValue)
            data.appendLE(UInt32(payload.count))
            data.append(payload)
        }
        return data
    }

    public static func decodeCaptureFrame(_ data: Data) throws -> CaptureFrame {
        guard data.count >= packetHeaderBytes else {
            throw FrameCodecError.truncated(needed: packetHeaderBytes, available: data.count)
        }
        var reader = ByteReader(data: data)
        let magic: UInt32 = try reader.readLE()
        guard magic == packetMagic else { throw FrameCodecError.badMagic(magic) }
        let version: UInt16 = try reader.readLE()
        guard version == OpenBeneProtocol.version else { throw FrameCodecError.unsupportedVersion(version) }
        _ = try reader.readLE() as UInt16 // flags
        let timestampNs: UInt64 = try reader.readLE()
        let frameID: UInt32 = try reader.readLE()
        let sectionCount: UInt32 = try reader.readLE()

        var rgb: Data?
        var depth: Data?
        var confidence: Data?
        var pose: [Float]?
        var metadata = FrameMetadata(width: 0, height: 0)

        for _ in 0..<sectionCount {
            let type: UInt32 = try reader.readLE()
            let length: UInt32 = try reader.readLE()
            guard length <= UInt32(maxSectionBytes), reader.offset + Int(length) <= data.count else {
                throw FrameCodecError.malformedSection(type: type, length: length)
            }
            let payload = data.subdata(in: reader.offset..<(reader.offset + Int(length)))
            reader.offset += Int(length)
            switch Section(rawValue: type) {
            case .rgbJPEG: rgb = payload
            case .depthPNG: depth = payload
            case .confidencePNG: confidence = payload
            case .pose:
                guard payload.count == 64 else {
                    throw FrameCodecError.malformedSection(type: type, length: length)
                }
                pose = payload.withUnsafeBytes { raw in
                    Array(raw.bindMemory(to: Float.self))
                }
            case .metadata:
                guard let decoded = try? JSONDecoder().decode(FrameMetadata.self, from: payload) else {
                    throw FrameCodecError.malformedSection(type: type, length: length)
                }
                metadata = decoded
            case nil:
                continue // forward compatible: unknown sections are skipped
            }
        }

        return CaptureFrame(
            frameID: frameID,
            timestampNs: timestampNs,
            rgbJPEG: rgb,
            depthPNG: depth,
            confidencePNG: confidence,
            pose: pose,
            metadata: metadata
        )
    }

    public static func flags(for frame: CaptureFrame) -> UInt16 {
        var flags: UInt16 = 0
        if frame.rgbJPEG != nil { flags |= 1 << 0 }
        if frame.depthPNG != nil { flags |= 1 << 1 }
        if frame.confidencePNG != nil { flags |= 1 << 2 }
        if frame.pose?.count == 16 { flags |= 1 << 3 }
        return flags
    }
}

extension JSONEncoder {
    static var openBene: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

struct ByteReader {
    let data: Data
    var offset: Int = 0

    mutating func readLE<T: FixedWidthInteger>() throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else {
            throw FrameCodecError.truncated(needed: offset + size, available: data.count)
        }
        var value: T = 0
        _ = withUnsafeMutableBytes(of: &value) { destination in
            data.copyBytes(to: destination, from: offset..<(offset + size))
        }
        offset += size
        return T(littleEndian: value)
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
