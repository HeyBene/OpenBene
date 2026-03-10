import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Request camera permission.
  /// On iOS, if previously denied the system dialog won't show again;
  /// callers should check [isCameraPermanentlyDenied] and use [openSettings].
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Returns true if the camera permission was permanently denied and can no
  /// longer be requested via a system dialog (user must go to Settings).
  /// Note: isDenied on iOS also covers "notDetermined" (never asked), so we
  /// must NOT treat isDenied alone as permanently denied.
  Future<bool> isCameraPermanentlyDenied() async {
    final status = await Permission.camera.status;
    return status.isPermanentlyDenied;
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
    // Always call .request() directly — no pre-check needed.
    // On iOS, permission_handler's .request() handles all states correctly:
    //   - notDetermined (fresh install) → shows system dialog
    //   - denied (user tapped "Don't Allow") → returns permanentlyDenied, no dialog
    //   - authorized → returns granted immediately
    // Any pre-check that bails out early on .isDenied or .isPermanentlyDenied
    // risks skipping the .request() call on the very first launch, which
    // prevents iOS from ever registering camera usage for this app (so the
    // toggle would never appear in Settings → Privacy → Camera).
    final cameraStatus = await Permission.camera.request();
    return {
      'camera': cameraStatus.isGranted,
      'cameraNeedsSettings': cameraStatus.isPermanentlyDenied,
      'storage': true,
    };
  }

  Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
