import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/services/csv_service.dart';
import 'package:easyconnect/services/backup_service.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/calling/services/system_call_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easyconnect/services/firebase_sync_service.dart';

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
  String? _accentColorHex; // Custom accent color hex
  bool _hasCallPhonePermission = false;
  bool _hasSendSmsPermission = false;

  // Firebase Sync state variables
  bool _isSyncEnabled = false;
  late final TextEditingController _syncCodeController;

  Color get kAccentPurple => getAccentColor(_accentColorHex);
  Color get dynamicAccentColor => kAccentPurple;

  // Active Category Tab: 0: Preferences, 1: Emergency SOS, 2: Backup & Info
  int _activeTab = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _syncCodeController = TextEditingController();
    _pageController = PageController(initialPage: _activeTab);
    _loadSettings();
    _checkDefaultDialer();
    _checkSosPermissions();
  }

  @override
  void dispose() {
    _syncCodeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkSosPermissions() async {
    final callGranted = await Permission.phone.isGranted;
    final smsGranted = await Permission.sms.isGranted;
    if (mounted) {
      setState(() {
        _hasCallPhonePermission = callGranted;
        _hasSendSmsPermission = smsGranted;
      });
    }
  }

  Future<void> _requestSosPermissions() async {
    final statuses = await [
      Permission.phone,
      Permission.sms,
    ].request();

    await _checkSosPermissions();

    if (mounted) {
      final callGranted = statuses[Permission.phone]?.isGranted == true;
      final smsGranted = statuses[Permission.sms]?.isGranted == true;
      final allGranted = callGranted && smsGranted;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(allGranted
              ? 'All SOS background permissions granted successfully!'
              : 'Some permissions were not granted. SOS alerts may require manual steps.'),
          backgroundColor: allGranted ? kAccentPurple : kSosRed,
        ),
      );
    }
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
      _layoutMode = settings.activeLayoutMode;
      _accentColorHex = settings.activeAccentColorHex;
      _isSyncEnabled = settings.activeIsSyncEnabled;
      _syncCodeController.text = settings.activeFamilySyncCode;
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

  Future<void> _backupZIP() async {
    setState(() => _isProcessing = true);
    try {
      final success = await ref.read(backupServiceProvider).createAndShareBackup();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup archive (ZIP) shared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e'), backgroundColor: kSosRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _restoreZIP() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Restore'),
        content: const Text(
          'This will overwrite all current contacts and settings. Are you sure you want to restore?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kSosRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      final success = await ref.read(backupServiceProvider).restoreFromBackup();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('App restored successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(contactsStreamProvider);
        ref.invalidate(settingsProvider);
        setState(() {
          _loadSettings();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e'), backgroundColor: kSosRed),
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
            backgroundColor: kAccentPurple,
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

  Widget _buildGroup({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 7.0),
            child: Text(
              label.toUpperCase(),
              style: GoogleFonts.nunito(
                fontSize: 10.0,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: const Color(0xFF9999B0),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF2F2F8), width: 1.5),
            ),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildTog({required bool val, required ValueChanged<bool> onChanged}) {
    return GestureDetector(
      onTap: () => onChanged(!val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 27,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: val ? const Color(0xFF32E08A) : const Color(0xFFE0E0EB),
        ),
        padding: const EdgeInsets.all(2.0),
        alignment: val ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 23,
          height: 23,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required Color iconBgColor,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    bool showDivider = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 13.0),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: Color(0xFFF2F2F8), width: 0.5))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 15,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1B1B2E),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    color: const Color(0xFF9999B0),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    final tabs = [
      {'icon': Icons.tune_rounded, 'label': 'Preferences'},
      {'icon': Icons.notifications_active_rounded, 'label': 'Emergency SOS'},
      {'icon': Icons.settings_backup_restore_rounded, 'label': 'Backup & Info'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0x0D000000), // rgba(0,0,0,0.05)
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3.0),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final tab = tabs[index];
          final isSelected = _activeTab == index;
          final icon = tab['icon'] as IconData;
          final label = tab['label'] as String;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _activeTab = index;
                });
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOutCubic,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : [],
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: isSelected ? const Color(0xFF1B1B2E) : const Color(0xFF9999B0),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        style: GoogleFonts.nunito(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? const Color(0xFF1B1B2E) : const Color(0xFF9999B0),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLayoutSelectorRow() {
    final modes = [
      {'code': 'classic', 'title': 'Classic Grid', 'subtitle': '4-column direct call layout (Mockup Theme)', 'icon': Icons.grid_view},
      {'code': 'modern', 'title': 'Modern Dashboard', 'subtitle': 'Multi-action buttons layout with tabs', 'icon': Icons.dashboard},
    ];

    return Column(
      children: List.generate(modes.length, (index) {
        final m = modes[index];
        final code = m['code'] as String;
        final title = m['title'] as String;
        final subtitle = m['subtitle'] as String;
        final icon = m['icon'] as IconData;
        final isSelected = _layoutMode == code;

        return GestureDetector(
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 13.0),
            decoration: BoxDecoration(
              border: index < modes.length - 1
                  ? const Border(bottom: BorderSide(color: Color(0xFFF2F2F8), width: 0.5))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected ? dynamicAccentColor.withValues(alpha: 0.08) : const Color(0xFFF2F2F8),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? dynamicAccentColor : const Color(0xFF9999B0),
                    size: 17,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1B1B2E),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: GoogleFonts.nunito(
                          fontSize: 11,
                          color: const Color(0xFF9999B0),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dynamicAccentColor,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 12,
                    ),
                  )
                else
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFCCCCDA),
                    size: 17,
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildLanguageSelectorRow() {
    final languages = [
      {'code': 'te', 'label': 'తెలుగు'},
      {'code': 'hi', 'label': 'हिन्दी'},
      {'code': 'en', 'label': 'English'},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: languages.map((lang) {
          final code = lang['code']!;
          final label = lang['label']!;
          final isSelected = _currentLanguage == code;

          return GestureDetector(
            onTap: () => _updateLanguage(code),
            child: Container(
              margin: const EdgeInsets.only(right: 8.0),
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 7.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: isSelected ? kPrimaryGradient : null,
                color: isSelected ? null : const Color(0xFFF2F2F8),
              ),
              child: Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : const Color(0xFF9999B0),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAccentColorRow() {
    final activeHex = _accentColorHex ?? '#5C5BE8';

    final colorHexes = [
      '#5C5BE8', // Purple
      '#007AFF', // Blue
      '#32E08A', // Green
      '#FF8C00', // Orange
      '#FF4B6E', // Red
      '#AF52DE', // Violet
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 13.0),
      child: Row(
        children: colorHexes.map((hex) {
          final parsedColor = getAccentColor(hex);
          final isSelected = activeHex.toLowerCase() == hex.toLowerCase();

          return GestureDetector(
            onTap: () => _updateAccentColor(hex),
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 9.0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: parsedColor,
              ),
              alignment: Alignment.center,
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 13,
                    )
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _updateAccentColor(String hex) async {
    setState(() {
      _accentColorHex = hex;
    });
    await _updateSetting((s) => s.accentColorHex = hex);
  }

  Widget _buildAppSettingsSection() {
    final isDefaultDialer = ref.watch(defaultDialerProvider);
    return Column(
      children: [
        _buildGroup(
          label: 'Layout Style',
          child: _buildLayoutSelectorRow(),
        ),
        _buildGroup(
          label: 'Language',
          child: _buildLanguageSelectorRow(),
        ),
        _buildGroup(
          label: 'Accent Color',
          child: _buildAccentColorRow(),
        ),
        _buildGroup(
          label: 'Accessibility',
          child: Column(
            children: [
              _buildSettingRow(
                iconBgColor: dynamicAccentColor,
                icon: Icons.volume_up,
                title: 'Voice Guidance',
                subtitle: 'Audible call confirmations',
                trailing: _buildTog(
                  val: _voiceEnabled,
                  onChanged: (bool value) async {
                    setState(() => _voiceEnabled = value);
                    await _updateSetting((s) => s.voiceEnabled = value);
                  },
                ),
              ),
              _buildSettingRow(
                iconBgColor: const Color(0xFFFF8C00),
                icon: Icons.phone_in_talk,
                title: 'Default Phone App',
                subtitle: 'Replace system dialer',
                showDivider: false,
                trailing: GestureDetector(
                  onTap: isDefaultDialer
                      ? null
                      : () async {
                          await ref.read(systemCallServiceProvider).requestDefaultDialer();
                          Future.delayed(const Duration(seconds: 1), _checkDefaultDialer);
                          Future.delayed(const Duration(seconds: 3), _checkDefaultDialer);
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: isDefaultDialer ? null : kPrimaryGradient,
                      color: isDefaultDialer ? const Color(0xFFCCCCDA) : null,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(
                      isDefaultDialer ? 'Active' : 'Set',
                      style: GoogleFonts.nunito(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSosDot(bool active) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF32E08A) : const Color(0xFFFF2147),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildSosPermissionRow({
    required bool granted,
    required String label,
    bool showDivider = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: Color(0xFFF2F2F8), width: 0.5))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: granted ? const Color(0xFF32E08A) : const Color(0x1A000000),
            ),
            alignment: Alignment.center,
            child: Icon(
              granted ? Icons.check : Icons.close,
              color: Colors.white,
              size: 10,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1B1B2E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosDropdown({
    required String label,
    required String? currentValue,
    required List<DropdownMenuItem<String?>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF2F2F8), width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 12,
              color: const Color(0xFF9999B0),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: currentValue,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFCCCCDA), size: 17),
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1B1B2E),
              ),
              hint: Text(
                'None — disabled',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF9999B0),
                  fontStyle: FontStyle.italic,
                ),
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSharingRow() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF2F2F8), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: dynamicAccentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.map_outlined,
              color: dynamicAccentColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOS Location Sharing',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1B1B2E),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Send GPS in text alerts',
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    color: const Color(0xFF9999B0),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _buildTog(
            val: _sosLocationShare,
            onChanged: (bool value) async {
              if (value) {
                final status = await Permission.location.request();
                if (!status.isGranted) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Location permission is required to enable sharing.'),
                        backgroundColor: kSosRed,
                      ),
                    );
                  }
                  return;
                }
              }
              setState(() => _sosLocationShare = value);
              await _updateSetting((s) => s.sosLocationShare = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSosSection(AsyncValue<List<Contact>> contactsAsync) {
    final hasAllPermissions = _hasCallPhonePermission && _hasSendSmsPermission;

    return Column(
      children: [
        // SOS status card
        Container(
          margin: const EdgeInsets.only(bottom: 14.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF2F2F8), width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 13.0),
                decoration: BoxDecoration(
                  gradient: hasAllPermissions
                      ? const LinearGradient(
                          colors: [Color(0xFFE8FFF3), Color(0xFFF0FFF8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFFFF0F0), Color(0xFFFFF5F5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  border: Border(
                    bottom: BorderSide(
                      color: hasAllPermissions ? const Color(0xFFC5F0DC) : const Color(0xFFFECACA),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _buildSosDot(hasAllPermissions),
                    const SizedBox(width: 10),
                    Text(
                      hasAllPermissions ? 'SOS Background — Active' : 'SOS Background — Inactive',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1B1B2E),
                      ),
                    ),
                  ],
                ),
              ),
              _buildSosPermissionRow(
                granted: _hasCallPhonePermission,
                label: 'Direct Phone Call (CALL_PHONE)',
              ),
              _buildSosPermissionRow(
                granted: _hasSendSmsPermission,
                label: 'Background SMS (SEND_SMS)',
                showDivider: false,
              ),
            ],
          ),
        ),

        // Grant button if permissions are missing
        if (!hasAllPermissions)
          Padding(
            padding: const EdgeInsets.only(bottom: 14.0),
            child: GestureDetector(
              onTap: _requestSosPermissions,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: kSosRedGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.security_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Grant SOS Permissions',
                      style: GoogleFonts.nunito(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Emergency Call contact dropdown
        _buildGroup(
          label: 'Emergency Call',
          child: contactsAsync.when(
            data: (contacts) {
              final dropdownItems = [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None — disabled'),
                ),
                ...contacts.map((c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name),
                    )),
              ];
              return _buildSosDropdown(
                label: 'SOS Emergency Contact',
                currentValue: _sosContactId,
                items: dropdownItems,
                onChanged: (String? newValue) async {
                  setState(() => _sosContactId = newValue);
                  await _updateSetting((s) => s.sosContactId = newValue);
                },
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, s) => Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Error: $e'),
            ),
          ),
        ),

        // Text Alerts dropdown group
        _buildGroup(
          label: 'Text Alerts',
          child: contactsAsync.when(
            data: (contacts) {
              final dropdownItems = [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None — disabled'),
                ),
                ...contacts.map((c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name),
                    )),
              ];
              return Column(
                children: [
                  _buildSosDropdown(
                    label: 'Message Recipient 1',
                    currentValue: _sosMsgContactId1,
                    items: dropdownItems,
                    onChanged: (String? newValue) async {
                      setState(() => _sosMsgContactId1 = newValue);
                      await _updateSetting((s) => s.sosMsgContactId1 = newValue);
                    },
                  ),
                  _buildSosDropdown(
                    label: 'Message Recipient 2',
                    currentValue: _sosMsgContactId2,
                    items: dropdownItems,
                    onChanged: (String? newValue) async {
                      setState(() => _sosMsgContactId2 = newValue);
                      await _updateSetting((s) => s.sosMsgContactId2 = newValue);
                    },
                  ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, s) => Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Error: $e'),
            ),
          ),
        ),

        // Location sharing card
        _buildLocationSharingRow(),
      ],
    );
  }

  Widget _buildImportExportSection() {
    final validCount = _parsedRows?.where((r) => r.errors.isEmpty).length ?? 0;

    return Column(
      children: [
        _buildGroup(
          label: 'Remote Cloud Sync',
          child: Column(
            children: [
              _buildSettingRow(
                iconBgColor: Colors.blueAccent,
                icon: Icons.sync,
                title: 'Enable Cloud Sync',
                subtitle: 'Sync contacts in real-time',
                trailing: _buildTog(
                  val: _isSyncEnabled,
                  onChanged: (bool value) async {
                    if (value && _syncCodeController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a Family Sync Code first'),
                          backgroundColor: kSosRed,
                        ),
                      );
                      return;
                    }

                    if (value) {
                      final isFb = ref.read(firebaseSyncServiceProvider).isFirebaseAvailable;
                      if (!isFb) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Firebase not initialized. Google-services.json missing.'),
                            backgroundColor: kSosRed,
                          ),
                        );
                        return;
                      }

                      final upload = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Upload Contacts?'),
                          content: const Text(
                            'Do you want to upload your existing local contacts to the cloud database under this code?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Keep Remote Only'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Upload Local Contacts'),
                            ),
                          ],
                        ),
                      );

                      if (upload == null) {
                        // User dismissed dialog
                        return;
                      }

                      if (upload == true) {
                        setState(() => _isProcessing = true);
                        try {
                          final code = _syncCodeController.text.trim();
                          await ref.read(firebaseSyncServiceProvider).uploadAllLocalContacts(forceFamilyCode: code);
                          
                          setState(() {
                            _isSyncEnabled = true;
                          });
                          await _updateSetting((s) {
                            s.isSyncEnabled = true;
                            s.familySyncCode = code;
                          });

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Local contacts successfully uploaded to Firebase!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Error uploading contacts: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to upload contacts: $e'),
                                backgroundColor: kSosRed,
                              ),
                            );
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _isProcessing = false);
                          }
                        }
                      } else {
                        // User selected Keep Remote Only
                        setState(() {
                          _isSyncEnabled = true;
                        });
                        await _updateSetting((s) {
                          s.isSyncEnabled = true;
                          s.familySyncCode = _syncCodeController.text.trim();
                        });
                      }
                    } else {
                      // Disabling sync
                      setState(() {
                        _isSyncEnabled = false;
                      });
                      await _updateSetting((s) {
                        s.isSyncEnabled = false;
                        s.familySyncCode = _syncCodeController.text.trim();
                      });
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Family Sync Code',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: const Color(0xFF9999B0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _syncCodeController,
                      enabled: !_isSyncEnabled,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1B1B2E),
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. family_smith_123',
                        hintStyle: GoogleFonts.nunito(
                          fontSize: 14,
                          color: const Color(0xFF9999B0),
                        ),
                        filled: true,
                        fillColor: _isSyncEnabled ? const Color(0xFFF2F2F8) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE0E0EB)),
                        ),
                      ),
                      onChanged: (value) async {
                        await _updateSetting((s) => s.familySyncCode = value.trim());
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the same code on both phones. Turn off sync to edit the code.',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: const Color(0xFF9999B0),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_isSyncEnabled) ...[
                      const SizedBox(height: 16),
                      const Divider(height: 1, color: Color(0xFFE0E0EB)),
                      const SizedBox(height: 16),
                      // Live Sync Status indicator
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Connected & Syncing in Real-Time',
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Manual Force Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing ? null : () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Force Upload to Cloud?'),
                                    content: const Text(
                                      'This will overwrite all remote contacts in the cloud with your current local contacts.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text('Upload'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  setState(() => _isProcessing = true);
                                  try {
                                    await ref.read(firebaseSyncServiceProvider).uploadAllLocalContacts();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Uploaded local contacts successfully!'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Failed to upload: $e'),
                                          backgroundColor: kSosRed,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isProcessing = false);
                                    }
                                  }
                                }
                              },
                              icon: const Icon(Icons.cloud_upload, size: 16),
                              label: const Text('Upload Local to Cloud'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF5C5BE8),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing ? null : () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Force Download from Cloud?'),
                                    content: const Text(
                                      'This will overwrite all local contacts on this phone with the contacts from the cloud.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text('Download'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  setState(() => _isProcessing = true);
                                  try {
                                    await ref.read(firebaseSyncServiceProvider).pullContactsFromCloud();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Downloaded cloud contacts successfully!'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Failed to download: $e'),
                                          backgroundColor: kSosRed,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isProcessing = false);
                                    }
                                  }
                                }
                              },
                              icon: const Icon(Icons.cloud_download, size: 16),
                              label: const Text('Download from Cloud'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF1B1B2E),
                                side: const BorderSide(color: Color(0xFFE0E0EB)),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Visual Data Flow Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.sync_alt, size: 18, color: Color(0xFF5C5BE8)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '🔄 Two-Way Live Sync is Active:\n• Modifying contacts on this phone will instantly update the Web Dashboard.\n• Modifying contacts on the Web Dashboard will instantly update this phone.',
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  color: const Color(0xFF5A5A75),
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildGroup(
          label: 'Data Management',
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickCSV,
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: kPrimaryGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.file_upload_outlined, color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Import CSV',
                                style: GoogleFonts.nunito(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_parsedRows != null && validCount > 0) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _importContacts,
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F3FF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF5C5BE8), width: 1.0),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_outline, color: Color(0xFF5C5BE8), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Save $validCount',
                                  style: GoogleFonts.nunito(
                                    color: const Color(0xFF5C5BE8),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _exportCSV,
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0x33000000), width: 0.5),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.table_chart_outlined, color: Color(0xFF9999B0), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Export CSV',
                                style: GoogleFonts.nunito(
                                  color: const Color(0xFF1B1B2E),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: _exportJSON,
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0x33000000), width: 0.5),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.settings_backup_restore, color: Color(0xFF9999B0), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Backup JSON',
                                style: GoogleFonts.nunito(
                                  color: const Color(0xFF1B1B2E),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _backupZIP,
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0x33000000), width: 0.5),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cloud_upload_outlined, color: Color(0xFF5C5BE8), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Backup ZIP',
                                style: GoogleFonts.nunito(
                                  color: const Color(0xFF1B1B2E),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: _restoreZIP,
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0x33000000), width: 0.5),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cloud_download_outlined, color: Color(0xFF32E08A), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Restore ZIP',
                                style: GoogleFonts.nunito(
                                  color: const Color(0xFF1B1B2E),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
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
                      style: GoogleFonts.nunito(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: hasErrors && row.name == null ? Colors.red.shade900 : kTextNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Phone: ${row.phone ?? "N/A"}',
                      style: GoogleFonts.nunito(fontSize: 13, color: kTextSlate, fontWeight: FontWeight.w500),
                    ),
                    if (row.whatsapp != null && row.whatsapp!.isNotEmpty)
                      Text(
                        'WhatsApp: ${row.whatsapp}',
                        style: GoogleFonts.nunito(fontSize: 13, color: kTextSlate, fontWeight: FontWeight.w500),
                      ),
                    if (row.photoPath != null && row.photoPath!.isNotEmpty)
                      Text(
                        'Photo: ${row.photoPath}',
                        style: GoogleFonts.nunito(fontSize: 13, color: kTextSlate, fontWeight: FontWeight.w500),
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
                                  style: GoogleFonts.nunito(
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

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsStreamProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7FA),
      appBar: AppBar(
        title: Text(
          'App Settings',
          style: GoogleFonts.nunito(
            color: const Color(0xFF1B1B2E),
            fontWeight: FontWeight.w700,
            fontSize: 17.0,
          ),
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        elevation: 0,
        leadingWidth: 96.0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Center(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: dynamicAccentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: dynamicAccentColor.withValues(alpha: 0.15),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chevron_left_rounded,
                      color: dynamicAccentColor,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Back',
                      style: GoogleFonts.nunito(
                        color: dynamicAccentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(
            color: const Color(0x12000000),
            height: 0.5,
          ),
        ),
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: _buildTabSelector(),
                ),
                
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      // Page 0: Preferences
                      SingleChildScrollView(
                        padding: EdgeInsets.only(
                          left: 16.0,
                          right: 16.0,
                          top: 4.0,
                          bottom: 16.0 + MediaQuery.paddingOf(context).bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildAppSettingsSection(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                      // Page 1: Emergency SOS
                      SingleChildScrollView(
                        padding: EdgeInsets.only(
                          left: 16.0,
                          right: 16.0,
                          top: 4.0,
                          bottom: 16.0 + MediaQuery.paddingOf(context).bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSosSection(contactsAsync),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                      // Page 2: Backup & Info
                      SingleChildScrollView(
                        padding: EdgeInsets.only(
                          left: 16.0,
                          right: 16.0,
                          top: 4.0,
                          bottom: 16.0 + MediaQuery.paddingOf(context).bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildImportExportSection(),
                            if (_parsedRows != null) ...[
                              const SizedBox(height: 20),
                              Text(
                                'Preview File: $_selectedFileName',
                                style: GoogleFonts.nunito(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: kTextNavy,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildPreviewList(),
                            ],
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }
}
