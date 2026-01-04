import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<bool> requestStoragePermission() async {
    final status = await Permission.storage.request();
    return status.isGranted || status.isLimited;
  }

  Future<bool> checkCameraPermission() async {
    return await Permission.camera.isGranted;
  }

  Future<bool> checkStoragePermission() async {
    final status = await Permission.storage.status;
    return status.isGranted || status.isLimited;
  }

  Future<Map<String, bool>> requestAllPermissions() async {
    final results = await [
      Permission.camera,
      Permission.storage,
    ].request();

    return {
      'camera': results[Permission.camera]?.isGranted ?? false,
      'storage': results[Permission.storage]?.isGranted ?? false,
    };
  }

  Future<bool> openAppSettings() async {
    return await openAppSettings();
  }
}
