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
      // Convert YUV420 to RGB
      final int width = image.width;
      final int height = image.height;

      // Create image from YUV420
      final img.Image imgImage = img.Image(width: width, height: height);

      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int uvIndex =
              uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
          final int index = y * width + x;

          final yp = image.planes[0].bytes[index];
          final up = image.planes[1].bytes[uvIndex];
          final vp = image.planes[2].bytes[uvIndex];

          int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
          int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
              .round()
              .clamp(0, 255);
          int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);

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
