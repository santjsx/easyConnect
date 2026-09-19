import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:easyconnect/features/ota_update/models/ota_metadata.dart';
import 'package:easyconnect/features/ota_update/services/ota_installer_platform.dart';

/// Riverpod provider for OtaUpdateService
final otaUpdateServiceProvider = Provider<OtaUpdateService>((ref) {
  return OtaUpdateService();
});

/// Riverpod StateNotifierProvider for reactive UI consumption
final otaStateProvider = StateNotifierProvider<OtaStateNotifier, OtaEngineState>((ref) {
  final service = ref.watch(otaUpdateServiceProvider);
  return OtaStateNotifier(service);
});

class OtaUpdateService {
  final String repoOwner;
  final String repoName;

  /// In-memory cache of failed checksum attempts per versionCode
  final Map<int, int> _failedAttempts = {};

  /// Keep track of dismissed version codes for flexible updates
  final Set<int> _dismissedVersionCodes = {};

  HttpClient? _activeClient;
  bool _isDownloading = false;

  OtaUpdateService({
    this.repoOwner = 'santjsx',
    this.repoName = 'easyConnect',
  });

  /// Maximum allowed checksum failures before blocking automatic loops
  static const int maxFailureThreshold = 3;

  /// 25 MB safety buffer over the APK size
  static const int diskSafetyBufferBytes = 25 * 1024 * 1024;

  // ─────────────────────────────────────────────────────────────────────────
  // TELEMETRY
  // ─────────────────────────────────────────────────────────────────────────
  void _logTelemetry(String event, Map<String, dynamic> data) {
    debugPrint('[OTA Telemetry] $event: ${jsonEncode(data)}');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHECK FOR UPDATES
  // ─────────────────────────────────────────────────────────────────────────
  Future<OtaCheckResult> checkForUpdates({
    bool isManual = false,
    String channel = 'stable', // 'stable' | 'beta'
  }) async {
    _logTelemetry('update_check_initiated', {
      'channel': channel,
      'isManual': isManual,
    });

    final appVersion = await OtaInstallerPlatform.getAppVersion();
    final currentVersionCode = appVersion['versionCode'] as int? ?? 0;
    final currentVersionName = appVersion['versionName'] as String? ?? '1.0.0';

    try {
      final OtaMetadata? metadata = await _fetchMetadata(channel: channel);

      if (metadata == null) {
        return OtaCheckResult.noUpdate(
          currentVersionCode: currentVersionCode,
          currentVersionName: currentVersionName,
        );
      }

      // Security Check: Downgrade Attack Protection
      if (metadata.versionCode < currentVersionCode) {
        _logTelemetry('downgrade_attempt_ignored', {
          'serverVersionCode': metadata.versionCode,
          'currentVersionCode': currentVersionCode,
        });
        return OtaCheckResult.downgradeIgnored(
          currentVersionCode: currentVersionCode,
          currentVersionName: currentVersionName,
        );
      }

      // Check if already on latest or higher version
      if (metadata.versionCode <= currentVersionCode) {
        _logTelemetry('already_up_to_date', {
          'versionCode': currentVersionCode,
        });
        return OtaCheckResult.noUpdate(
          currentVersionCode: currentVersionCode,
          currentVersionName: currentVersionName,
        );
      }

      // Check failure loop threshold
      final failures = _failedAttempts[metadata.versionCode] ?? 0;
      if (!isManual && failures >= maxFailureThreshold) {
        _logTelemetry('max_failures_threshold_exceeded', {
          'versionCode': metadata.versionCode,
          'failures': failures,
        });
        return OtaCheckResult.error(
          message: 'Update paused: multiple verification failures occurred. Tap Check Updates to retry.',
          currentVersionCode: currentVersionCode,
          currentVersionName: currentVersionName,
        );
      }

      final isMandatory = metadata.isMandatoryFor(currentVersionCode);

      // If flexible update was dismissed in this session and this isn't a manual check, skip prompt
      if (!isMandatory && !isManual && _dismissedVersionCodes.contains(metadata.versionCode)) {
        return OtaCheckResult.noUpdate(
          currentVersionCode: currentVersionCode,
          currentVersionName: currentVersionName,
        );
      }

      _logTelemetry('update_detected', {
        'versionCode': metadata.versionCode,
        'versionName': metadata.versionName,
        'isMandatory': isMandatory,
      });

      return OtaCheckResult.updateAvailable(
        metadata: metadata,
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
      );
    } catch (e, stack) {
      debugPrint('Error checking for updates: $e\n$stack');
      _logTelemetry('update_check_failed', {'error': e.toString()});
      return OtaCheckResult.error(
        message: 'Could not connect to update service: ${e.toString()}',
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FETCH METADATA FROM GITHUB
  // ─────────────────────────────────────────────────────────────────────────
  Future<OtaMetadata?> _fetchMetadata({required String channel}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);

    try {
      // Direct raw release asset URL (avoids GitHub API 60 req/hr rate limiting)
      final directUrl = channel == 'beta'
          ? 'https://raw.githubusercontent.com/$repoOwner/$repoName/main/release-metadata.json'
          : 'https://github.com/$repoOwner/$repoName/releases/latest/download/release-metadata.json';

      final request = await client.getUrl(Uri.parse(directUrl));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'EasyConnect-OTA/1.0');
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        return OtaMetadata.fromJson(json);
      }

      // Fallback to GitHub Releases API if direct asset download returned 404
      final apiUrl = channel == 'beta'
          ? 'https://api.github.com/repos/$repoOwner/$repoName/releases'
          : 'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

      final apiRequest = await client.getUrl(Uri.parse(apiUrl));
      apiRequest.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github.v3+json');
      apiRequest.headers.set(HttpHeaders.userAgentHeader, 'EasyConnect-OTA/1.0');
      final apiResponse = await apiRequest.close();

      if (apiResponse.statusCode == 200) {
        final apiBody = await apiResponse.transform(utf8.decoder).join();
        final dynamic parsed = jsonDecode(apiBody);

        Map<String, dynamic>? releaseData;
        if (parsed is List && parsed.isNotEmpty) {
          releaseData = parsed.first as Map<String, dynamic>;
        } else if (parsed is Map<String, dynamic>) {
          releaseData = parsed;
        }

        if (releaseData != null && releaseData.containsKey('assets')) {
          final assets = releaseData['assets'] as List<dynamic>;
          for (final asset in assets) {
            if (asset['name'] == 'release-metadata.json') {
              final browserDownloadUrl = asset['browser_download_url'] as String?;
              if (browserDownloadUrl != null) {
                final metaReq = await client.getUrl(Uri.parse(browserDownloadUrl));
                final metaResp = await metaReq.close();
                if (metaResp.statusCode == 200) {
                  final metaBody = await metaResp.transform(utf8.decoder).join();
                  return OtaMetadata.fromJson(jsonDecode(metaBody) as Map<String, dynamic>);
                }
              }
            }
          }
        }
      }
      return null;
    } finally {
      client.close();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DOWNLOAD & CRYPTOGRAPHIC VERIFICATION
  // ─────────────────────────────────────────────────────────────────────────
  Future<File> downloadAndVerify({
    required OtaMetadata metadata,
    required void Function(OtaDownloadProgress) onProgress,
  }) async {
    if (_isDownloading) {
      throw StateError('A download is already in progress.');
    }

    _isDownloading = true;

    // 1. Pre-flight Disk Space Check
    final freeBytes = await OtaInstallerPlatform.getAvailableDiskSpace();
    if (freeBytes > 0 && metadata.fileSizeBytes > 0) {
      final requiredBytes = metadata.fileSizeBytes + diskSafetyBufferBytes;
      if (freeBytes < requiredBytes) {
        _isDownloading = false;
        final freeMb = (freeBytes / (1024 * 1024)).toStringAsFixed(1);
        final neededMb = (requiredBytes / (1024 * 1024)).toStringAsFixed(1);
        _logTelemetry('insufficient_disk_space', {
          'freeBytes': freeBytes,
          'requiredBytes': requiredBytes,
        });
        throw Exception(
          'Insufficient disk space. Device has $freeMb MB free, but update requires at least $neededMb MB.',
        );
      }
    }

    // 2. Prepare destination path in app cache directory
    final cacheDir = await getTemporaryDirectory();
    final otaDir = Directory('${cacheDir.path}/ota_updates');
    if (!await otaDir.exists()) {
      await otaDir.create(recursive: true);
    }

    final targetFile = File('${otaDir.path}/easyconnect-v${metadata.versionCode}.apk');
    if (await targetFile.exists()) {
      // Check if existing file already matches SHA-256 (resuming / already complete)
      final existingSha = await _computeSha256(targetFile);
      if (existingSha.toLowerCase() == metadata.sha256.toLowerCase()) {
        _logTelemetry('existing_download_verified', {
          'versionCode': metadata.versionCode,
        });
        _isDownloading = false;
        return targetFile;
      }
      // If mismatch, delete stale file
      await targetFile.delete();
    }

    // 3. Initiate Streaming Download with TLS 1.3
    _logTelemetry('download_started', {
      'versionCode': metadata.versionCode,
      'url': metadata.apkUrl,
      'expectedSha256': metadata.sha256,
    });

    _activeClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);

    IOSink? sink;
    try {
      final request = await _activeClient!.getUrl(Uri.parse(metadata.apkUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'EasyConnect-OTA/1.0');
      final response = await request.close();

      if (response.statusCode != 200 && response.statusCode != 302) {
        throw HttpException(
          'Download server returned HTTP ${response.statusCode}',
          uri: Uri.parse(metadata.apkUrl),
        );
      }

      final contentLength = response.contentLength > 0
          ? response.contentLength
          : metadata.fileSizeBytes;

      sink = targetFile.openWrite();
      int receivedBytes = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final fraction = contentLength > 0 ? (receivedBytes / contentLength) : 0.0;
        onProgress(OtaDownloadProgress(
          bytesDownloaded: receivedBytes,
          totalBytes: contentLength,
          fraction: fraction.clamp(0.0, 1.0),
        ));
      }

      await sink.flush();
      await sink.close();
      sink = null;

      // 4. Cryptographic SHA-256 Validation
      _logTelemetry('download_completed_verifying', {
        'versionCode': metadata.versionCode,
        'bytes': receivedBytes,
      });

      final calculatedSha = await _computeSha256(targetFile);

      if (calculatedSha.toLowerCase() != metadata.sha256.toLowerCase()) {
        _logTelemetry('checksum_failed', {
          'versionCode': metadata.versionCode,
          'expected': metadata.sha256,
          'actual': calculatedSha,
        });

        // Immediately delete corrupted file per security specification
        if (await targetFile.exists()) {
          await targetFile.delete();
        }

        // Increment failure counter
        final prev = _failedAttempts[metadata.versionCode] ?? 0;
        _failedAttempts[metadata.versionCode] = prev + 1;

        throw Exception(
          'Security verification failed: SHA-256 checksum mismatch. File removed to protect your device.',
        );
      }

      // Verification passed!
      _logTelemetry('checksum_verified', {
        'versionCode': metadata.versionCode,
        'sha256': calculatedSha,
      });
      _failedAttempts.remove(metadata.versionCode);
      return targetFile;
    } catch (e) {
      if (sink != null) {
        await sink.close();
      }
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      _activeClient?.close(force: true);
      _activeClient = null;
      _isDownloading = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHA-256 STREAMING COMPUTATION
  // ─────────────────────────────────────────────────────────────────────────
  Future<String> _computeSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INSTALLATION TRIGGER
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> triggerInstallation(File apkFile) async {
    _logTelemetry('installation_started', {'path': apkFile.path});

    final canInstall = await OtaInstallerPlatform.canRequestPackageInstalls();
    if (!canInstall) {
      _logTelemetry('request_install_permission_needed', {});
      final opened = await OtaInstallerPlatform.openInstallPermissionSettings();
      return opened;
    }

    final success = await OtaInstallerPlatform.installApk(apkFile.path);
    if (!success) {
      _logTelemetry('installation_failed', {'path': apkFile.path});
    }
    return success;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // USER ACTIONS
  // ─────────────────────────────────────────────────────────────────────────
  void dismissFlexibleUpdate(int versionCode) {
    _dismissedVersionCodes.add(versionCode);
    _logTelemetry('flexible_update_dismissed', {'versionCode': versionCode});
  }

  void cancelDownload() {
    if (_activeClient != null) {
      _activeClient?.close(force: true);
      _activeClient = null;
      _isDownloading = false;
      _logTelemetry('download_cancelled', {});
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// REACTIVE STATE NOTIFIER
// ─────────────────────────────────────────────────────────────────────────
class OtaStateNotifier extends StateNotifier<OtaEngineState> {
  final OtaUpdateService _service;

  OtaStateNotifier(this._service) : super(const OtaEngineState()) {
    _initAppVersion();
  }

  Future<void> _initAppVersion() async {
    final v = await OtaInstallerPlatform.getAppVersion();
    state = state.copyWith(
      currentVersionCode: v['versionCode'] as int? ?? 0,
      currentVersionName: v['versionName'] as String? ?? '',
    );
  }

  Future<OtaCheckResult> check({bool isManual = false, String channel = 'stable'}) async {
    state = state.copyWith(status: OtaStatus.checking, errorMessage: null);
    final result = await _service.checkForUpdates(isManual: isManual, channel: channel);

    if (result.hasUpdate && result.metadata != null) {
      state = state.copyWith(
        status: OtaStatus.updateAvailable,
        metadata: result.metadata,
        isMandatory: result.isMandatory,
        currentVersionCode: result.currentVersionCode,
        currentVersionName: result.currentVersionName,
      );
    } else if (result.errorMessage != null) {
      state = state.copyWith(
        status: OtaStatus.error,
        errorMessage: result.errorMessage,
        currentVersionCode: result.currentVersionCode,
        currentVersionName: result.currentVersionName,
      );
    } else {
      state = state.copyWith(
        status: OtaStatus.upToDate,
        currentVersionCode: result.currentVersionCode,
        currentVersionName: result.currentVersionName,
      );
    }
    return result;
  }

  Future<void> startDownload() async {
    final metadata = state.metadata;
    if (metadata == null) return;

    state = state.copyWith(
      status: OtaStatus.downloading,
      errorMessage: null,
      progress: const OtaDownloadProgress(bytesDownloaded: 0, totalBytes: 0, fraction: 0.0),
    );

    try {
      final file = await _service.downloadAndVerify(
        metadata: metadata,
        onProgress: (prog) {
          if (mounted) {
            state = state.copyWith(progress: prog);
          }
        },
      );

      state = state.copyWith(
        status: OtaStatus.readyToInstall,
        localApkPath: file.path,
      );
    } catch (e) {
      state = state.copyWith(
        status: OtaStatus.error,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> install() async {
    final path = state.localApkPath;
    if (path == null) return;
    state = state.copyWith(status: OtaStatus.installing);
    final success = await _service.triggerInstallation(File(path));
    if (!success) {
      state = state.copyWith(
        status: OtaStatus.readyToInstall,
        errorMessage: 'Package installer was closed or permission is required.',
      );
    }
  }

  void dismiss() {
    if (state.metadata != null) {
      _service.dismissFlexibleUpdate(state.metadata!.versionCode);
    }
    state = state.copyWith(status: OtaStatus.idle);
  }

  void cancel() {
    _service.cancelDownload();
    state = state.copyWith(status: OtaStatus.idle);
  }
}
