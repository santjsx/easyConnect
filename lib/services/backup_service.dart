import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/services/tts_service.dart';

class BackupService {
  final ContactRepository _contactRepo;
  final TTSService _ttsService;

  BackupService(this._contactRepo, this._ttsService);

  List<int> _safeGetArchiveFileContent(ArchiveFile file) {
    final content = file.content;
    if (content is List<int>) {
      return content;
    }
    if (content != null) {
      try {
        return (content as dynamic).bytes as List<int>;
      } catch (_) {}
      try {
        return (content as dynamic).toUint8List() as List<int>;
      } catch (_) {}
    }
    return file.content as List<int>;
  }

  /// Packages contacts, settings and photos into a shareable ZIP archive
  Future<bool> createAndShareBackup() async {
    try {
      final contacts = await _contactRepo.getAllContacts();

      final Box<AppSettings> settingsBox = Hive.isBoxOpen('settings')
          ? Hive.box<AppSettings>('settings')
          : await Hive.openBox<AppSettings>('settings');

      final settings = settingsBox.isNotEmpty
          ? settingsBox.values.first
          : AppSettings(adminPin: '1234');

      final archive = Archive();

      // Create contact list JSON with relative paths
      final List<Map<String, dynamic>> contactsJson = [];
      for (final c in contacts) {
        String? relativePhoto;
        if (c.photoPath != null && c.photoPath!.isNotEmpty) {
          try {
            final file = File(c.photoPath!);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              final filename = file.uri.pathSegments.last;
              relativePhoto = 'photos/$filename';
              archive.addFile(ArchiveFile('photos/$filename', bytes.length, bytes));
            }
          } catch (e) {
            debugPrint('Failed to add photo for contact ${c.name}: $e');
          }
        }

        String? relativeVoice;
        if (c.voiceLabelPath != null && c.voiceLabelPath!.isNotEmpty) {
          try {
            final file = File(c.voiceLabelPath!);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              final filename = file.uri.pathSegments.last;
              relativeVoice = 'voice_labels/$filename';
              archive.addFile(ArchiveFile('voice_labels/$filename', bytes.length, bytes));
            }
          } catch (e) {
            debugPrint('Failed to add voice label for contact ${c.name}: $e');
          }
        }

        contactsJson.add({
          'id': c.id,
          'name': c.name,
          'phoneNumber': c.phoneNumber,
          'whatsappNumber': c.whatsappNumber,
          'photoPath': relativePhoto,
          'colorTheme': c.colorTheme,
          'preferredAction': c.preferredAction,
          'positionIndex': c.positionIndex,
          'voiceLabelPath': relativeVoice,
        });
      }

      final Map<String, dynamic> backupData = {
        'version': 1,
        'exported_at': DateTime.now().toIso8601String(),
        'settings': {
          'language': settings.language,
          'voiceEnabled': settings.voiceEnabled,
          'sosContactId': settings.sosContactId,
          'sosLocationShare': settings.sosLocationShare,
          'adminPin': settings.adminPin,
          'fingerprintEnabled': settings.fingerprintEnabled,
        },
        'contacts': contactsJson,
      };

      // Add backup_data.json to the ZIP archive
      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      final jsonBytes = utf8.encode(jsonString);
      archive.addFile(ArchiveFile('backup_data.json', jsonBytes.length, jsonBytes));

      // Encode archive to zip bytes
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        throw Exception("Failed to encode ZIP archive");
      }

      // Write to temp directory for robust sharing permissions (compatible with share_plus FileProvider)
      final tempDir = await getTemporaryDirectory();

      // Clean up old backup ZIP files to avoid storage clutter
      try {
        final List<FileSystemEntity> entities = tempDir.listSync();
        for (final entity in entities) {
          if (entity is File &&
              entity.path.endsWith('.zip') &&
              entity.path.contains('easyconnect_backup_')) {
            await entity.delete();
          }
        }
      } catch (e) {
        debugPrint('Error cleaning up old backups: $e');
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final backupFilename = 'easyconnect_backup_$timestamp.zip';
      final backupFile = File('${tempDir.path}/$backupFilename');
      await backupFile.writeAsBytes(zipBytes);

      // Share backup file with explicit name and mimeType
      await Share.shareXFiles(
        [
          XFile(
            backupFile.path,
            name: backupFilename,
            mimeType: 'application/zip',
          )
        ],
        text: 'EasyConnect Secure App Backup (ZIP)',
      );
      return true;
    } catch (e) {
      debugPrint('Error in BackupService.createAndShareBackup: $e');
      await _ttsService.speak("Backup failed. Please try again.");
      return false;
    }
  }

  /// Opens a file picker, loads a ZIP archive, and restores contacts, settings and photos
  Future<bool> restoreFromBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result == null || result.files.single.path == null) {
        return false;
      }

      final bytes = await File(result.files.single.path!).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 1. Locate backup_data.json
      ArchiveFile? metadataFile;
      for (final file in archive) {
        if (file.name == 'backup_data.json') {
          metadataFile = file;
          break;
        }
      }

      if (metadataFile == null) {
        throw Exception("Invalid backup archive: backup_data.json not found.");
      }

      final jsonString = utf8.decode(_safeGetArchiveFileContent(metadataFile));
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      // 2. Clear current contacts list
      await _contactRepo.clearAllContacts();

      // 3. Recreate required local media directories
      final appDocDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${appDocDir.path}/photos');
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }
      final voiceLabelsDir = Directory('${appDocDir.path}/voice_labels');
      if (!await voiceLabelsDir.exists()) {
        await voiceLabelsDir.create(recursive: true);
      }

      // 4. Extract photos and voice files
      final Map<String, String> extractedPaths = {};
      for (final file in archive) {
        if (!file.isFile) continue;

        try {
          final fileContent = _safeGetArchiveFileContent(file);
          if (file.name.startsWith('photos/')) {
            final filename = file.name.split('/').last;
            final localFile = File('${photosDir.path}/$filename');
            await localFile.writeAsBytes(fileContent);
            extractedPaths[file.name] = localFile.path;
          } else if (file.name.startsWith('voice_labels/')) {
            final filename = file.name.split('/').last;
            final localFile = File('${voiceLabelsDir.path}/$filename');
            await localFile.writeAsBytes(fileContent);
            extractedPaths[file.name] = localFile.path;
          }
        } catch (e) {
          debugPrint('Failed to extract file ${file.name} from backup: $e');
        }
    }

      // 5. Restore contacts
      final contactsList = data['contacts'] as List<dynamic>;
      for (final cJson in contactsList) {
        final relativePhoto = cJson['photoPath'] as String?;
        final relativeVoice = cJson['voiceLabelPath'] as String?;

        final localPhotoPath = (relativePhoto != null && extractedPaths.containsKey(relativePhoto))
            ? extractedPaths[relativePhoto]
            : null;
        final localVoicePath = (relativeVoice != null && extractedPaths.containsKey(relativeVoice))
            ? extractedPaths[relativeVoice]
            : null;

        final contact = Contact(
          id: cJson['id'] as String,
          name: cJson['name'] as String,
          phoneNumber: cJson['phoneNumber'] as String,
          whatsappNumber: cJson['whatsappNumber'] as String?,
          photoPath: localPhotoPath,
          colorTheme: cJson['colorTheme'] as String? ?? '#4CAF50',
          preferredAction: cJson['preferredAction'] as String? ?? 'call',
          positionIndex: cJson['positionIndex'] as int? ?? 0,
          voiceLabelPath: localVoicePath,
        );
        await _contactRepo.addContact(contact);
      }

      // 6. Restore Settings
      final settingsJson = data['settings'] as Map<String, dynamic>;
      final Box<AppSettings> settingsBox = Hive.isBoxOpen('settings')
          ? Hive.box<AppSettings>('settings')
          : await Hive.openBox<AppSettings>('settings');

      final restoredSettings = AppSettings(
        language: settingsJson['language'] as String? ?? 'en',
        voiceEnabled: settingsJson['voiceEnabled'] as bool? ?? true,
        sosContactId: settingsJson['sosContactId'] as String?,
        sosLocationShare: settingsJson['sosLocationShare'] as bool? ?? true,
        adminPin: settingsJson['adminPin'] as String? ?? '1234',
        fingerprintEnabled: settingsJson['fingerprintEnabled'] as bool? ?? false,
      );

      await settingsBox.clear();
      await settingsBox.add(restoredSettings);

      await _ttsService.speak("Data restored successfully");
      return true;
    } catch (e) {
      debugPrint('Error in BackupService.restoreFromBackup: $e');
      await _ttsService.speak("Restore failed. Please check the backup file.");
      return false;
    }
  }
}

final backupServiceProvider = Provider<BackupService>((ref) {
  final contactRepo = ref.watch(contactRepositoryProvider);
  final ttsService = ref.watch(ttsServiceProvider);
  return BackupService(contactRepo, ttsService);
});
