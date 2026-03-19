import Foundation
import simd

/// 位姿适配器。
/// 用来把 ARKit 相机坐标系转换成 Nerfstudio / OpenGL 更常见的相机约定。
enum PoseTransformAdapter {

    /// 将 ARKit 的 camera-to-world 矩阵转换为 Nerfstudio 约定。
    /// 返回值使用 [[Float]]，便于直接写入 JSON。
    static func arkitToNerfstudio(_ arTransform: simd_float4x4) -> [[Float]] {
        // ARKit 是列主序矩阵。
        // 这里对相机局部坐标的 Y、Z 轴取反，统一到 OpenGL/NeRF 常见约定。
        var m = arTransform
        m.columns.1 = -m.columns.1
        m.columns.2 = -m.columns.2

        // 转成按行输出的二维数组，便于 JSON 序列化。
        return [
            [m.columns.0.x, m.columns.1.x, m.columns.2.x, m.columns.3.x],
            [m.columns.0.y, m.columns.1.y, m.columns.2.y, m.columns.3.y],
            [m.columns.0.z, m.columns.1.z, m.columns.2.z, m.columns.3.z],
            [0, 0, 0, 1]
        ]
    }
}
