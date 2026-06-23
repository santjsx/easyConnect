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
  bool _isTestingVoice = false;

  // SOS status transient variables
  bool _hasCallPhonePermission = false;

  late final TextEditingController _syncCodeController;
  late final TextEditingController _azureApiKeyController;
  late final TextEditingController _azureRegionController;
  bool _obscureApiKey = true;

  static const Map<String, String> _azureTeluguVoices = {
    'Shruti (Female)': 'te-IN-ShrutiNeural',
    'Mohan (Male)': 'te-IN-MohanNeural',
  };

  static const Map<String, String> _azureHindiVoices = {
    'Swara (Female)': 'hi-IN-SwaraNeural',
    'Madhur (Male)': 'hi-IN-MadhurNeural',
  };

  static const Map<String, String> _azureEnglishVoices = {
    'Neerja (Female)': 'en-IN-NeerjaNeural',
    'Prabhat (Male)': 'en-IN-PrabhatNeural',
    'Jenny (Female)': 'en-US-JennyNeural',
    'Guy (Male)': 'en-US-GuyNeural',
    'Sonia (Female)': 'en-GB-SoniaNeural',
    'Ryan (Male)': 'en-GB-RyanNeural',
  };

  String? _azureTeluguVoice;
  String? _azureHindiVoice;
  String? _azureEnglishVoice;

  Color get kAccentPurple => ref.read(dynamicAccentColorProvider);
  Color get dynamicAccentColor => ref.watch(dynamicAccentColorProvider);

  // Active Category Tab: 0: Preferences, 1: Emergency SOS, 2: Backup & Info
  int _activeTab = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _syncCodeController = TextEditingController();
    _azureApiKeyController = TextEditingController();
    _azureRegionController = TextEditingController();
    _pageController = PageController(initialPage: _activeTab);
    
    // Synchronously initialize Family Sync Code and Azure details from Hive box
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    if (settingsBox != null && settingsBox.isNotEmpty) {
      final settings = settingsBox.values.first;
      _syncCodeController.text = settings.activeFamilySyncCode;
      _azureApiKeyController.text = settings.activeAzureSpeechSubscriptionKey;
      _azureRegionController.text = settings.activeAzureSpeechRegion;
      
      _azureTeluguVoice = settings.activeAzureSpeechTeluguVoice;
      _azureHindiVoice = settings.activeAzureSpeechHindiVoice;
      _azureEnglishVoice = settings.activeAzureSpeechEnglishVoice;
    }
    
    _checkDefaultDialer();
    _checkSosPermissions();
  }

  @override
  void dispose() {
    _syncCodeController.dispose();
    _azureApiKeyController.dispose();
    _azureRegionController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkSosPermissions() async {
    final callGranted = await Permission.phone.isGranted;
    if (mounted) {
      setState(() {
        _hasCallPhonePermission = callGranted;
      });
    }
  }

  Future<void> _requestSosPermissions() async {
    final status = await Permission.phone.request();

    await _checkSosPermissions();

    if (mounted) {
      final callGranted = status.isGranted;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(callGranted
              ? 'SOS background call permission granted successfully!'
              : 'Permission was not granted. SOS calls may require manual steps.'),
          backgroundColor: callGranted ? kAccentPurple : kSosRed,
        ),
      );
    }
  }

  Future<void> _checkDefaultDialer() async {
    final isDefault = await ref.read(systemCallServiceProvider).isDefaultDialer();
    ref.read(defaultDialerProvider.notifier).state = isDefault;
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
    final currentLang = ref.read(settingsProvider).value?.language;
    if (currentLang == code) return;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
            child: Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10.0,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
                color: textSecondary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 0.5),
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
        width: 44,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: val ? kAccentGreen : const Color(0xFFE0E0EB),
        ),
        padding: const EdgeInsets.all(2.0),
        alignment: val ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: borderColor, width: 0.5))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: textSecondary,
                    fontWeight: FontWeight.w400,
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? kMutedBGDark : const Color(0x0A000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 0.5),
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
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                decoration: BoxDecoration(
                  color: isSelected ? surfaceColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected
                      ? Border.all(color: borderColor, width: 0.5)
                      : Border.all(color: Colors.transparent, width: 0.5),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: isSelected ? dynamicAccentColor : textSecondary,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? dynamicAccentColor : textSecondary,
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

  Widget _buildLayoutSelectorRow(AppSettings settings) {
    final modes = [
      {'code': 'classic', 'title': 'Classic Grid', 'subtitle': '4-column direct call layout (Mockup Theme)', 'icon': Icons.grid_view},
      {'code': 'modern', 'title': 'Modern Dashboard', 'subtitle': 'Multi-action buttons layout with tabs', 'icon': Icons.dashboard},
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: List.generate(modes.length, (index) {
          final m = modes[index];
          final code = m['code'] as String;
          final title = m['title'] as String;
          final subtitle = m['subtitle'] as String;
          final icon = m['icon'] as IconData;
          final isSelected = settings.activeLayoutMode == code;

          return GestureDetector(
            onTap: () async {
              if (settings.activeLayoutMode == code) return;
              await _updateSetting((s) => s.layoutMode = code);
              final ttsService = ref.read(ttsServiceProvider);
              if (code == 'classic') {
                await ttsService.speak('Layout changed to Classic Mode');
              } else {
                await ttsService.speak('Layout changed to Modern Mode');
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(bottom: index < modes.length - 1 ? 10.0 : 0.0),
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              decoration: BoxDecoration(
                color: isSelected ? dynamicAccentColor.withValues(alpha: 0.05) : surfaceColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? dynamicAccentColor : borderColor,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isSelected ? dynamicAccentColor.withValues(alpha: 0.1) : (isDark ? kMutedBGDark : kMutedBGLight),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: isSelected ? dynamicAccentColor : textSecondary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: textSecondary,
                            fontWeight: FontWeight.w400,
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
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: borderColor, width: 0.5),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLanguageSelectorRow(AppSettings settings) {
    final languages = [
      {'code': 'te', 'label': 'తెలుగు'},
      {'code': 'hi', 'label': 'हिन्दी'},
      {'code': 'en', 'label': 'English'},
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: languages.map((lang) {
          final code = lang['code']!;
          final label = lang['label']!;
          final isSelected = settings.language == code;

          return GestureDetector(
            onTap: () => _updateLanguage(code),
            child: Container(
              margin: const EdgeInsets.only(right: 10.0),
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? dynamicAccentColor : borderColor,
                  width: 0.5,
                ),
                color: isSelected ? dynamicAccentColor.withValues(alpha: 0.08) : (isDark ? kMutedBGDark : kMutedBGLight),
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? dynamicAccentColor : textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAccentColorRow(AppSettings settings) {
    final activeHex = settings.activeAccentColorHex;

    final colorHexes = [
      '#534AB7', // Deep Indigo-Violet
      '#1D9E75', // Accent Green
      '#EF9F27', // Accent Amber
      '#E24B4A', // Accent Red
      '#378ADD', // Accent Blue
      '#D4537E', // Accent Pink
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? kBorderDark : kBorderLight;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: colorHexes.map((hex) {
          final parsedColor = getAccentColor(hex);
          final isSelected = activeHex.toLowerCase() == hex.toLowerCase();

          return GestureDetector(
            onTap: () => _updateAccentColor(hex),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: parsedColor,
                border: Border.all(
                  color: isSelected ? (isDark ? Colors.white : Colors.black) : borderColor,
                  width: isSelected ? 2.0 : 0.5,
                ),
              ),
              alignment: Alignment.center,
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _updateAccentColor(String hex) async {
    await _updateSetting((s) => s.accentColorHex = hex);
  }

  Widget _buildAppSettingsSection(AppSettings settings) {
    final isDefaultDialer = ref.watch(defaultDialerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    return Column(
      children: [
        _buildGroup(
          label: 'Layout Style',
          child: _buildLayoutSelectorRow(settings),
        ),
        _buildGroup(
          label: 'Language',
          child: _buildLanguageSelectorRow(settings),
        ),
        _buildGroup(
          label: 'Accent Color',
          child: _buildAccentColorRow(settings),
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
                  val: settings.voiceEnabled,
                  onChanged: (bool value) async {
                    await _updateSetting((s) => s.voiceEnabled = value);
                  },
                ),
              ),
              _buildSettingRow(
                iconBgColor: const Color(0xFFFF8C00),
                icon: Icons.phone_in_talk,
                title: 'Default Phone App',
                subtitle: 'Replace system dialer',
                showDivider: true,
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
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              _buildSettingRow(
                iconBgColor: const Color(0xFF5C5BE8),
                icon: Icons.lock_person_rounded,
                title: 'Accidental Exit Guard',
                subtitle: 'Locks app screen (Kiosk Mode)',
                showDivider: false,
                trailing: _buildTog(
                  val: settings.activeIsKioskModeEnabled,
                  onChanged: (bool value) async {
                    await _updateSetting((s) => s.isKioskModeEnabled = value);
                    if (value) {
                      await ref.read(systemCallServiceProvider).startKioskMode();
                    } else {
                      await ref.read(systemCallServiceProvider).stopKioskMode();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        _buildGroup(
          label: 'Azure Speech Service Settings',
          child: _buildAzureSettingsCard(settings),
        ),
        _buildGroup(
          label: 'Tap Options',
          child: Column(
            children: [
              _buildSettingRow(
                iconBgColor: const Color(0xFF32E08A),
                icon: Icons.touch_app_rounded,
                title: 'Direct Photo Tap',
                subtitle: 'Single-tap photo dials instantly',
                showDivider: false,
                trailing: _buildTog(
                  val: settings.activeDirectTapPreferredAction,
                  onChanged: (bool value) async {
                    await _updateSetting((s) => s.directTapPreferredAction = value);
                  },
                ),
              ),
            ],
          ),
        ),
        _buildGroup(
          label: 'Wellness Monitor',
          child: Column(
            children: [
              _buildSettingRow(
                iconBgColor: const Color(0xFFFF4B6E),
                icon: Icons.accessibility_new_rounded,
                title: 'Inactivity Check-in',
                subtitle: 'Alerts if phone is not touched/moved',
                showDivider: settings.activeWellnessCheckEnabled,
                trailing: _buildTog(
                  val: settings.activeWellnessCheckEnabled,
                  onChanged: (bool value) async {
                    await _updateSetting((s) => s.wellnessCheckEnabled = value);
                  },
                ),
              ),
              if (settings.activeWellnessCheckEnabled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF9999B0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.hourglass_empty_rounded,
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
                              'Inactivity Limit',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                            Text(
                              'Hours before escalation alert',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: textSecondary,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: settings.activeWellnessIntervalHours,
                          items: const [
                            DropdownMenuItem(value: 4, child: Text('4 hours')),
                            DropdownMenuItem(value: 8, child: Text('8 hours')),
                            DropdownMenuItem(value: 12, child: Text('12 hours')),
                            DropdownMenuItem(value: 24, child: Text('24 hours')),
                          ],
                          dropdownColor: surfaceColor,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                          onChanged: (int? value) async {
                            if (value != null) {
                              await _updateSetting((s) => s.wellnessIntervalHours = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAzureSettingsCard(AppSettings settings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'API Configuration',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _azureApiKeyController,
            obscureText: _obscureApiKey,
            style: GoogleFonts.inter(fontSize: 14, color: textPrimary),
            decoration: InputDecoration(
              labelText: 'Azure Subscription Key',
              labelStyle: GoogleFonts.inter(color: textSecondary, fontSize: 13),
              filled: true,
              fillColor: isDark ? kMutedBGDark : kMutedBGLight,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor, width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: dynamicAccentColor, width: 1.0),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureApiKey ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: textSecondary,
                  size: 18,
                ),
                onPressed: () {
                  setState(() {
                    _obscureApiKey = !_obscureApiKey;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _azureRegionController,
            style: GoogleFonts.inter(fontSize: 14, color: textPrimary),
            decoration: InputDecoration(
              labelText: 'Azure Region (e.g. eastus, centralindia)',
              labelStyle: GoogleFonts.inter(color: textSecondary, fontSize: 13),
              filled: true,
              fillColor: isDark ? kMutedBGDark : kMutedBGLight,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor, width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: dynamicAccentColor, width: 1.0),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Telugu Voice Selection',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            decoration: BoxDecoration(
              color: isDark ? kMutedBGDark : kMutedBGLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _azureTeluguVoice,
                isExpanded: true,
                style: GoogleFonts.inter(fontSize: 14, color: textPrimary, fontWeight: FontWeight.w500),
                icon: Icon(Icons.keyboard_arrow_down, color: textSecondary, size: 18),
                dropdownColor: surfaceColor,
                items: _azureTeluguVoices.keys.map((name) {
                  return DropdownMenuItem<String>(
                    value: _azureTeluguVoices[name],
                    child: Text(name),
                  );
                }).toList(),
                onChanged: (String? val) {
                  if (val != null) {
                    setState(() {
                      _azureTeluguVoice = val;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Hindi Voice Selection',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            decoration: BoxDecoration(
              color: isDark ? kMutedBGDark : kMutedBGLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _azureHindiVoice,
                isExpanded: true,
                style: GoogleFonts.inter(fontSize: 14, color: textPrimary, fontWeight: FontWeight.w500),
                icon: Icon(Icons.keyboard_arrow_down, color: textSecondary, size: 18),
                dropdownColor: surfaceColor,
                items: _azureHindiVoices.keys.map((name) {
                  return DropdownMenuItem<String>(
                    value: _azureHindiVoices[name],
                    child: Text(name),
                  );
                }).toList(),
                onChanged: (String? val) {
                  if (val != null) {
                    setState(() {
                      _azureHindiVoice = val;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'English Voice Selection',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            decoration: BoxDecoration(
              color: isDark ? kMutedBGDark : kMutedBGLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _azureEnglishVoice,
                isExpanded: true,
                style: GoogleFonts.inter(fontSize: 14, color: textPrimary, fontWeight: FontWeight.w500),
                icon: Icon(Icons.keyboard_arrow_down, color: textSecondary, size: 18),
                dropdownColor: surfaceColor,
                items: _azureEnglishVoices.keys.map((name) {
                  return DropdownMenuItem<String>(
                    value: _azureEnglishVoices[name],
                    child: Text(name),
                  );
                }).toList(),
                onChanged: (String? val) {
                  if (val != null) {
                    setState(() {
                      _azureEnglishVoice = val;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: dynamicAccentColor,
                    side: BorderSide(color: dynamicAccentColor, width: 1.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _isTestingVoice
                      ? null
                      : () async {
                          FocusScope.of(context).unfocus();
                          final apiKey = _azureApiKeyController.text.trim();
                          final region = _azureRegionController.text.trim();
                          final voiceName = settings.language == 'te'
                              ? (_azureTeluguVoice ?? 'te-IN-ShrutiNeural')
                              : (settings.language == 'hi'
                                  ? (_azureHindiVoice ?? 'hi-IN-SwaraNeural')
                                  : (_azureEnglishVoice ?? 'en-IN-NeerjaNeural'));
                          
                          if (apiKey.isEmpty || region.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter an API Key and Region first.'),
                                backgroundColor: kSosRed,
                              ),
                            );
                            return;
                          }

                          setState(() {
                            _isTestingVoice = true;
                          });

                          try {
                            final error = await ref.read(ttsServiceProvider).testConnection(
                              apiKey: apiKey,
                              region: region,
                              voiceName: voiceName,
                              languageCode: settings.language,
                            );

                            if (!mounted) return;

                            if (error == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Test successful! Azure voice guidance playing...'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } else {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Row(
                                    children: [
                                      const Icon(Icons.error_outline, color: kSosRed),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Connection Failed',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  content: Text(
                                    'Azure returned an error:\n\n$error\n\nPlease check your Subscription Key and Region.',
                                    style: GoogleFonts.inter(),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text(
                                        'OK',
                                        style: GoogleFonts.inter(color: dynamicAccentColor, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isTestingVoice = false;
                              });
                            }
                          }
                        },
                  child: _isTestingVoice
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(dynamicAccentColor),
                          ),
                        )
                      : Text(
                          'Test Connection',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dynamicAccentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () async {
                    FocusScope.of(context).unfocus();
                    final apiKey = _azureApiKeyController.text.trim();
                    final region = _azureRegionController.text.trim();
                    await _updateSetting((s) {
                      s.azureSpeechSubscriptionKey = apiKey;
                      s.azureSpeechRegion = region;
                      s.azureSpeechTeluguVoice = _azureTeluguVoice;
                      s.azureSpeechHindiVoice = _azureHindiVoice;
                      s.azureSpeechEnglishVoice = _azureEnglishVoice;
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Azure Speech settings saved successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: Text(
                    'Save Settings',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSosDot(bool active) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF1D9E75) : const Color(0xFFE24B4A),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildSosPermissionRow({
    required bool granted,
    required String label,
    bool showDivider = true,
    Color? textColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: granted ? const Color(0xFF1D9E75) : const Color(0xFFE24B4A),
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
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textColor ?? textPrimary,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: currentValue,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down, color: textSecondary, size: 18),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
              hint: Text(
                'None — disabled',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
              dropdownColor: surfaceColor,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSharingRow(AppSettings settings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isDark ? kSurfaceDark : kSurfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: dynamicAccentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
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
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Send GPS in text alerts',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          _buildTog(
            val: settings.sosLocationShare,
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
              await _updateSetting((s) => s.sosLocationShare = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSosSection(AsyncValue<List<Contact>> contactsAsync, AppSettings settings) {
    final hasAllPermissions = _hasCallPhonePermission;

    return Column(
      children: [
        // SOS status card
        Container(
          margin: const EdgeInsets.only(bottom: 14.0),
          decoration: BoxDecoration(
            color: hasAllPermissions
                ? const Color(0xFFE1F5EE) // green tint
                : const Color(0xFFFCEBEB), // red tint
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasAllPermissions ? const Color(0xFF1D9E75) : const Color(0xFFE24B4A),
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  _buildSosDot(hasAllPermissions),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasAllPermissions ? 'SOS Background — Active' : 'SOS Background — Inactive',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: hasAllPermissions ? const Color(0xFF0F6E56) : const Color(0xFF791F1F),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSosPermissionRow(
                granted: _hasCallPhonePermission,
                label: 'Direct Phone Call (CALL_PHONE)',
                showDivider: false,
                textColor: hasAllPermissions ? const Color(0xFF0F6E56) : const Color(0xFF791F1F),
              ),
            ],
          ),
        ),

        // Grant button if permissions are missing
        if (!hasAllPermissions)
          Padding(
            padding: const EdgeInsets.only(bottom: 14.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE24B4A),
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _requestSosPermissions,
              icon: const Icon(Icons.security_rounded, size: 16),
              label: Text(
                'Grant SOS Permissions',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
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
                currentValue: settings.sosContactId,
                items: dropdownItems,
                onChanged: (String? newValue) async {
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
                    currentValue: settings.sosMsgContactId1,
                    items: dropdownItems,
                    onChanged: (String? newValue) async {
                      await _updateSetting((s) => s.sosMsgContactId1 = newValue);
                    },
                  ),
                  _buildSosDropdown(
                    label: 'Message Recipient 2',
                    currentValue: settings.sosMsgContactId2,
                    items: dropdownItems,
                    onChanged: (String? newValue) async {
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
        _buildLocationSharingRow(settings),
      ],
    );
  }

  Widget _buildImportExportSection(AppSettings settings) {
    final validCount = _parsedRows?.where((r) => r.errors.isEmpty).length ?? 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    final mutedBG = isDark ? kMutedBGDark : kMutedBGLight;

    return Column(
      children: [
        _buildGroup(
          label: 'Remote Cloud Sync',
          child: Column(
            children: [
              _buildSettingRow(
                iconBgColor: dynamicAccentColor,
                icon: Icons.sync,
                title: 'Enable Cloud Sync',
                subtitle: 'Sync contacts in real-time',
                trailing: _buildTog(
                  val: settings.activeIsSyncEnabled,
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
                          backgroundColor: surfaceColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: borderColor, width: 0.5),
                          ),
                          title: Text(
                            'Upload Contacts?',
                            style: GoogleFonts.inter(
                              color: textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          content: Text(
                            'Do you want to upload your existing local contacts to the cloud database under this code?',
                            style: GoogleFonts.inter(
                              color: textSecondary,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(
                                'Keep Remote Only',
                                style: GoogleFonts.inter(color: dynamicAccentColor),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: dynamicAccentColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Upload Local Contacts',
                                style: GoogleFonts.inter(),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (upload == null) {
                        return;
                      }

                      if (upload == true) {
                        setState(() => _isProcessing = true);
                        try {
                          final code = _syncCodeController.text.trim();
                          await ref.read(firebaseSyncServiceProvider).uploadAllLocalContacts(forceFamilyCode: code);
                          
                          await _updateSetting((s) {
                            s.isSyncEnabled = true;
                            s.familySyncCode = code;
                          });

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Local contacts successfully uploaded to Firebase!'),
                                backgroundColor: kAccentGreen,
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
                        await _updateSetting((s) {
                          s.isSyncEnabled = true;
                          s.familySyncCode = _syncCodeController.text.trim();
                        });
                      }
                    } else {
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
                      'FAMILY SYNC CODE',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: textSecondary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _syncCodeController,
                      enabled: !settings.activeIsSyncEnabled,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. family_smith_123',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 14,
                          color: textSecondary.withValues(alpha: 0.6),
                        ),
                        filled: true,
                        fillColor: settings.activeIsSyncEnabled ? mutedBG : surfaceColor,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderColor, width: 0.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderColor, width: 0.5),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: borderColor.withValues(alpha: 0.5), width: 0.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: dynamicAccentColor, width: 1.0),
                        ),
                      ),
                      onChanged: (value) async {
                        await _updateSetting((s) => s.familySyncCode = value.trim());
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the same code on both phones. Turn off sync to edit the code.',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: textSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (settings.activeIsSyncEnabled) ...[
                      const SizedBox(height: 16),
                      Divider(height: 1, color: borderColor, thickness: 0.5),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? kGreenTintDark.withValues(alpha: 0.15) : kGreenTintLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isDark ? kGreenIconDark.withValues(alpha: 0.2) : kGreenIconLight.withValues(alpha: 0.2), width: 0.5),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isDark ? kGreenIconDark : kGreenIconLight,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Live Sync Connected & Active',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? kGreenIconDark : kGreenIconLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Updates on this phone or the Web Dashboard sync automatically in real-time.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(height: 1, color: borderColor, thickness: 0.5),
                      const SizedBox(height: 16),
                      Text(
                        'MANUAL CLOUD ACTIONS',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? kMutedBGDark : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor, width: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Send Contacts to Cloud',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 96,
                                  height: 28,
                                  child: ElevatedButton(
                                    onPressed: _isProcessing ? null : () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: surfaceColor,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            side: BorderSide(color: borderColor, width: 0.5),
                                          ),
                                          title: Text(
                                            'Send Contacts to Cloud?',
                                            style: GoogleFonts.inter(
                                              color: textPrimary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          content: Text(
                                            'This will overwrite all remote contacts in the cloud with your current local contacts. This cannot be undone.',
                                            style: GoogleFonts.inter(color: textSecondary),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              child: Text('Cancel', style: GoogleFonts.inter(color: dynamicAccentColor)),
                                            ),
                                            ElevatedButton(
                                              onPressed: () => Navigator.pop(context, true),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: dynamicAccentColor,
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                              child: Text('Send Now', style: GoogleFonts.inter()),
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
                                                backgroundColor: kAccentGreen,
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
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: dynamicAccentColor,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      'Send Now',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sends all contacts on this phone to the cloud database, overwriting what is currently stored.',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: textSecondary,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? kMutedBGDark : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor, width: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Fetch Contacts from Cloud',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 96,
                                  height: 28,
                                  child: OutlinedButton(
                                    onPressed: _isProcessing ? null : () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: surfaceColor,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            side: BorderSide(color: borderColor, width: 0.5),
                                          ),
                                          title: Text(
                                            'Fetch Contacts from Cloud?',
                                            style: GoogleFonts.inter(
                                              color: textPrimary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          content: Text(
                                            'This will delete all local contacts on this phone and overwrite them with the contacts from the cloud. This cannot be undone.',
                                            style: GoogleFonts.inter(color: textSecondary),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              child: Text('Cancel', style: GoogleFonts.inter(color: dynamicAccentColor)),
                                            ),
                                            ElevatedButton(
                                              onPressed: () => Navigator.pop(context, true),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: dynamicAccentColor,
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                              child: Text('Fetch Now', style: GoogleFonts.inter()),
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
                                                backgroundColor: kAccentGreen,
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
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: textPrimary,
                                      side: BorderSide(color: borderColor, width: 0.5),
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      'Fetch Now',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Downloads contacts from the cloud and overwrites the contact list on this phone.',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: textSecondary,
                                fontWeight: FontWeight.w400,
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
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
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
                              color: isDark ? kPurpleTintDark : kPurpleTintLight,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: dynamicAccentColor, width: 0.5),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle_outline, color: dynamicAccentColor, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Save $validCount',
                                  style: GoogleFonts.inter(
                                    color: dynamicAccentColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
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
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor, width: 0.5),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.table_chart_outlined, color: textSecondary, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Export CSV',
                                style: GoogleFonts.inter(
                                  color: textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
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
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor, width: 0.5),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.settings_backup_restore, color: textSecondary, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Backup JSON',
                                style: GoogleFonts.inter(
                                  color: textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
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
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor, width: 0.5),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_upload_outlined, color: dynamicAccentColor, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Backup ZIP',
                                style: GoogleFonts.inter(
                                  color: textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
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
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor, width: 0.5),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cloud_download_outlined, color: kAccentGreen, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Restore ZIP',
                                style: GoogleFonts.inter(
                                  color: textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
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
        const SizedBox(height: 14),
        _buildCaregiverWebAccessGroup(settings),
        const SizedBox(height: 14),
        _buildUserGuideGroup(),
        const SizedBox(height: 14),
        _buildGroup(
          label: 'Info & Policies',
          child: Column(
            children: [
              _buildSettingRow(
                iconBgColor: dynamicAccentColor,
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                subtitle: 'View our user data & privacy practices',
                showDivider: false,
                trailing: GestureDetector(
                  onTap: () async {
                    final uri = Uri.parse('https://webdashboard-liart.vercel.app/privacy.html');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? kMutedBGDark : const Color(0xFFF2F2F8),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderColor, width: 0.5),
                    ),
                    child: Text(
                      'View',
                      style: GoogleFonts.inter(
                        color: dynamicAccentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
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

  Widget _buildHelpItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget content,
    bool showDivider = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;

    return Container(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: borderColor, width: 0.5))
            : null,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 16,
            ),
          ),
          title: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          iconColor: textSecondary,
          collapsedIconColor: textSecondary,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          expandedAlignment: Alignment.topLeft,
          children: [content],
        ),
      ),
    );
  }

  Widget _buildCaregiverWebAccessGroup(AppSettings settings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;

    final badgeBg = isDark ? kBlueTintDark : kBlueTintLight;
    final badgeIcon = isDark ? kBlueIconDark : kBlueIconLight;

    return _buildGroup(
      label: 'Caregiver Web Access',
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.computer_rounded,
                    color: badgeIcon,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Remote Web Dashboard',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'https://webdashboard-liart.vercel.app',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: badgeIcon,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Caregivers can add/edit contacts and monitor wellness status from any computer or mobile browser using this URL.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse('https://webdashboard-liart.vercel.app');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 14, color: Colors.white),
                    label: Text(
                      'Open Web',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: dynamicAccentColor,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: 'https://webdashboard-liart.vercel.app'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Dashboard URL copied to clipboard!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    icon: Icon(Icons.copy_rounded, size: 14, color: dynamicAccentColor),
                    label: Text(
                      'Copy Link',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: dynamicAccentColor,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: dynamicAccentColor,
                      side: BorderSide(color: borderColor, width: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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

  Widget _buildUserGuideGroup() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;

    return _buildGroup(
      label: 'User Guide & Help',
      child: Column(
        children: [
          _buildHelpItem(
            icon: Icons.emergency_share_rounded,
            iconColor: kAccentPink,
            title: 'Emergency SOS',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How it works:',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '• To trigger SOS, press and hold the SOS button on the home screen or tap it 3 times quickly.\n'
                  '• A countdown of 5 seconds will begin (allowing you to cancel if it was accidental).\n'
                  '• If not cancelled, the app will automatically open your phone dialer to call your primary SOS contact.\n'
                  '• It will also prefill an SMS text message with your current GPS location coordinates to send to your emergency contacts.',
                  style: GoogleFonts.inter(fontSize: 12, color: textSecondary, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  'Permissions needed:',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Phone: Required to start the phone call automatically.\n'
                  '• SMS: Required to prefill the emergency text alert with your location coordinates.',
                  style: GoogleFonts.inter(fontSize: 12, color: textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
          _buildHelpItem(
            icon: Icons.accessibility_new_rounded,
            iconColor: kAccentAmber,
            title: 'Wellness Inactivity Check',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What is Inactivity Check-in?',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '• This feature monitors if the phone is being touched or moved.\n'
                  '• If the phone remains completely still (no movement or screen taps) for your chosen interval (e.g. 8 hours), the app assumes you might be inactive.\n'
                  '• An on-screen alert will prompt you to confirm you are okay.\n'
                  '• If you do not respond to the check-in prompt within 5 minutes, an escalation alert is triggered, and your wellness status is synced to the Caregiver Web Dashboard.',
                  style: GoogleFonts.inter(fontSize: 12, color: textSecondary, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  'Setting up:',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Enable "Inactivity Check-in" in settings and choose the inactivity limit (4, 8, 12, or 24 hours).',
                  style: GoogleFonts.inter(fontSize: 12, color: textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
          _buildHelpItem(
            icon: Icons.cloud_sync_rounded,
            iconColor: dynamicAccentColor,
            title: 'Family Cloud Sync',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connecting Family Members:',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '• To sync contacts between two devices or with the web dashboard, use the "Family Sync Code".\n'
                  '• Enter the exact same code on both devices (e.g. smith_family_2026).\n'
                  '• Enable "Cloud Sync" on both devices. The contact list will keep itself in sync automatically in real-time.',
                  style: GoogleFonts.inter(fontSize: 12, color: textSecondary, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manual Cloud Sync:',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '• "Send Contacts to Cloud": Overwrites the cloud database with your current local contacts.\n'
                  '• "Fetch Contacts from Cloud": Clears your local list and pulls all contacts from the cloud database.',
                  style: GoogleFonts.inter(fontSize: 12, color: textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
          _buildHelpItem(
            icon: Icons.grid_view,
            iconColor: kAccentBlue,
            title: 'Speed-Dial Layout Modes',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose the best style for the user:',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Classic Grid: Displays a simple, oversized grid of 4 contacts per screen with photos. Perfect for elderly users or those who want a simple, one-touch dial interface.\n'
                  '• Modern Dashboard: A clean dashboard displaying contacts in categorized tabs with quick-action buttons for phone call, WhatsApp, and voice guidance.',
                  style: GoogleFonts.inter(fontSize: 12, color: textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
          _buildHelpItem(
            icon: Icons.touch_app_rounded,
            iconColor: kAccentGreen,
            title: 'Direct Photo Tap',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How to dial quickly:',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '• With "Direct Photo Tap" enabled, tapping a contact\'s photo from the main screen instantly makes a phone call.\n'
                  '• If disabled, tapping a contact\'s photo will open their detailed contact card first (allowing you to choose between standard call, WhatsApp, or voice reading).',
                  style: GoogleFonts.inter(fontSize: 12, color: textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
          _buildHelpItem(
            icon: Icons.lock_person_rounded,
            iconColor: kAccentPink,
            title: 'Exit Guard (Kiosk Mode)',
            showDivider: false,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prevent Accidental App Closing:',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '• For users who get confused or accidentally close apps, enable "Accidental Exit Guard".\n'
                  '• When enabled, the app locks itself in the foreground. Pressing home/back keys will not close the app.\n'
                  '• To exit settings or close the app, an Admin Pin (default: 1234) must be entered, keeping the user safe inside the simplified interface.',
                  style: GoogleFonts.inter(fontSize: 12, color: textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;

    if (_parsedRows == null || _parsedRows!.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 0.5),
        ),
        color: surfaceColor,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text(
              'Selected CSV file is empty.',
              style: GoogleFonts.inter(color: textSecondary),
            ),
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

        final boxBg = hasErrors 
            ? (isDark ? kRedTintDark.withValues(alpha: 0.15) : kRedTintLight)
            : surfaceColor;
        final boxBorder = hasErrors
            ? (isDark ? kRedIconDark.withValues(alpha: 0.3) : kRedIconLight.withValues(alpha: 0.3))
            : borderColor;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: boxBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: boxBorder,
              width: 0.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasErrors ? Icons.error_outline : Icons.check_circle_outline,
                color: hasErrors ? kAccentRed : kAccentGreen,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name ?? '[No Name]',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: hasErrors && row.name == null ? kAccentRed : textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Phone: ${row.phone ?? "N/A"}',
                      style: GoogleFonts.inter(fontSize: 13, color: textSecondary, fontWeight: FontWeight.w500),
                    ),
                    if (row.whatsapp != null && row.whatsapp!.isNotEmpty)
                      Text(
                        'WhatsApp: ${row.whatsapp}',
                        style: GoogleFonts.inter(fontSize: 13, color: textSecondary, fontWeight: FontWeight.w500),
                      ),
                    if (row.photoPath != null && row.photoPath!.isNotEmpty)
                      Text(
                        'Photo: ${row.photoPath}',
                        style: GoogleFonts.inter(fontSize: 13, color: textSecondary, fontWeight: FontWeight.w500),
                      ),
                    if (hasErrors) ...[
                      const SizedBox(height: 8),
                      ...row.errors.map(
                        (err) => Padding(
                          padding: const EdgeInsets.only(bottom: 2.0),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 14, color: kAccentRed),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  err,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: kAccentRed,
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
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
      next.whenData((settings) {
        if (_syncCodeController.text != settings.activeFamilySyncCode) {
          _syncCodeController.text = settings.activeFamilySyncCode;
        }
        if (_azureApiKeyController.text != settings.activeAzureSpeechSubscriptionKey) {
          _azureApiKeyController.text = settings.activeAzureSpeechSubscriptionKey;
        }
        if (_azureRegionController.text != settings.activeAzureSpeechRegion) {
          _azureRegionController.text = settings.activeAzureSpeechRegion;
        }
        if (_azureTeluguVoice != settings.activeAzureSpeechTeluguVoice) {
          _azureTeluguVoice = settings.activeAzureSpeechTeluguVoice;
        }
        if (_azureHindiVoice != settings.activeAzureSpeechHindiVoice) {
          _azureHindiVoice = settings.activeAzureSpeechHindiVoice;
        }
        if (_azureEnglishVoice != settings.activeAzureSpeechEnglishVoice) {
          _azureEnglishVoice = settings.activeAzureSpeechEnglishVoice;
        }
      });
    });

    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value ?? AppSettings(adminPin: '1234');
    final contactsAsync = ref.watch(contactsStreamProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: isDark ? kSurfaceDark : const Color(0xFFF7F7FA),
      appBar: AppBar(
        title: Text(
          'App Settings',
          style: GoogleFonts.inter(
            color: textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 17.0,
          ),
        ),
        backgroundColor: surfaceColor.withValues(alpha: 0.9),
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
                      style: GoogleFonts.inter(
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
                            _buildAppSettingsSection(settings),
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
                            _buildSosSection(contactsAsync, settings),
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
                            _buildImportExportSection(settings),
                            if (_parsedRows != null) ...[
                              const SizedBox(height: 20),
                              Text(
                                'Preview File: $_selectedFileName',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
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
