import Foundation
import simd

/// Converts ARKit camera transform to Nerfstudio/NeRF convention.
///
/// ARKit: right-handed, camera looks along +Z (in camera local frame, but
/// the transform_matrix from ARKit is camera-to-world).
///
/// Nerfstudio (OpenGL convention): camera looks along -Z in camera space.
/// The standard fix is to flip Y and Z axes of the camera-local frame:
///   column 1 (Y) negated, column 2 (Z) negated.
///
/// This produces a camera-to-world matrix in OpenGL/NeRF convention.
enum PoseTransformAdapter {

    /// Convert an ARKit camera-to-world transform to Nerfstudio convention.
    /// Returns a 4x4 matrix as [[Float]] (row-major, for JSON serialization).
    static func arkitToNerfstudio(_ arTransform: simd_float4x4) -> [[Float]] {
        // ARKit simd_float4x4 is column-major.
        // We need to negate columns 1 and 2 (Y and Z) to go from
        // ARKit camera convention to OpenGL/NeRF camera convention.
        var m = arTransform
        m.columns.1 = -m.columns.1  // negate Y
        m.columns.2 = -m.columns.2  // negate Z

        // Convert to row-major [[Float]] for JSON
        return [
            [m.columns.0.x, m.columns.1.x, m.columns.2.x, m.columns.3.x],
            [m.columns.0.y, m.columns.1.y, m.columns.2.y, m.columns.3.y],
            [m.columns.0.z, m.columns.1.z, m.columns.2.z, m.columns.3.z],
            [0, 0, 0, 1]
        ]
    }
}
