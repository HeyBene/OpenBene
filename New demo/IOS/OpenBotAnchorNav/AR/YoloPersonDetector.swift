import CoreML
import Vision

/// One serialized instance, shared with the AR camera rather than opening a
/// second capture session. Missing/incompatible weights are surfaced as errors.
final class YoloPersonDetector {
    static var modelName: String {
        if #available(iOS 16.0, *) { return "yolo11n" }
        return "YOLOv3TinyInt8LUT"
    }
    private var model: VNCoreMLModel?
    private let modelURL: URL?
    init(modelURL: URL? = nil) { self.modelURL = modelURL }

    func detect(_ image: CVPixelBuffer) throws -> [VNRecognizedObjectObservation] {
        let model: VNCoreMLModel
        if let cached = self.model { model = cached }
        else {
            guard let url = modelURL ?? Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc") else {
                throw NSError(domain: "YoloPersonDetector", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少\(Self.modelName)离线模型。"])
            }
            let config = MLModelConfiguration(); config.computeUnits = .all
            let loaded = try MLModel(contentsOf: url, configuration: config)
            model = try VNCoreMLModel(for: loaded)
            model.featureProvider = try MLDictionaryFeatureProvider(dictionary: ["confidenceThreshold": 0.25, "iouThreshold": 0.45])
            self.model = model
        }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit
        try VNImageRequestHandler(cvPixelBuffer: image, orientation: .right, options: [:]).perform([request])
        guard let objects = request.results as? [VNRecognizedObjectObservation] else {
            throw NSError(domain: "YoloPersonDetector", code: 2, userInfo: [NSLocalizedDescriptionKey: "YOLO模型输出不是带类别的人体框。"])
        }
        return objects.filter { $0.labels.first?.identifier == "person" }
    }
}
