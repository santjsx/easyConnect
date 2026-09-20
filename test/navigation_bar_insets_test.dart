import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/contacts/widgets/contact_form_sheet.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:easyconnect/features/ota_update/screens/ota_update_screen.dart';
import 'package:easyconnect/core/widgets/app_bottom_sheet.dart';
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
  const double kNav3ButtonHeight = 48.0;

  group('3-Button Navigation Bar Insets Protection Tests', () {
    testWidgets('ContactFormSheet accommodates 3-button navigation insets in scrollview padding', (WidgetTester tester) async {
      final testContact = Contact(
        id: 'test-edit-1',
        name: 'Grandpa',
        phoneNumber: '+919876543210',
        positionIndex: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dynamicAccentColorProvider.overrideWithValue(Colors.purple),
            contactRepositoryProvider.overrideWithValue(FakeContactRepository()),
            ttsServiceProvider.overrideWithValue(FakeTTSService()),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                padding: EdgeInsets.only(bottom: kNav3ButtonHeight),
                viewPadding: EdgeInsets.only(bottom: kNav3ButtonHeight),
              ),
              child: Scaffold(
                body: ContactFormSheet(contact: testContact),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the SingleChildScrollView inside ContactFormSheet
      final scrollViewFinder = find.byType(SingleChildScrollView);
      expect(scrollViewFinder, findsOneWidget);

      final SingleChildScrollView scrollView = tester.widget(scrollViewFinder);
      final EdgeInsets padding = scrollView.padding as EdgeInsets;

      // Bottom padding should be at least 24.0 + 48.0 = 72.0
      expect(padding.bottom, greaterThanOrEqualTo(24.0 + kNav3ButtonHeight));
      expect(find.text('Edit Contact'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('OtaUpdateScreen scrollview includes bottom navigation bar insets', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                padding: EdgeInsets.only(bottom: kNav3ButtonHeight),
                viewPadding: EdgeInsets.only(bottom: kNav3ButtonHeight),
              ),
              child: const OtaUpdateScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scrollViewFinder = find.byType(SingleChildScrollView);
      expect(scrollViewFinder, findsOneWidget);

      final SingleChildScrollView scrollView = tester.widget(scrollViewFinder);
      final EdgeInsets padding = scrollView.padding as EdgeInsets;

      // Bottom padding should be 20.0 + 48.0 = 68.0
      expect(padding.bottom, equals(20.0 + kNav3ButtonHeight));
      expect(find.text('Software Update'), findsOneWidget);
    });

    testWidgets('AppBottomSheetContainer enforces SafeArea at the bottom', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: kNav3ButtonHeight),
              viewPadding: EdgeInsets.only(bottom: kNav3ButtonHeight),
            ),
            child: const Scaffold(
              body: AppBottomSheetContainer(
                child: Text('Protected Sheet Content'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that SafeArea exists and has bottom enabled
      final safeAreaFinder = find.descendant(
        of: find.byType(AppBottomSheetContainer),
        matching: find.byType(SafeArea),
      );
      expect(safeAreaFinder, findsOneWidget);

      final SafeArea safeArea = tester.widget(safeAreaFinder);
      expect(safeArea.bottom, isTrue);
      expect(safeArea.top, isFalse);
      expect(find.text('Protected Sheet Content'), findsOneWidget);
    });

    testWidgets('Privacy Policy and Terms of Service bottom sheet containers include bottom insets', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(bottom: kNav3ButtonHeight),
              viewPadding: const EdgeInsets.only(bottom: kNav3ButtonHeight),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (sheetContext) {
                        final bottomInset = MediaQuery.paddingOf(sheetContext).bottom;
                        return Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                          ),
                          padding: EdgeInsets.only(
                            left: 24,
                            right: 24,
                            top: 16,
                            bottom: 16 + bottomInset,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Privacy Policy'),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  child: const Text('Open Privacy'),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap open button
      await tester.tap(find.text('Open Privacy'));
      await tester.pumpAndSettle();

      // Find the sheet container
      final containerFinder = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Container),
      );
      expect(containerFinder, findsWidgets);

      final Container sheetContainer = tester.widget(containerFinder.first);
      final EdgeInsets padding = sheetContainer.padding as EdgeInsets;

      // Bottom padding must be 16.0 + 48.0 = 64.0
      expect(padding.bottom, equals(16.0 + kNav3ButtonHeight));
      expect(find.text('Close'), findsOneWidget);
    });
  });
}
