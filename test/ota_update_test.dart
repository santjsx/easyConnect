import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easyconnect/features/ota_update/models/ota_metadata.dart';

void main() {
  group('OTA Metadata JSON Parsing', () {
    test('Correctly parses standardized release-metadata.json schema', () {
      final json = {
        'versionCode': 46,
        'versionName': '1.5.46',
        'apkUrl': 'https://github.com/santjsx/easyConnect/releases/download/v1.5.46/app-release.apk',
        'sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'isMandatory': true,
        'minSupportedVersionCode': 40,
        'releaseNotes': 'Critical security patch and performance optimizations',
        'fileSizeBytes': 25165824,
        'publishedAt': '2026-09-19T12:00:00Z',
      };

      final metadata = OtaMetadata.fromJson(json);

      expect(metadata.versionCode, 46);
      expect(metadata.versionName, '1.5.46');
      expect(metadata.sha256, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(metadata.isMandatory, isTrue);
      expect(metadata.minSupportedVersionCode, 40);
      expect(metadata.releaseNotes, 'Critical security patch and performance optimizations');
      expect(metadata.fileSizeBytes, 25165824);
      expect(metadata.formattedSize, '24.0 MB');
    });

    test('Gracefully handles string version codes and missing optional fields', () {
      final json = {
        'versionCode': '47',
        'versionName': '1.5.47',
        'apkUrl': 'https://github.com/santjsx/easyConnect',
        'sha256': 'ABCDEF1234567890',
        'minSupportedVersionCode': '42',
      };

      final metadata = OtaMetadata.fromJson(json);

      expect(metadata.versionCode, 47);
      expect(metadata.versionName, '1.5.47');
      expect(metadata.sha256, 'abcdef1234567890'); // Case normalized to lowercase
      expect(metadata.isMandatory, isFalse);
      expect(metadata.minSupportedVersionCode, 42);
    });
  });

  group('Semantic Version & Mandatory Update Evaluation', () {
    test('isMandatoryFor returns true when isMandatory flag is true', () {
      const metadata = OtaMetadata(
        versionCode: 50,
        versionName: '1.6.0',
        apkUrl: 'https://example.com/apk',
        sha256: 'hash',
        isMandatory: true,
        minSupportedVersionCode: 0,
      );

      expect(metadata.isMandatoryFor(45), isTrue);
      expect(metadata.isMandatoryFor(49), isTrue);
    });

    test('isMandatoryFor returns true when current version is below minSupportedVersionCode', () {
      const metadata = OtaMetadata(
        versionCode: 50,
        versionName: '1.6.0',
        apkUrl: 'https://example.com/apk',
        sha256: 'hash',
        isMandatory: false,
        minSupportedVersionCode: 45,
      );

      expect(metadata.isMandatoryFor(40), isTrue); // 40 < 45 -> forced mandatory
      expect(metadata.isMandatoryFor(44), isTrue); // 44 < 45 -> forced mandatory
      expect(metadata.isMandatoryFor(45), isFalse); // 45 >= 45 -> flexible
      expect(metadata.isMandatoryFor(48), isFalse); // 48 >= 45 -> flexible
    });

    test('OtaCheckResult detects downgrade attempts', () {
      final result = OtaCheckResult.downgradeIgnored(
        currentVersionCode: 50,
        currentVersionName: '1.6.0',
      );

      expect(result.hasUpdate, isFalse);
      expect(result.isDowngrade, isTrue);
    });
  });

  group('Cryptographic Checksum Verification', () {
    test('Validates SHA-256 calculation against known bytes', () async {
      final testData = utf8.encode('EasyConnect OTA Release Checksum Test');
      final expectedSha256 = sha256.convert(testData).toString();

      // Write test file to temp
      final tempDir = await Directory.systemTemp.createTemp('ota_test_');
      final tempFile = File('${tempDir.path}/test_asset.bin');
      await tempFile.writeAsBytes(testData);

      final digest = await sha256.bind(tempFile.openRead()).first;
      final calculated = digest.toString();

      expect(calculated, expectedSha256);

      // Clean up
      await tempDir.delete(recursive: true);
    });
  });
}
