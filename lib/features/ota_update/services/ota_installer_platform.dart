import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Platform bridge for Android OTA installation and package manager checks.
class OtaInstallerPlatform {
  static const MethodChannel _channel = MethodChannel('com.easyconnect.app/ota_installer');

  /// Retrieves the running application's versionCode and versionName from PackageManager.
  static Future<Map<String, dynamic>> getAppVersion() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getAppVersion');
      return {
        'versionCode': (result?['versionCode'] as num?)?.toInt() ?? 0,
        'versionName': result?['versionName']?.toString() ?? '',
      };
    } on PlatformException catch (e) {
      debugPrint('OtaInstallerPlatform.getAppVersion failed: ${e.message}');
      return {'versionCode': 0, 'versionName': ''};
    }
  }

  /// Queries the free space in bytes available on the device cache partition.
  static Future<int> getAvailableDiskSpace() async {
    try {
      final bytes = await _channel.invokeMethod<int>('getAvailableDiskSpace');
      return bytes ?? 0;
    } on PlatformException catch (e) {
      debugPrint('OtaInstallerPlatform.getAvailableDiskSpace failed: ${e.message}');
      return -1; // -1 denotes unable to determine, will bypass strict block if unknown
    }
  }

  /// Checks if the app holds permission to request package installations (Android 8.0+).
  static Future<bool> canRequestPackageInstalls() async {
    try {
      final canInstall = await _channel.invokeMethod<bool>('canRequestPackageInstalls');
      return canInstall ?? false;
    } on PlatformException catch (e) {
      debugPrint('OtaInstallerPlatform.canRequestPackageInstalls failed: ${e.message}');
      return true;
    }
  }

  /// Opens the system Settings screen for "Install Unknown Apps" for this app.
  static Future<bool> openInstallPermissionSettings() async {
    try {
      final opened = await _channel.invokeMethod<bool>('openInstallPermissionSettings');
      return opened ?? false;
    } on PlatformException catch (e) {
      debugPrint('OtaInstallerPlatform.openInstallPermissionSettings failed: ${e.message}');
      return false;
    }
  }

  /// Launches the system Package Installer via FileProvider Intent.
  static Future<bool> installApk(String filePath) async {
    try {
      final success = await _channel.invokeMethod<bool>('installApk', {
        'filePath': filePath,
      });
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint('OtaInstallerPlatform.installApk failed: ${e.message}');
      return false;
    }
  }
}
