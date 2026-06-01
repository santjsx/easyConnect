import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/services/csv_service.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/calling/services/system_call_service.dart';
import 'package:url_launcher/url_launcher.dart';

class AppSettingsScreen extends ConsumerStatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen> {
  List<ContactImportRow>? _parsedRows;
  String? _selectedFileName;
  bool _isProcessing = false;

  // Settings state variables
  String _currentLanguage = 'en';
  bool _voiceEnabled = true;
  bool _sosLocationShare = false;
  String? _sosContactId;
  String? _sosMsgContactId1;
  String? _sosMsgContactId2;
  String _layoutMode = 'classic';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkDefaultDialer();
  }

  Future<void> _checkDefaultDialer() async {
    final isDefault = await ref.read(systemCallServiceProvider).isDefaultDialer();
    ref.read(defaultDialerProvider.notifier).state = isDefault;
  }

  void _loadSettings() {
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    if (settingsBox != null && settingsBox.isNotEmpty) {
      final settings = settingsBox.values.first;
      _currentLanguage = settings.language;
      _voiceEnabled = settings.voiceEnabled;
      _sosLocationShare = settings.sosLocationShare;
      _sosContactId = settings.sosContactId;
      _sosMsgContactId1 = settings.sosMsgContactId1;
      _sosMsgContactId2 = settings.sosMsgContactId2;
      _layoutMode = settings.layoutMode;
    }
  }

  Future<void> _updateSetting(Function(AppSettings) updateFn) async {
    try {
      final Box<AppSettings> settingsBox;
      if (Hive.isBoxOpen('settings')) {
        settingsBox = Hive.box<AppSettings>('settings');
      } else {
        settingsBox = await Hive.openBox<AppSettings>('settings');
      }
      if (settingsBox.isNotEmpty) {
        final settings = settingsBox.values.first;
        updateFn(settings);
        await settings.save();
      }
    } catch (e) {
      debugPrint('Error in AppSettingsScreen._updateSetting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e'), backgroundColor: kSosRed),
        );
      }
    }
  }

  Future<void> _exportCSV() async {
    setState(() => _isProcessing = true);
    try {
      final contacts = await ref.read(contactRepositoryProvider).getAllContacts();
      final csvString = await ref.read(csvServiceProvider).exportToCSV(contacts);

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      await ref.read(csvServiceProvider).saveAndShare(csvString, 'easyconnect_contacts_$timestamp.csv');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV Export shared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: kSosRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _exportJSON() async {
    setState(() => _isProcessing = true);
    try {
      final contacts = await ref.read(contactRepositoryProvider).getAllContacts();

      final Box<AppSettings> settingsBox;
      if (Hive.isBoxOpen('settings')) {
        settingsBox = Hive.box<AppSettings>('settings');
      } else {
        settingsBox = await Hive.openBox<AppSettings>('settings');
      }
      AppSettings? settings;
      if (settingsBox.isNotEmpty) {
        settings = settingsBox.values.first;
      } else {
        settings = AppSettings(adminPin: '1234');
      }

      final jsonString = await ref.read(csvServiceProvider).exportToJSON(contacts, settings);

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      await ref.read(csvServiceProvider).saveAndShare(jsonString, 'easyconnect_backup_$timestamp.json');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('JSON Backup shared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: kSosRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickCSV() async {
    setState(() => _isProcessing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final rows = await ref.read(csvServiceProvider).parseCSV(filePath);

        if (mounted) {
          setState(() {
            _parsedRows = rows;
            _selectedFileName = result.files.single.name;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read CSV: $e'), backgroundColor: kSosRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _importContacts() async {
    if (_parsedRows == null || _parsedRows!.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final validRows = _parsedRows!.where((row) => row.errors.isEmpty).toList();
      final totalValid = validRows.length;
      final totalSkipped = _parsedRows!.length - totalValid;

      await ref.read(csvServiceProvider).importValidRows(
            _parsedRows!,
            ref.read(contactRepositoryProvider),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$totalValid contacts imported, $totalSkipped skipped'),
            backgroundColor: kCallGreen,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _parsedRows = null;
          _selectedFileName = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: kSosRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _updateLanguage(String code) async {
    if (_currentLanguage == code) return;

    setState(() {
      _currentLanguage = code;
    });

    try {
      await _updateSetting((s) => s.language = code);

      final ttsService = ref.read(ttsServiceProvider);
      await ttsService.setLanguage(code);

      String confirmationMessage = '';
      if (code == 'te') {
        confirmationMessage = 'భాష తెలుగుకు మార్చబడింది';
      } else if (code == 'hi') {
        confirmationMessage = 'भाषा हिन्दी में बदल दी गई है';
      } else {
        confirmationMessage = 'Language changed to English';
      }
      await ttsService.speak(confirmationMessage);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update language: $e'), backgroundColor: kSosRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsStreamProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Slate 50 background
      appBar: AppBar(
        title: const Text(
          'App Settings',
          style: TextStyle(
            color: kTextNavy,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: kTextNavy,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextDark, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 16.0,
                bottom: 16.0 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SECTION 1: App Settings
                  _buildSectionHeader('Preferences & Styles'),
                  const SizedBox(height: 12),
                  _buildAppSettingsSection(contactsAsync),
                  const SizedBox(height: 28),

                  // SECTION 2: Backup & Import
                  _buildSectionHeader('Backup & Utilities'),
                  const SizedBox(height: 12),
                  _buildImportExportSection(),

                  if (_parsedRows != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Preview File: $_selectedFileName',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                    ),
                    const SizedBox(height: 8),
                    _buildPreviewList(),
                  ],
                  const SizedBox(height: 28),

                  // SECTION 3: About & Privacy
                  _buildSectionHeader('Developer & Privacy'),
                  const SizedBox(height: 12),
                  _buildAboutSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18.0,
          fontWeight: FontWeight.bold,
          color: kTextNavy,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _buildAppSettingsSection(AsyncValue<List<Contact>> contactsAsync) {
    final isDefaultDialer = ref.watch(defaultDialerProvider);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Home Screen Layout Selector
            const Text(
              'Home Screen Layout Style',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: kTextNavy),
            ),
            const SizedBox(height: 12),
            _buildLayoutSelectorRow(),
            const Divider(height: 40, color: Color(0xFFF1F5F9)),

            // App Language Selector
            const Text(
              'Language Selector',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: kTextNavy),
            ),
            const SizedBox(height: 12),
            _buildLanguageSelectorRow(),
            const Divider(height: 40, color: Color(0xFFF1F5F9)),

            // Voice Guidance Toggle
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: kCallGreen,
              title: const Text(
                'Voice Guidance',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: kTextNavy),
              ),
              subtitle: const Text(
                'Audible confirmation prompts for all call inputs.',
                style: TextStyle(color: kTextSlate, fontWeight: FontWeight.w500),
              ),
              value: _voiceEnabled,
              onChanged: (bool value) async {
                setState(() => _voiceEnabled = value);
                await _updateSetting((s) => s.voiceEnabled = value);
              },
            ),
            const Divider(height: 40, color: Color(0xFFF1F5F9)),

            // SOS Contact Dropdown Picker (For Call)
            const Text(
              'SOS Emergency Contact (To CALL)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: kTextNavy),
            ),
            const SizedBox(height: 8),
            contactsAsync.when(
              data: (contacts) {
                return DropdownButtonFormField<String?>(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: kAccentPurple, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    fillColor: const Color(0xFFF8FAFC),
                    filled: true,
                  ),
                  initialValue: _sosContactId,
                  hint: const Text('Select contact to call in emergency'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None (Disable SOS Call)'),
                    ),
                    ...contacts.map((c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.name),
                        )),
                  ],
                  onChanged: (String? newValue) async {
                    setState(() => _sosContactId = newValue);
                    await _updateSetting((s) => s.sosContactId = newValue);
                  },
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (e, s) => Text('Error loading contact list: $e'),
            ),
            const SizedBox(height: 20),

            // SOS Message Contact 1 Dropdown Picker
            const Text(
              'SOS Message Recipient 1 (To Text)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: kTextNavy),
            ),
            const SizedBox(height: 8),
            contactsAsync.when(
              data: (contacts) {
                return DropdownButtonFormField<String?>(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: kAccentPurple, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    fillColor: const Color(0xFFF8FAFC),
                    filled: true,
                  ),
                  initialValue: _sosMsgContactId1,
                  hint: const Text('Select first contact to message'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None (Disable Message 1)'),
                    ),
                    ...contacts.map((c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.name),
                        )),
                  ],
                  onChanged: (String? newValue) async {
                    setState(() => _sosMsgContactId1 = newValue);
                    await _updateSetting((s) => s.sosMsgContactId1 = newValue);
                  },
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (e, s) => Text('Error loading contact list: $e'),
            ),
            const SizedBox(height: 20),

            // SOS Message Contact 2 Dropdown Picker
            const Text(
              'SOS Message Recipient 2 (To Text)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: kTextNavy),
            ),
            const SizedBox(height: 8),
            contactsAsync.when(
              data: (contacts) {
                return DropdownButtonFormField<String?>(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: kAccentPurple, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    fillColor: const Color(0xFFF8FAFC),
                    filled: true,
                  ),
                  initialValue: _sosMsgContactId2,
                  hint: const Text('Select second contact to message'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None (Disable Message 2)'),
                    ),
                    ...contacts.map((c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.name),
                        )),
                  ],
                  onChanged: (String? newValue) async {
                    setState(() => _sosMsgContactId2 = newValue);
                    await _updateSetting((s) => s.sosMsgContactId2 = newValue);
                  },
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (e, s) => Text('Error loading contact list: $e'),
            ),
            const Divider(height: 40, color: Color(0xFFF1F5F9)),

            // SOS Location Sharing Toggle
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: kCallGreen,
              title: const Text(
                'SOS Location Sharing',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: kTextNavy),
              ),
              subtitle: const Text(
                'Sends GPS coordinates inside text alerts on SOS triggers.',
                style: TextStyle(color: kTextSlate, fontWeight: FontWeight.w500),
              ),
              value: _sosLocationShare,
              onChanged: (bool value) async {
                setState(() => _sosLocationShare = value);
                await _updateSetting((s) => s.sosLocationShare = value);
              },
            ),
            const Divider(height: 40, color: Color(0xFFF1F5F9)),

            // Default Phone App Integration
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Default Phone App',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: kTextNavy),
              ),
              subtitle: Text(
                isDefaultDialer
                    ? 'EasyConnect is active as the default phone call screen.'
                    : 'Allows EasyConnect to replace the native system dialer for normal phone calls.',
                style: const TextStyle(color: kTextSlate, fontWeight: FontWeight.w500),
              ),
              trailing: SizedBox(
                width: 120,
                height: 40,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDefaultDialer ? Colors.grey : kCallGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                  ),
                  onPressed: isDefaultDialer
                      ? null
                      : () async {
                          await ref.read(systemCallServiceProvider).requestDefaultDialer();
                          Future.delayed(const Duration(seconds: 1), _checkDefaultDialer);
                          Future.delayed(const Duration(seconds: 3), _checkDefaultDialer);
                        },
                  child: Text(
                    isDefaultDialer ? 'Active' : 'Set Default',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutSelectorRow() {
    final modes = [
      {'code': 'classic', 'title': 'Classic Grid', 'subtitle': '4-column direct call layout (Mockup Theme)'},
      {'code': 'modern', 'title': 'Modern Dashboard', 'subtitle': 'Multi-action buttons layout with tabs'},
    ];

    return Column(
      children: modes.map((m) {
        final code = m['code']!;
        final title = m['title']!;
        final subtitle = m['subtitle']!;
        final isSelected = _layoutMode == code;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: InkWell(
            onTap: () async {
              if (_layoutMode == code) return;
              setState(() {
                _layoutMode = code;
              });
              await _updateSetting((s) => s.layoutMode = code);
              final ttsService = ref.read(ttsServiceProvider);
              if (code == 'classic') {
                await ttsService.speak('లేఅవుట్ క్లాసిక్ మోడ్‌కు మార్చబడింది', forceLanguage: 'te');
              } else {
                await ttsService.speak('లేఅవుట్ మోడరన్ మోడ్‌కు మార్చబడింది', forceLanguage: 'te');
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? kCallGreen : const Color(0xFFE2E8F0),
                  width: isSelected ? 2.5 : 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    code == 'classic' ? Icons.grid_view : Icons.dashboard,
                    color: isSelected ? kCallGreen : kTextDark,
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? kCallGreen : kTextNavy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? kCallGreen.withValues(alpha: 0.8) : kTextSlate,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle,
                      color: kCallGreen,
                      size: 24,
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLanguageSelectorRow() {
    final languages = [
      {'code': 'te', 'label': 'తెలుగు', 'sub': 'Telugu'},
      {'code': 'hi', 'label': 'हिन्दी', 'sub': 'Hindi'},
      {'code': 'en', 'label': 'English', 'sub': 'English'},
    ];

    return Row(
      children: languages.map((lang) {
        final code = lang['code']!;
        final label = lang['label']!;
        final isSelected = _currentLanguage == code;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: InkWell(
              onTap: () => _updateLanguage(code),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? kCallGreen : const Color(0xFFE2E8F0),
                    width: isSelected ? 2.5 : 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? kCallGreen : kTextNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lang['sub']!,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected ? kCallGreen.withValues(alpha: 0.8) : kTextSlate,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildImportExportSection() {
    final validCount = _parsedRows?.where((r) => r.errors.isEmpty).length ?? 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: kMinTouchTarget,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kCallGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _pickCSV,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text(
                        'Import CSV',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ),
                if (_parsedRows != null && validCount > 0) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: kMinTouchTarget,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFECFDF5),
                          foregroundColor: kCallGreen,
                          side: const BorderSide(color: kCallGreen, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _importContacts,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(
                          'Save $validCount Contacts',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: kMinTouchTarget,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kTextNavy,
                        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _exportCSV,
                      icon: const Icon(Icons.table_chart_outlined, color: kTextSlate),
                      label: const Text(
                        'Export CSV',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: kMinTouchTarget,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kTextNavy,
                        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _exportJSON,
                      icon: const Icon(Icons.settings_backup_restore, color: kTextSlate),
                      label: const Text(
                        'Export Backup',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewList() {
    if (_parsedRows == null || _parsedRows!.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(
            child: Text('Selected CSV file is empty.'),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _parsedRows!.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = _parsedRows![index];
        final hasErrors = row.errors.isNotEmpty;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hasErrors ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasErrors ? const Color(0xFFFECDD3) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasErrors ? Icons.error_outline : Icons.check_circle_outline,
                color: hasErrors ? kStopRed : kCallGreen,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name ?? '[No Name]',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: hasErrors && row.name == null ? Colors.red.shade900 : kTextNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Phone: ${row.phone ?? "N/A"}',
                      style: const TextStyle(fontSize: 13, color: kTextSlate, fontWeight: FontWeight.w500),
                    ),
                    if (row.whatsapp != null && row.whatsapp!.isNotEmpty)
                      Text(
                        'WhatsApp: ${row.whatsapp}',
                        style: const TextStyle(fontSize: 13, color: kTextSlate, fontWeight: FontWeight.w500),
                      ),
                    if (row.photoPath != null && row.photoPath!.isNotEmpty)
                      Text(
                        'Photo: ${row.photoPath}',
                        style: const TextStyle(fontSize: 13, color: kTextSlate, fontWeight: FontWeight.w500),
                      ),
                    if (hasErrors) ...[
                      const SizedBox(height: 8),
                      ...row.errors.map(
                        (err) => Padding(
                          padding: const EdgeInsets.only(bottom: 2.0),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red.shade900),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  err,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAboutSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFECDD3),
                width: 1.5,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.favorite_rounded,
                color: Color(0xFFF43F5E),
                size: 26,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'E A S Y C O N N E C T',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade400,
              letterSpacing: 4.0,
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            textAlign: TextAlign.center,
            text: const TextSpan(
              style: TextStyle(
                fontSize: 16,
                color: kTextDark,
                letterSpacing: -0.3,
              ),
              children: [
                TextSpan(
                  text: 'Built by ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: 'Santhoshh',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF43F5E),
                  ),
                ),
                TextSpan(
                  text: ' with love for ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: 'Mom',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: kAccentPurple,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'An offline, high-privacy calling application designed to make communication simple and accessible.',
            style: TextStyle(
              fontSize: 12,
              color: kTextSlate,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: kMinTouchTarget,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kAccentPurple,
                      side: const BorderSide(color: kAccentPurple, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _showPrivacyPolicy,
                    icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                    label: const Text(
                      'Privacy Policy',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: kMinTouchTarget,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kAccentPurple,
                      side: const BorderSide(color: kAccentPurple, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _showTermsOfService,
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text(
                      'Terms of Service',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: kMinTouchTarget,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccentPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              onPressed: () async {
                final Uri url = Uri.parse('https://santhoshh.xyz/');
                try {
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  debugPrint('Could not launch portfolio url: $e');
                }
              },
              icon: const Icon(Icons.language_rounded, size: 20),
              label: const Text(
                'Visit Developer Portfolio',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'EasyConnect v1.3.2 — Offline-First & Private',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.privacy_tip_outlined, color: kAccentPurple, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: kTextNavy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        Text(
                          'Last Updated: May 2026',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Introduction',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'EasyConnect is designed specifically for elderly and illiterate users to have a completely accessible, foolproof phone calling experience. We believe privacy is a fundamental human right. Because this app is built for family and loved ones, it works entirely offline with zero tracking.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '1. Zero Cloud Synchronization',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'EasyConnect does NOT send your contacts list, call logs, phone numbers, or any user activity to external servers or cloud providers. All data remains inside the private local sandbox on your physical device.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '2. Completely Local Telephony & Monitoring',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'By registering as a default phone handler, the app monitors active call states purely locally. It uses Android native services to instantly display the large Accept/Decline overlays without recording, uploading, or storing audio conversations.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '3. On-Device Voice Guidance (TTS)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'All spoken names and voice notifications are processed entirely on-device using Android\'s local system text-to-speech framework. No speech profiles or audio clips are sent to third parties.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '4. Emergency SOS Alerts',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'When the SOS button is triggered, the app compiles your current GPS location and sends a text message strictly through your cellular SIM card to the emergency contact designated in settings. This information is sent directly to your family member with no intermediate storage.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '5. Security & Device Sandbox',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Local data is stored in Hive (NoSQL database) using the system-protected sandboxed file space. Standard security protocols are implemented to prevent external modifications of contacts or emergency parameters.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: kMinTouchTarget,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Close',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showTermsOfService() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.description_outlined, color: kAccentPurple, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'Terms of Service',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: kTextNavy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        Text(
                          'Last Updated: May 2026',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '1. Acceptance of Terms',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'By installing and using EasyConnect, you agree to these terms. This app is designed to replace your system phone dialer and SMS client solely to provide enhanced accessibility.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '2. Default Dialer & Permissions',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'For the application to show large incoming call sheets and process dial requests, you must set EasyConnect as the Default Phone App and grant background overlay permissions. The application cannot process phone calls otherwise.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '3. Emergency SOS Triggers',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The SOS emergency trigger relies on standard cellular networks to place phone calls and send background SMS alerts containing GPS coordinates. Accuracy depends on your device\'s hardware GPS module and cellular coverage. EasyConnect does not guarantee real-time delivery if network signals are absent.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '4. Safe Usage & Liability',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextNavy),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This is a local, sandboxed utility app built for personal use. While we strive to maintain high reliability for calling and accessibility, the app is provided "as is" without warranties of any kind. Developers assume no liability for missed signals or network errors.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: kMinTouchTarget,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Close',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
