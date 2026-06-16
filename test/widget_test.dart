import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/contacts/widgets/contact_form_sheet.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:easyconnect/services/tts_service.dart';

class FakeTTSService extends Fake implements TTSService {
  @override
  Future<void> speak(
    String text, {
    String? forceLanguage,
    bool isDuringActiveCall = false,
    bool useSystemTts = true,
  }) async {}
}

class FakeContactRepository extends Fake implements ContactRepository {
  @override
  Future<List<Contact>> getAllContacts() async => [];
}

void main() {
  testWidgets('Test ContactFormSheet UI states', (WidgetTester tester) async {
    // 1. Test when contact is null (creation mode)
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dynamicAccentColorProvider.overrideWithValue(Colors.purple),
          contactRepositoryProvider.overrideWithValue(FakeContactRepository()),
          ttsServiceProvider.overrideWithValue(FakeTTSService()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ContactFormSheet(key: UniqueKey(), contact: null),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify it renders the "Record Voice" button
    expect(find.text('Record Voice'), findsOneWidget);

    // 2. Test when contact has null voiceLabelPath
    final contactWithNullVoice = Contact(
      id: 'test-id-1',
      name: 'Santhosh Null',
      phoneNumber: '+919876543210',
      positionIndex: 0,
      voiceLabelPath: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dynamicAccentColorProvider.overrideWithValue(Colors.purple),
          contactRepositoryProvider.overrideWithValue(FakeContactRepository()),
          ttsServiceProvider.overrideWithValue(FakeTTSService()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ContactFormSheet(key: UniqueKey(), contact: contactWithNullVoice),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Record Voice'), findsOneWidget);

    // 3. Test when contact has empty string voiceLabelPath
    final contactWithEmptyVoice = Contact(
      id: 'test-id-2',
      name: 'Santhosh Empty',
      phoneNumber: '+919876543210',
      positionIndex: 0,
      voiceLabelPath: '',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dynamicAccentColorProvider.overrideWithValue(Colors.purple),
          contactRepositoryProvider.overrideWithValue(FakeContactRepository()),
          ttsServiceProvider.overrideWithValue(FakeTTSService()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ContactFormSheet(key: UniqueKey(), contact: contactWithEmptyVoice),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 4. Test when contact has valid voiceLabelPath
    final contactWithValidVoice = Contact(
      id: 'test-id-3',
      name: 'Santhosh Valid',
      phoneNumber: '+919876543210',
      positionIndex: 0,
      voiceLabelPath: '/some/path/to/voice.m4a',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dynamicAccentColorProvider.overrideWithValue(Colors.purple),
          contactRepositoryProvider.overrideWithValue(FakeContactRepository()),
          ttsServiceProvider.overrideWithValue(FakeTTSService()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ContactFormSheet(key: UniqueKey(), contact: contactWithValidVoice),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
  });
}
