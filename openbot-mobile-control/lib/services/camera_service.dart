import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class CameraService {
  CameraController? _controller;
  bool _isStreaming = false;
  StreamController<Uint8List>? _frameStreamController;

  Stream<Uint8List>? get frameStream => _frameStreamController?.stream;
  bool get isStreaming => _isStreaming;
  CameraController? get controller => _controller;

  Future<void> initialize({int quality = 85}) async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      // Use back camera by default
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
    } catch (e) {
      throw Exception('Failed to initialize camera: $e');
    }
  }

  Future<void> startStreaming({
    required Function(Uint8List) onFrame,
    int quality = 85,
    int targetWidth = 640,
  }) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('Camera not initialized');
    }

    if (_isStreaming) {
      return;
    }

    _isStreaming = true;
    _frameStreamController = StreamController<Uint8List>.broadcast();

    await _controller!.startImageStream((CameraImage image) async {
      if (!_isStreaming) return;

      try {
        // Convert CameraImage to JPEG
        final jpegBytes = await _convertImageToJpeg(
          image,
          quality: quality,
          targetWidth: targetWidth,
        );

        if (jpegBytes != null) {
          _frameStreamController?.add(jpegBytes);
          onFrame(jpegBytes);
        }
      } catch (e) {
        debugPrint('Error processing frame: $e');
      }
    });
  }

  Future<Uint8List?> _convertImageToJpeg(
    CameraImage image, {
    int quality = 85,
    int targetWidth = 640,
  }) async {
    try {
      final int width = image.width;
      final int height = image.height;

      // Create image buffer
      final img.Image imgImage = img.Image(width: width, height: height);

      // Get plane data
      final Uint8List yPlane = image.planes[0].bytes;
      final Uint8List uPlane = image.planes[1].bytes;
      final Uint8List vPlane = image.planes[2].bytes;

      final int yRowStride = image.planes[0].bytesPerRow;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * yRowStride + x;
          final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

          // Get YUV values
          final int yValue = yPlane[yIndex];
          final int uValue = uPlane[uvIndex];
          final int vValue = vPlane[uvIndex];

          // YUV to RGB conversion (BT.601 standard)
          int r = ((yValue + 1.402 * (vValue - 128))).round().clamp(0, 255);
          int g = ((yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))).round().clamp(0, 255);
          int b = ((yValue + 1.772 * (uValue - 128))).round().clamp(0, 255);

          imgImage.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      // Resize if needed
      img.Image resized = imgImage;
      if (width > targetWidth) {
        final int targetHeight = (height * targetWidth / width).round();
        resized = img.copyResize(
          imgImage,
          width: targetWidth,
          height: targetHeight,
        );
      }

      // Encode to JPEG
      final jpegBytes = img.encodeJpg(resized, quality: quality);
      return Uint8List.fromList(jpegBytes);
    } catch (e) {
      debugPrint('Error converting image to JPEG: $e');
      return null;
    }
  }

  Future<void> stopStreaming() async {
    if (!_isStreaming) return;

    _isStreaming = false;

    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }

    await _frameStreamController?.close();
    _frameStreamController = null;
  }

  Future<void> dispose() async {
    await stopStreaming();
    await _controller?.dispose();
    _controller = null;
  }

  Future<Uint8List?> takePicture({int quality = 85}) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('Camera not initialized');
    }

    try {
      final XFile picture = await _controller!.takePicture();
      final bytes = await picture.readAsBytes();

      // Optionally compress
      final image = img.decodeImage(bytes);
      if (image != null) {
        final compressed = img.encodeJpg(image, quality: quality);
        return Uint8List.fromList(compressed);
      }

      return bytes;
    } catch (e) {
      debugPrint('Error taking picture: $e');
      return null;
    }
  }
}
