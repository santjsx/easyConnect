import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:hive/hive.dart';
import 'package:geolocator/geolocator.dart';
import 'package:easyconnect/main.dart';
import 'package:easyconnect/screens/find_phone_alarm_screen.dart';
import 'package:easyconnect/services/system_status_service.dart';

class FirebaseSyncService {
  final Ref _ref;
  final HttpClient _httpClient = HttpClient();
  StreamSubscription? _firestoreSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _commandSubscription;
  Timer? _telemetryTimer;
  bool _isFindPhoneShowing = false;
  bool _isSyncRunning = false;
  bool _isUploadingAll = false;
  String? _currentFamilyCode;

  // Sequential execution lock queue to prevent concurrent sync operations
  Future<void>? _activeSyncFuture;

  FirebaseSyncService(this._ref) {
    // Listen to settings to automatically start/stop sync
    _ref.listen(settingsProvider, (previous, next) {
      next.whenData((settings) {
        if (settings.activeIsSyncEnabled && settings.activeFamilySyncCode.isNotEmpty) {
          startSync(settings.activeFamilySyncCode);
        } else {
          stopSync();
        }
      });
    });
  }

  bool get isFirebaseAvailable {
    try {
      Firebase.app();
      return true;
    } catch (_) {
      return false;
    }
  }

  void startSync(String familyCode) {
    if (!isFirebaseAvailable) {
      debugPrint('Firebase Sync: Firebase is not initialized. Drop google-services.json and restart the app.');
      return;
    }
    if (_isSyncRunning) {
      if (_currentFamilyCode == familyCode) return;
      stopSync();
    }

    debugPrint('Firebase Sync: Starting sync for family code: $familyCode');
    _isSyncRunning = true;
    _currentFamilyCode = familyCode;

    _firestoreSubscription = FirebaseFirestore.instance
        .collection('families')
        .doc(familyCode)
        .collection('contacts')
        .snapshots()
        .listen((snapshot) {
      Future<void> syncTask() => _syncFromFirestore(snapshot.docs, familyCode);
      
      // Chain snapshot handling sequentially
      if (_activeSyncFuture == null) {
        _activeSyncFuture = syncTask();
      } else {
        _activeSyncFuture = _activeSyncFuture!.whenComplete(syncTask);
      }
    }, onError: (e) {
      debugPrint('Firebase Sync error: $e');
    });

    // Initial telemetry upload and periodic timer (every 2 minutes)
    _uploadTelemetry(familyCode);
    _telemetryTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _uploadTelemetry(familyCode);
    });

    // Listen to local status telemetry changes
    _statusSubscription = _ref.read(systemStatusProvider.notifier).stream.listen((status) {
      if (_isSyncRunning && _currentFamilyCode != null) {
        _uploadTelemetry(_currentFamilyCode!);
      }
    });

    // Listen to caregiver command events (e.g. Find My Phone)
    _commandSubscription = FirebaseFirestore.instance
        .collection('families')
        .doc(familyCode)
        .collection('commands')
        .doc('find_phone')
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;
      final trigger = data['trigger'] as bool? ?? false;
      if (trigger) {
        final timestampVal = data['timestamp'];
        DateTime? commandTime;
        if (timestampVal is Timestamp) {
          commandTime = timestampVal.toDate();
        } else if (timestampVal is String) {
          commandTime = DateTime.tryParse(timestampVal);
        }
        
        if (commandTime != null) {
          final diff = DateTime.now().difference(commandTime).inMinutes;
          if (diff.abs() <= 5) {
            _triggerFindPhoneAlarm(familyCode);
          }
        }
      }
    }, onError: (e) {
      debugPrint('Firebase command subscription error: $e');
    });
  }

  void stopSync() {
    if (_firestoreSubscription != null) {
      debugPrint('Firebase Sync: Stopping sync.');
      _firestoreSubscription!.cancel();
      _firestoreSubscription = null;
    }
    if (_statusSubscription != null) {
      _statusSubscription!.cancel();
      _statusSubscription = null;
    }
    if (_commandSubscription != null) {
      _commandSubscription!.cancel();
      _commandSubscription = null;
    }
    if (_telemetryTimer != null) {
      _telemetryTimer!.cancel();
      _telemetryTimer = null;
    }
    _currentFamilyCode = null;
    _isSyncRunning = false;
    _activeSyncFuture = null;
  }

  Future<void> _uploadTelemetry(String familyCode) async {
    try {
      final status = _ref.read(systemStatusProvider);
      
      // Get current GPS location link
      String? gpsLocation;
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 8),
          );
          gpsLocation = "https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}";
        }
      } catch (e) {
        debugPrint("Error getting geolocator position for telemetry sync: $e");
      }

      await FirebaseFirestore.instance
          .collection('families')
          .doc(familyCode)
          .collection('telemetry')
          .doc('device')
          .set({
        'batteryLevel': status.batteryLevel,
        'isCharging': status.isCharging,
        'signalStrength': status.signalStrength,
        'simState': status.simState,
        'gpsLocation': gpsLocation ?? '',
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('Firebase Sync: Synced device telemetry successfully.');
    } catch (e) {
      debugPrint('Error uploading device telemetry: $e');
    }
  }

  void _triggerFindPhoneAlarm(String familyCode) {
    if (_isFindPhoneShowing) return;
    _isFindPhoneShowing = true;

    final context = navigatorKey.currentState?.overlay?.context;
    if (context != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => FindPhoneAlarmScreen(familyCode: familyCode),
          fullscreenDialog: true,
        ),
      ).then((_) {
        _isFindPhoneShowing = false;
      });
    } else {
      _isFindPhoneShowing = false;
    }
  }

  static List<int> _decodeBase64Helper(String base64Str) => base64Decode(base64Str);

  Future<void> _syncFromFirestore(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String familyCode) async {
    if (_isUploadingAll) {
      debugPrint('Firebase Sync: Skipping sync from Firestore because upload is in progress.');
      return;
    }
    try {
      final repo = _ref.read(contactRepositoryProvider);
      final localContacts = await repo.getAllContacts();
      final localContactsMap = {for (var c in localContacts) c.id: c};

      final List<String> remoteIds = [];

      for (final doc in docs) {
        final data = doc.data();
        final id = data['id'] as String;
        final name = data['name'] as String;
        final phoneNumber = data['phoneNumber'] as String;
        final whatsappNumber = data['whatsappNumber'] as String?;
        final colorTheme = data['colorTheme'] as String? ?? '#4CAF50';
        final preferredAction = data['preferredAction'] as String? ?? 'call';
        final positionIndex = data['positionIndex'] as int? ?? 0;
        final photoUrl = data['photoUrl'] as String?;
        final voiceLabelUrl = data['voiceLabelUrl'] as String?;

        remoteIds.add(id);

        final localContact = localContactsMap[id];
        bool needsUpdate = false;
        String? finalPhotoPath = localContact?.photoPath;
        String? finalVoicePath = localContact?.voiceLabelPath;

        // 1. Photo download
        if (photoUrl != null && photoUrl.isNotEmpty) {
          final appDocDir = await getApplicationDocumentsDirectory();
          final String expectedPath;
          
          if (photoUrl.startsWith('data:')) {
            expectedPath = '${appDocDir.path}/photos/$id.jpg';
            if (!await File(expectedPath).exists()) {
              debugPrint('Firebase Sync: Saving base64 photo for $name...');
              final base64String = photoUrl.split(',').last;
              
              // Perform decode on background isolate
              final bytes = await compute(_decodeBase64Helper, base64String);
              
              // Atomic file write using temporary file
              final tempFile = File('$expectedPath.tmp');
              if (!await tempFile.parent.exists()) {
                await tempFile.parent.create(recursive: true);
              }
              await tempFile.writeAsBytes(bytes);
              final finalFile = await tempFile.rename(expectedPath);
              
              finalPhotoPath = finalFile.path;
              needsUpdate = true;
            } else if (localContact?.photoPath != expectedPath) {
              finalPhotoPath = expectedPath;
              needsUpdate = true;
            }
          } else {
            final uri = Uri.parse(photoUrl);
            final pathSegments = uri.pathSegments;
            final filename = pathSegments.isNotEmpty ? pathSegments.last : '$id.jpg';
            final safeFilename = filename.replaceAll(RegExp(r'[^\w\.\-]'), '_');
            expectedPath = '${appDocDir.path}/photos/$safeFilename';

            if (!await File(expectedPath).exists()) {
              debugPrint('Firebase Sync: Downloading photo for $name...');
              final downloadedPath = await _downloadFile(photoUrl, 'photos', safeFilename);
              if (downloadedPath != null) {
                finalPhotoPath = downloadedPath;
                needsUpdate = true;
              }
            } else if (localContact?.photoPath != expectedPath) {
              finalPhotoPath = expectedPath;
              needsUpdate = true;
            }
          }
        } else {
          if (localContact?.photoPath != null) {
            try {
              final file = File(localContact!.photoPath!);
              if (await file.exists()) {
                await file.delete();
              }
            } catch (e) {
              debugPrint('Error deleting local photo file: $e');
            }
            finalPhotoPath = null;
            needsUpdate = true;
          }
        }

        // 2. Voice label download
        if (voiceLabelUrl != null && voiceLabelUrl.isNotEmpty) {
          final appDocDir = await getApplicationDocumentsDirectory();
          final String expectedPath;

          if (voiceLabelUrl.startsWith('data:')) {
            expectedPath = '${appDocDir.path}/voice_labels/$id.m4a';
            if (!await File(expectedPath).exists()) {
              debugPrint('Firebase Sync: Saving base64 voice label for $name...');
              final base64String = voiceLabelUrl.split(',').last;
              
              // Perform decode on background isolate
              final bytes = await compute(_decodeBase64Helper, base64String);
              
              // Atomic file write using temporary file
              final tempFile = File('$expectedPath.tmp');
              if (!await tempFile.parent.exists()) {
                await tempFile.parent.create(recursive: true);
              }
              await tempFile.writeAsBytes(bytes);
              final finalFile = await tempFile.rename(expectedPath);
              
              finalVoicePath = finalFile.path;
              needsUpdate = true;
            } else if (localContact?.voiceLabelPath != expectedPath) {
              finalVoicePath = expectedPath;
              needsUpdate = true;
            }
          } else {
            final uri = Uri.parse(voiceLabelUrl);
            final pathSegments = uri.pathSegments;
            final filename = pathSegments.isNotEmpty ? pathSegments.last : '$id.m4a';
            final safeFilename = filename.replaceAll(RegExp(r'[^\w\.\-]'), '_');
            expectedPath = '${appDocDir.path}/voice_labels/$safeFilename';

            if (!await File(expectedPath).exists()) {
              debugPrint('Firebase Sync: Downloading voice label for $name...');
              final downloadedPath = await _downloadFile(voiceLabelUrl, 'voice_labels', safeFilename);
              if (downloadedPath != null) {
                finalVoicePath = downloadedPath;
                needsUpdate = true;
              }
            } else if (localContact?.voiceLabelPath != expectedPath) {
              finalVoicePath = expectedPath;
              needsUpdate = true;
            }
          }
        } else {
          if (localContact?.voiceLabelPath != null) {
            try {
              final file = File(localContact!.voiceLabelPath!);
              if (await file.exists()) {
                await file.delete();
              }
            } catch (e) {
              debugPrint('Error deleting local voice label file: $e');
            }
            finalVoicePath = null;
            needsUpdate = true;
          }
        }

        // 3. Field differences
        if (localContact == null ||
            localContact.name != name ||
            localContact.phoneNumber != phoneNumber ||
            localContact.whatsappNumber != whatsappNumber ||
            localContact.colorTheme != colorTheme ||
            localContact.preferredAction != preferredAction ||
            localContact.positionIndex != positionIndex ||
            needsUpdate) {
          
          final updatedContact = Contact(
            id: id,
            name: name,
            phoneNumber: phoneNumber,
            whatsappNumber: whatsappNumber,
            photoPath: finalPhotoPath,
            colorTheme: colorTheme,
            preferredAction: preferredAction,
            positionIndex: positionIndex,
            voiceLabelPath: finalVoicePath,
          );

          debugPrint('Firebase Sync: Saving contact $name to Hive...');
          if (localContact == null) {
            await repo.addContact(updatedContact, isFromSync: true);
          } else {
            await repo.updateContact(updatedContact, isFromSync: true);
          }
        }
      }

      // 4. Delete local contacts not found in Firestore
      for (final localId in localContactsMap.keys) {
        if (!remoteIds.contains(localId)) {
          debugPrint('Firebase Sync: Deleting contact ID $localId from Hive (not found in Firestore)...');
          await repo.deleteContact(localId, isFromSync: true);
        }
      }
    } catch (e) {
      debugPrint('Error during Firestore sync process: $e');
    }
  }

  Future<String?> _downloadFile(String url, String folderName, String fileName) async {
    try {
      final request = await _httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == 200) {
        final appDocDir = await getApplicationDocumentsDirectory();
        final dir = Directory('${appDocDir.path}/$folderName');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final file = File('${dir.path}/$fileName');
        await response.pipe(file.openWrite());
        return file.path;
      }
    } catch (e) {
      debugPrint('Error downloading file from sync: $e');
    }
    return null;
  }

  // Upload actions called from ContactRepository
  Future<void> uploadContact(Contact contact) async {
    if (!isFirebaseAvailable) return;
    try {
      final settingsBox = Hive.box<AppSettings>('settings');
      if (settingsBox.isEmpty) return;
      final settings = settingsBox.values.first;
      if (!settings.activeIsSyncEnabled || settings.activeFamilySyncCode.isEmpty) return;

      await _uploadContactWithCode(contact, settings.activeFamilySyncCode);
    } catch (e) {
      debugPrint('Error uploading contact to Firestore (silent): $e');
    }
  }

  static String _encodeBase64Helper(List<int> bytes) => base64Encode(bytes);

  Future<String?> _convertFileToBase64(String localPath, String mimeType) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      // Offload base64 encoding to background worker isolate to keep UI thread at 60/120fps
      final base64String = await compute(_encodeBase64Helper, bytes);
      return 'data:$mimeType;base64,$base64String';
    } catch (e) {
      debugPrint('Error converting file to base64: $e');
      rethrow;
    }
  }

  Future<void> _uploadContactWithCode(Contact contact, String familyCode) async {
    try {
      String? photoUrl;
      if (contact.photoPath != null && contact.photoPath!.isNotEmpty) {
        if (contact.photoPath!.startsWith('data:')) {
          photoUrl = contact.photoPath;
        } else {
          photoUrl = await _convertFileToBase64(contact.photoPath!, 'image/jpeg');
        }
      }

      String? voiceLabelUrl;
      if (contact.voiceLabelPath != null && contact.voiceLabelPath!.isNotEmpty) {
        if (contact.voiceLabelPath!.startsWith('data:')) {
          voiceLabelUrl = contact.voiceLabelPath;
        } else {
          voiceLabelUrl = await _convertFileToBase64(contact.voiceLabelPath!, 'audio/m4a');
        }
      }

      await FirebaseFirestore.instance
          .collection('families')
          .doc(familyCode)
          .collection('contacts')
          .doc(contact.id)
          .set({
        'id': contact.id,
        'name': contact.name,
        'phoneNumber': contact.phoneNumber,
        'whatsappNumber': contact.whatsappNumber,
        'colorTheme': contact.colorTheme,
        'preferredAction': contact.preferredAction,
        'positionIndex': contact.positionIndex,
        'photoUrl': photoUrl,
        'voiceLabelUrl': voiceLabelUrl,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // Enable merge to prevent overwriting other fields (e.g. concurrent edits by Admin Dashboard)
    } catch (e) {
      debugPrint('Error uploading contact to Firestore: $e');
      rethrow;
    }
  }

  Future<void> deleteContact(String id) async {
    if (!isFirebaseAvailable) return;
    try {
      final settingsBox = Hive.box<AppSettings>('settings');
      if (settingsBox.isEmpty) return;
      final settings = settingsBox.values.first;
      if (!settings.activeIsSyncEnabled || settings.activeFamilySyncCode.isEmpty) return;

      final familyCode = settings.activeFamilySyncCode;
      debugPrint('Firebase Sync: Deleting contact ID $id from Firestore...');

      await FirebaseFirestore.instance
          .collection('families')
          .doc(familyCode)
          .collection('contacts')
          .doc(id)
          .delete();

      try {
        await FirebaseStorage.instance.ref().child('families').child(familyCode).child('photos').child('$id.jpg').delete();
      } catch (_) {}
      try {
        await FirebaseStorage.instance.ref().child('families').child(familyCode).child('voice_labels').child('$id.m4a').delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('Error deleting contact from Firestore (silent): $e');
    }
  }

  // Upload all local contacts
  Future<void> uploadAllLocalContacts({String? forceFamilyCode}) async {
    if (!isFirebaseAvailable) return;
    
    final String familyCode;
    if (forceFamilyCode != null) {
      familyCode = forceFamilyCode;
    } else {
      final settingsBox = Hive.box<AppSettings>('settings');
      if (settingsBox.isEmpty) return;
      final settings = settingsBox.values.first;
      familyCode = settings.activeFamilySyncCode;
    }

    if (familyCode.isEmpty) return;

    _isUploadingAll = true;
    try {
      final repo = _ref.read(contactRepositoryProvider);
      final contacts = await repo.getAllContacts();
      for (final contact in contacts) {
        await _uploadContactWithCode(contact, familyCode);
      }
    } finally {
      // Small delay to allow Firestore to propagate writes before listener triggers
      await Future.delayed(const Duration(milliseconds: 500));
      _isUploadingAll = false;
    }
  }

  Future<void> pullContactsFromCloud() async {
    if (!isFirebaseAvailable) return;
    final settingsBox = Hive.box<AppSettings>('settings');
    if (settingsBox.isEmpty) return;
    final settings = settingsBox.values.first;
    if (settings.activeFamilySyncCode.isEmpty) return;

    final familyCode = settings.activeFamilySyncCode;
    final snapshot = await FirebaseFirestore.instance
        .collection('families')
        .doc(familyCode)
        .collection('contacts')
        .get();

    await _syncFromFirestore(snapshot.docs, familyCode);
  }
}

final firebaseSyncServiceProvider = Provider<FirebaseSyncService>((ref) {
  return FirebaseSyncService(ref);
});
