import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/services/firebase_sync_service.dart';

class ContactRepository {
  final TTSService _ttsService;
  final Ref _ref;

  ContactRepository(this._ttsService, this._ref);

  Future<Box<Contact>> _getBox() async {
    if (Hive.isBoxOpen('contacts')) {
      return Hive.box<Contact>('contacts');
    }
    return await Hive.openBox<Contact>('contacts');
  }

  String _hslToHex(double hue, double saturation, double lightness) {
    final color = HSLColor.fromAHSL(1.0, hue, saturation, lightness).toColor();
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }

  String _generateUnusedColor(List<Contact> existingContacts) {
    final List<String> palette = [
      '#6C6BF8', // Vibrant Purple/Blue
      '#FF8C00', // Dark Orange
      '#32E08A', // Mint Green
      '#E8265E', // Rose Pink
      '#007AFF', // iOS Blue
      '#AF52DE', // iOS Purple
      '#FF3B30', // iOS Red
      '#FF9500', // iOS Orange
      '#FFCC00', // iOS Yellow
      '#4CD964', // iOS Green
      '#5AC8FA', // iOS Teal
      '#10B981', // Emerald
      '#F59E0B', // Amber
      '#EF4444', // Red
      '#EC4899', // Pink
      '#8B5CF6', // Purple
      '#3B82F6', // Blue
      '#14B8A6', // Teal
      '#06B6D4', // Cyan
      '#6366F1', // Indigo
      '#84CC16', // Lime
      '#D946EF', // Fuchsia
      '#F43F5E', // Rose
      '#0EA5E9', // Sky Blue
      '#E11D48', // Crimson Rose
      '#D97706', // Ochre Amber
      '#7C3AED', // Royal Violet
      '#059669', // Deep Emerald
      '#2563EB', // Sapphire Blue
      '#DB2777', // Magenta Pink
      '#EA580C', // Rust Orange
      '#0891B2', // Deep Teal/Cyan
      '#4F46E5', // Slate Indigo
      '#65A30D', // Olive Lime
      '#C026D3', // Bright Orchid
      '#B45309', // Brown Amber
      '#9333EA', // Bright Purple
    ];

    final existingColors = existingContacts.map((c) => c.colorTheme.toUpperCase()).toSet();

    for (final color in palette) {
      if (!existingColors.contains(color.toUpperCase())) {
        return color;
      }
    }

    double hue = 0.0;
    for (int i = 0; i < existingContacts.length + 1; i++) {
      hue = (hue + 0.618033988749895) % 1.0;
      final generatedHex = _hslToHex(hue * 360, 0.75, 0.5);
      if (!existingColors.contains(generatedHex.toUpperCase())) {
        return generatedHex;
      }
    }

    return '#6C6BF8';
  }

  Future<List<Contact>> getAllContacts() async {
    try {
      final box = await _getBox();
      final list = box.values.toList();
      list.sort((a, b) => a.positionIndex.compareTo(b.positionIndex));
      return list;
    } catch (e) {
      debugPrint('Error in ContactRepository.getAllContacts: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
      return [];
    }
  }

  // Self-healing migration called only on app boot to clean up default colors
  Future<void> runColorMigration() async {
    try {
      final box = await _getBox();
      final list = box.values.toList();
      for (final contact in list) {
        if (contact.colorTheme == '#4CAF50') {
          final unusedColor = _generateUnusedColor(list);
          final updated = contact.copyWith(colorTheme: unusedColor);
          await box.put(updated.id, updated);
        }
      }
    } catch (e) {
      debugPrint('Color migration failed: $e');
    }
  }

  Future<String?> _persistPhoto(String contactId, String? tempPath) async {
    if (tempPath == null || tempPath.isEmpty) return null;
    
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final permanentDir = Directory('${appDocDir.path}/photos');
      
      // If it's already in the permanent directory, no need to copy
      if (tempPath.startsWith(permanentDir.path)) {
        return tempPath;
      }
      
      final tempFile = File(tempPath);
      if (!await tempFile.exists()) {
        return tempPath;
      }
      
      if (!await permanentDir.exists()) {
        await permanentDir.create(recursive: true);
      }
      
      // Use timestamped suffix to bust flutter image cache
      final newPath = '${permanentDir.path}/${contactId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final newFile = await tempFile.copy(newPath);
      
      // Delete old photos for this contact (excluding the one we just saved)
      await _deleteOldPhoto(contactId, excludePath: newFile.path);
      
      return newFile.path;
    } catch (e) {
      debugPrint('Error persisting contact photo: $e');
      return tempPath;
    }
  }

  Future<void> _deleteOldPhoto(String contactId, {String? excludePath}) async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDocDir.path}/photos');
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            final baseName = entity.uri.pathSegments.last;
            if (baseName.startsWith('${contactId}_') || baseName == '$contactId.jpg') {
              if (entity.path != excludePath) {
                await entity.delete();
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error deleting old photo for $contactId: $e');
    }
  }

  Future<void> _deleteContactFiles(String id) async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      
      // Delete photos
      final photosDir = Directory('${appDocDir.path}/photos');
      if (await photosDir.exists()) {
        await for (final entity in photosDir.list()) {
          if (entity is File) {
            final baseName = entity.uri.pathSegments.last;
            if (baseName.startsWith('${id}_') || baseName == '$id.jpg') {
              await entity.delete();
            }
          }
        }
      }
      
      // Delete voice labels
      final voiceDir = Directory('${appDocDir.path}/voice_labels');
      if (await voiceDir.exists()) {
        await for (final entity in voiceDir.list()) {
          if (entity is File) {
            final baseName = entity.uri.pathSegments.last;
            if (baseName.startsWith('${id}_') || baseName == '$id.m4a') {
              await entity.delete();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error deleting contact files: $e');
    }
  }

  Future<void> addContact(Contact contact, {bool isFromSync = false}) async {
    try {
      final box = await _getBox();
      final existing = box.values.toList();
      var finalContact = contact;
      
      if (!isFromSync && contact.photoPath != null) {
        final permanentPhotoPath = await _persistPhoto(contact.id, contact.photoPath);
        finalContact = contact.copyWith(photoPath: permanentPhotoPath);
      }

      if (contact.colorTheme == '#4CAF50') {
        finalContact = finalContact.copyWith(colorTheme: _generateUnusedColor(existing));
      }
      await box.put(finalContact.id, finalContact);
      if (!isFromSync) {
        _ref.read(firebaseSyncServiceProvider).uploadContact(finalContact);
      }
    } catch (e) {
      debugPrint('Error in ContactRepository.addContact: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }

  Future<void> updateContact(Contact contact, {bool isFromSync = false}) async {
    try {
      final box = await _getBox();
      final existing = box.values.toList();
      var finalContact = contact;

      if (!isFromSync) {
        if (contact.photoPath != null) {
          final permanentPhotoPath = await _persistPhoto(contact.id, contact.photoPath);
          finalContact = contact.copyWith(photoPath: permanentPhotoPath);
        } else {
          await _deleteOldPhoto(contact.id);
        }
      }

      if (contact.colorTheme == '#4CAF50') {
        existing.removeWhere((c) => c.id == contact.id);
        finalContact = finalContact.copyWith(colorTheme: _generateUnusedColor(existing));
      }
      await box.put(finalContact.id, finalContact);
      if (!isFromSync) {
        _ref.read(firebaseSyncServiceProvider).uploadContact(finalContact);
      }
    } catch (e) {
      debugPrint('Error in ContactRepository.updateContact: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }

  Future<void> deleteContact(String id, {bool isFromSync = false}) async {
    try {
      await _deleteContactFiles(id);
      final box = await _getBox();
      await box.delete(id);
      if (!isFromSync) {
        _ref.read(firebaseSyncServiceProvider).deleteContact(id);
      }
    } catch (e) {
      debugPrint('Error in ContactRepository.deleteContact: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }

  Future<void> reorderContacts(List<String> orderedIds) async {
    try {
      final box = await _getBox();
      for (int i = 0; i < orderedIds.length; i++) {
        final id = orderedIds[i];
        final contact = box.get(id);
        if (contact != null) {
          final updated = contact.copyWith(positionIndex: i);
          await box.put(id, updated);
          _ref.read(firebaseSyncServiceProvider).uploadContact(updated);
        }
      }
    } catch (e) {
      debugPrint('Error in ContactRepository.reorderContacts: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }

  Future<void> clearAllContacts() async {
    try {
      final contacts = await getAllContacts();
      for (final contact in contacts) {
        await _deleteContactFiles(contact.id);
      }
      final box = await _getBox();
      await box.clear();
    } catch (e) {
      debugPrint('Error in ContactRepository.clearAllContacts: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }
}

final contactRepositoryProvider = Provider<ContactRepository>((ref) {
  final ttsService = ref.watch(ttsServiceProvider);
  return ContactRepository(ttsService, ref);
});

final contactsStreamProvider = StreamProvider<List<Contact>>((ref) async* {
  final repo = ref.watch(contactRepositoryProvider);
  
  // Yield initial contacts list
  yield await repo.getAllContacts();
  
  // Watch for any changes in the Hive box
  final box = Hive.isBoxOpen('contacts') ? Hive.box<Contact>('contacts') : await Hive.openBox<Contact>('contacts');
  await for (final _ in box.watch()) {
    yield await repo.getAllContacts();
  }
});

final contactsMapProvider = Provider<Map<String, Contact>>((ref) {
  final contactsAsync = ref.watch(contactsStreamProvider);
  return contactsAsync.maybeWhen(
    data: (contacts) {
      final Map<String, Contact> map = {};
      for (final contact in contacts) {
        final cleanPhone = contact.phoneNumber.replaceAll(RegExp(r'\D'), '');
        if (cleanPhone.isNotEmpty) {
          map[cleanPhone] = contact;
        }
        map[contact.name.toLowerCase().trim()] = contact;
      }
      return map;
    },
    orElse: () => const <String, Contact>{},
  );
});
