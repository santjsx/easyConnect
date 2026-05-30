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

  Future<void> addContact(Contact contact) async {
    try {
      final box = await _getBox();
      await box.put(contact.id, contact);
    } catch (e) {
      debugPrint('Error in ContactRepository.addContact: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }

  Future<void> updateContact(Contact contact) async {
    try {
      final box = await _getBox();
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
