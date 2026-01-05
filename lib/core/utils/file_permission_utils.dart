import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/logger.dart';

/// Utility class for handling file storage permissions
class FilePermissionUtils {
  /// Request storage permissions for file access
  static Future<bool> requestStoragePermissions() async {
    try {
      if (kIsWeb) {
        // Web doesn't need storage permissions for file picker
        return true;
      }

      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final androidVersion = androidInfo.version.sdkInt;

      // Android 13+ (API 33+) uses granular media permissions
      if (androidVersion >= 33) {
        return await _requestAndroid13PlusPermissions();
      } else {
        // Android < 13 uses storage permission
        return await _requestLegacyStoragePermissions();
      }
    } catch (e) {
      AppLogger.error('Error requesting storage permissions: $e', tag: 'PERMISSIONS');
      return false;
    }
  }

  /// Check if storage permissions are granted
  static Future<bool> checkStoragePermissions() async {
    try {
      if (kIsWeb) {
        return true;
      }

      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final androidVersion = androidInfo.version.sdkInt;

      if (androidVersion >= 33) {
        final imagesPermission = await Permission.photos.isGranted;
        final videosPermission = await Permission.videos.isGranted;
        final audioPermission = await Permission.audio.isGranted;

        return imagesPermission || videosPermission || audioPermission;
      } else {
        return await Permission.storage.isGranted;
      }
    } catch (e) {
      AppLogger.error('Error checking storage permissions: $e', tag: 'PERMISSIONS');
      return false;
    }
  }

  /// Request permissions for Android 13+ (API 33+)
  static Future<bool> _requestAndroid13PlusPermissions() async {
    try {
      final Map<Permission, PermissionStatus> statuses;

      // Request multiple media permissions
      statuses = await [
        Permission.photos,
        Permission.videos,
        Permission.audio,
        Permission.storage, // Still request for backward compatibility
      ].request();

      final photosGranted = statuses[Permission.photos]?.isGranted ?? false;
      final videosGranted = statuses[Permission.videos]?.isGranted ?? false;
      final audioGranted = statuses[Permission.audio]?.isGranted ?? false;
      final storageGranted = statuses[Permission.storage]?.isGranted ?? false;

      final hasPermission = photosGranted || videosGranted || audioGranted || storageGranted;

      if (hasPermission) {
        AppLogger.info('Media permissions granted for Android 13+', tag: 'PERMISSIONS');
      } else {
        AppLogger.warning('Media permissions denied for Android 13+', tag: 'PERMISSIONS');

        // Check if any permission is permanently denied
        final photosPermanentlyDenied = statuses[Permission.photos]?.isPermanentlyDenied ?? false;
        final videosPermanentlyDenied = statuses[Permission.videos]?.isPermanentlyDenied ?? false;
        final audioPermanentlyDenied = statuses[Permission.audio]?.isPermanentlyDenied ?? false;
        final storagePermanentlyDenied = statuses[Permission.storage]?.isPermanentlyDenied ?? false;

        if (photosPermanentlyDenied || videosPermanentlyDenied || audioPermanentlyDenied || storagePermanentlyDenied) {
          _showPermissionDeniedDialog();
        }
      }

      return hasPermission;
    } catch (e) {
      AppLogger.error('Error requesting Android 13+ permissions: $e', tag: 'PERMISSIONS');
      return false;
    }
  }

  /// Request legacy storage permissions for Android < 13
  static Future<bool> _requestLegacyStoragePermissions() async {
    try {
      final status = await Permission.storage.request();

      if (status.isGranted) {
        AppLogger.info('Storage permission granted for Android < 13', tag: 'PERMISSIONS');
        return true;
      } else {
        AppLogger.warning('Storage permission denied for Android < 13', tag: 'PERMISSIONS');

        if (status.isPermanentlyDenied) {
          _showPermissionDeniedDialog();
        }

        return false;
      }
    } catch (e) {
      AppLogger.error('Error requesting legacy storage permissions: $e', tag: 'PERMISSIONS');
      return false;
    }
  }

  /// Show dialog for permanently denied permissions
  static void _showPermissionDeniedDialog() {
    AppLogger.warning('Permissions permanently denied. User needs to enable in app settings.', tag: 'PERMISSIONS');

    // Note: In a real implementation, you might want to show a dialog to the user
    // explaining why the permission is needed and direct them to app settings
    // For now, we'll just log the message
  }

  /// Open app settings for manual permission grant
  static Future<void> openAppSettings() async {
    try {
      await openAppSettings();
      AppLogger.info('Opened app settings for permission configuration', tag: 'PERMISSIONS');
    } catch (e) {
      AppLogger.error('Error opening app settings: $e', tag: 'PERMISSIONS');
    }
  }

  /// Get detailed permission status for debugging
  static Future<Map<String, bool>> getPermissionStatus() async {
    final status = <String, bool>{};

    try {
      if (kIsWeb) {
        status['web'] = true;
        return status;
      }

      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final androidVersion = androidInfo.version.sdkInt;

      if (androidVersion >= 33) {
        status['photos'] = await Permission.photos.isGranted;
        status['videos'] = await Permission.videos.isGranted;
        status['audio'] = await Permission.audio.isGranted;
        status['storage'] = await Permission.storage.isGranted;
      } else {
        status['storage'] = await Permission.storage.isGranted;
      }

      // Note: android_version is int, not bool, so we store it differently
        status['has_android_13_plus'] = androidVersion >= 33;
    } catch (e) {
      AppLogger.error('Error getting permission status: $e', tag: 'PERMISSIONS');
    }

    return status;
  }
}