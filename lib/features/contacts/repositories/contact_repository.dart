import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/services/tts_service.dart';

class ContactRepository {
  final TTSService _ttsService;

  ContactRepository(this._ttsService);

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
      
      for (final contact in list) {
        if (contact.colorTheme == '#4CAF50') {
          final unusedColor = _generateUnusedColor(list);
          contact.colorTheme = unusedColor;
          await contact.save();
        }
      }
      
      list.sort((a, b) => a.positionIndex.compareTo(b.positionIndex));
      return list;
    } catch (e) {
      debugPrint('Error in ContactRepository.getAllContacts: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
      return [];
    }
  }

  Future<void> addContact(Contact contact) async {
    try {
      final box = await _getBox();
      final existing = box.values.toList();
      if (contact.colorTheme == '#4CAF50') {
        contact.colorTheme = _generateUnusedColor(existing);
      }
      await box.put(contact.id, contact);
    } catch (e) {
      debugPrint('Error in ContactRepository.addContact: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }

  Future<void> updateContact(Contact contact) async {
    try {
      final box = await _getBox();
      final existing = box.values.toList();
      if (contact.colorTheme == '#4CAF50') {
        existing.removeWhere((c) => c.id == contact.id);
        contact.colorTheme = _generateUnusedColor(existing);
      }
      await box.put(contact.id, contact);
    } catch (e) {
      debugPrint('Error in ContactRepository.updateContact: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }

  Future<void> deleteContact(String id) async {
    try {
      final box = await _getBox();
      await box.delete(id);
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
          contact.positionIndex = i;
          await contact.save();
        }
      }
    } catch (e) {
      debugPrint('Error in ContactRepository.reorderContacts: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }

  Future<void> clearAllContacts() async {
    try {
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
  return ContactRepository(ttsService);
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
