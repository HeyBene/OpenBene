# Offline person detectors

The app runs these bundled weights through `VNCoreMLRequest`, selects only the
COCO `person` class, and never downloads a model at runtime. No custom training
or identity recognition is provided. Model failures appear in the tracking UI.

## iOS 16 and later: YOLO11n

- Source: [Ultralytics official iOS app release v8.3.0](https://github.com/ultralytics/yolo-ios-app/releases/tag/v8.3.0).
- Asset: [yolo11n.mlpackage.zip](https://github.com/ultralytics/yolo-ios-app/releases/download/v8.3.0/yolo11n.mlpackage.zip).
- Archive SHA-256: `c7f0276ee436fea565a1626aae18865e4f683722248f4de6d39bd55939374649`.
- Original package retained without changes. Embedded metadata: Ultralytics
  8.3.139, exported 2025-05-18, int8, NMS enabled, image 384×640, 80 classes.
- License: AGPL-3.0, as declared in the model metadata. The upstream license
  is included in `YOLO-LICENSE.txt` and applies to these weights.
- This model's MLProgram requires iOS 16. The runtime selects it only on
  iOS 16+, while keeping the app deployment target at iOS 15. Xcode may warn
  about the model's minimum OS when compiling it for the iOS 15 app target.

## iOS 15: YOLOv3 Tiny

- Source: [Apple machine learning model catalog](https://developer.apple.com/machine-learning/models/).
- Asset: [YOLOv3TinyInt8LUT.mlmodel](https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3TinyInt8LUT.mlmodel).
- File SHA-256: `cde8af2528d6eca1d1580fdd0f0147cb6613d40ba962656b5f683c65f571870e`.
- Original model retained without changes. Embedded metadata: YOLOv3-tiny,
  Apple model catalog version 2.0; authors Joseph Redmon and Ali Farhadi.
- The embedded license field directs readers to
  [pjreddie/darknet](https://github.com/pjreddie/darknet) for license information.
  The model metadata is preserved in the distributed file.

## Inference and controller

`YoloPersonDetector` serializes lazy CoreML loading/inference off the UI thread.
It requests confidence threshold 0.25 and IoU threshold 0.45. The optional 0.6
confidence experiment is a separate UI switch. Vision uses `.right` orientation
and `.scaleFit`; the driver converts the returned normalized boxes through
ARKit's display transform into the visible portrait viewport.

`PersonTargetTracker` associates boxes geometrically and smooths their horizontal
center and estimates horizontal motion. `ObjectFollowSteering` uses forward
differential commands for small errors and braking/pivot priority near the
image sides. The detector runs at up to 15 Hz.
Changing detector weights alone does not establish stable or collision-free
following. Near-person stopping uses ARKit scene-depth measurements inside
the matched body ROI, corrected for camera pitch. The old top-edge stopping
experiment has been removed because a pitched camera can clip distant heads.
