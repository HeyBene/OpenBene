import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Request camera permission.
  /// On iOS, if previously denied the system dialog won't show again;
  /// callers should check [isCameraPermanentlyDenied] and use [openSettings].
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Returns true if the camera permission was denied and can no longer be
  /// requested via a system dialog (user must go to Settings).
  Future<bool> isCameraPermanentlyDenied() async {
    final status = await Permission.camera.status;
    return status.isPermanentlyDenied || status.isDenied;
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

  /// Request all required permissions.
  /// Returns a map with 'camera' and 'cameraNeedsSettings' keys.
  /// 'cameraNeedsSettings' is true when iOS cannot show the dialog anymore.
  Future<Map<String, dynamic>> requestAllPermissions() async {
    // Check current status first
    final currentStatus = await Permission.camera.status;

    // If already denied/permanentlyDenied, don't request again (iOS won't
    // show the dialog) — tell the caller to open Settings instead.
    if (currentStatus.isDenied || currentStatus.isPermanentlyDenied) {
      return {
        'camera': false,
        'cameraNeedsSettings': true,
        'storage': true,
      };
    }

    final cameraStatus = await Permission.camera.request();
    return {
      'camera': cameraStatus.isGranted,
      'cameraNeedsSettings': false,
      'storage': true,
    };
  }

  Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
