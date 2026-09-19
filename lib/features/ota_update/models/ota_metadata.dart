/// Represents the standardized release-metadata.json schema from GitHub Releases.
class OtaMetadata {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String sha256;
  final bool isMandatory;
  final int minSupportedVersionCode;
  final String releaseNotes;
  final int fileSizeBytes;
  final DateTime? publishedAt;

  const OtaMetadata({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sha256,
    this.isMandatory = false,
    this.minSupportedVersionCode = 0,
    this.releaseNotes = '',
    this.fileSizeBytes = 0,
    this.publishedAt,
  });

  factory OtaMetadata.fromJson(Map<String, dynamic> json) {
    return OtaMetadata(
      versionCode: json['versionCode'] is int
          ? json['versionCode'] as int
          : int.tryParse(json['versionCode']?.toString() ?? '0') ?? 0,
      versionName: json['versionName']?.toString() ?? '',
      apkUrl: json['apkUrl']?.toString() ?? '',
      sha256: (json['sha256']?.toString() ?? '').trim().toLowerCase(),
      isMandatory: json['isMandatory'] == true,
      minSupportedVersionCode: json['minSupportedVersionCode'] is int
          ? json['minSupportedVersionCode'] as int
          : int.tryParse(json['minSupportedVersionCode']?.toString() ?? '0') ?? 0,
      releaseNotes: json['releaseNotes']?.toString() ?? '',
      fileSizeBytes: json['fileSizeBytes'] is int
          ? json['fileSizeBytes'] as int
          : int.tryParse(json['fileSizeBytes']?.toString() ?? '0') ?? 0,
      publishedAt: json['publishedAt'] != null
          ? DateTime.tryParse(json['publishedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'versionCode': versionCode,
      'versionName': versionName,
      'apkUrl': apkUrl,
      'sha256': sha256,
      'isMandatory': isMandatory,
      'minSupportedVersionCode': minSupportedVersionCode,
      'releaseNotes': releaseNotes,
      'fileSizeBytes': fileSizeBytes,
      if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
    };
  }

  /// Whether this update is mandatory for a given running version code
  bool isMandatoryFor(int currentVersionCode) {
    return isMandatory || currentVersionCode < minSupportedVersionCode;
  }

  /// Formatted size in megabytes
  String get formattedSize {
    if (fileSizeBytes <= 0) return '';
    final mb = fileSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Result of evaluating remote metadata against the local app version
class OtaCheckResult {
  final bool hasUpdate;
  final bool isMandatory;
  final bool isDowngrade;
  final OtaMetadata? metadata;
  final int currentVersionCode;
  final String currentVersionName;
  final String? errorMessage;

  const OtaCheckResult({
    required this.hasUpdate,
    required this.isMandatory,
    required this.isDowngrade,
    this.metadata,
    required this.currentVersionCode,
    required this.currentVersionName,
    this.errorMessage,
  });

  factory OtaCheckResult.noUpdate({
    required int currentVersionCode,
    required String currentVersionName,
  }) {
    return OtaCheckResult(
      hasUpdate: false,
      isMandatory: false,
      isDowngrade: false,
      currentVersionCode: currentVersionCode,
      currentVersionName: currentVersionName,
    );
  }

  factory OtaCheckResult.downgradeIgnored({
    required int currentVersionCode,
    required String currentVersionName,
  }) {
    return OtaCheckResult(
      hasUpdate: false,
      isMandatory: false,
      isDowngrade: true,
      currentVersionCode: currentVersionCode,
      currentVersionName: currentVersionName,
    );
  }

  factory OtaCheckResult.updateAvailable({
    required OtaMetadata metadata,
    required int currentVersionCode,
    required String currentVersionName,
  }) {
    return OtaCheckResult(
      hasUpdate: true,
      isMandatory: metadata.isMandatoryFor(currentVersionCode),
      isDowngrade: false,
      metadata: metadata,
      currentVersionCode: currentVersionCode,
      currentVersionName: currentVersionName,
    );
  }

  factory OtaCheckResult.error({
    required String message,
    required int currentVersionCode,
    required String currentVersionName,
  }) {
    return OtaCheckResult(
      hasUpdate: false,
      isMandatory: false,
      isDowngrade: false,
      currentVersionCode: currentVersionCode,
      currentVersionName: currentVersionName,
      errorMessage: message,
    );
  }
}

/// Download progress state
class OtaDownloadProgress {
  final int bytesDownloaded;
  final int totalBytes;
  final double fraction;

  const OtaDownloadProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.fraction,
  });

  int get percentage => (fraction * 100).clamp(0, 100).toInt();

  String get formattedProgress {
    final downloadedMb = (bytesDownloaded / (1024 * 1024)).toStringAsFixed(1);
    if (totalBytes > 0) {
      final totalMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
      return '$downloadedMb / $totalMb MB ($percentage%)';
    }
    return '$downloadedMb MB';
  }
}

/// Overall state of the OTA engine
enum OtaStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  verifying,
  readyToInstall,
  installing,
  error,
}

class OtaEngineState {
  final OtaStatus status;
  final OtaMetadata? metadata;
  final OtaDownloadProgress? progress;
  final String? localApkPath;
  final String? errorMessage;
  final bool isMandatory;
  final int currentVersionCode;
  final String currentVersionName;

  const OtaEngineState({
    this.status = OtaStatus.idle,
    this.metadata,
    this.progress,
    this.localApkPath,
    this.errorMessage,
    this.isMandatory = false,
    this.currentVersionCode = 0,
    this.currentVersionName = '',
  });

  OtaEngineState copyWith({
    OtaStatus? status,
    OtaMetadata? metadata,
    OtaDownloadProgress? progress,
    String? localApkPath,
    String? errorMessage,
    bool? isMandatory,
    int? currentVersionCode,
    String? currentVersionName,
  }) {
    return OtaEngineState(
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
      progress: progress ?? this.progress,
      localApkPath: localApkPath ?? this.localApkPath,
      errorMessage: errorMessage ?? this.errorMessage,
      isMandatory: isMandatory ?? this.isMandatory,
      currentVersionCode: currentVersionCode ?? this.currentVersionCode,
      currentVersionName: currentVersionName ?? this.currentVersionName,
    );
  }
}
