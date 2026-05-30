import 'dart:io';
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
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/calling/screens/calling_screen.dart';
import 'package:easyconnect/features/calling/services/system_call_service.dart';

import 'package:easyconnect/features/contacts/widgets/contact_form_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}


class _AdminScreenState extends ConsumerState<AdminScreen> {
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
  bool _isDefaultDialer = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkDefaultDialer();
  }

  Future<void> _checkDefaultDialer() async {
    final isDefault = await ref.read(systemCallServiceProvider).isDefaultDialer();
    ref.read(defaultDialerProvider.notifier).state = isDefault;
    if (mounted) {
      setState(() {
        _isDefaultDialer = isDefault;
      });
    }
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
      debugPrint('Error in AdminScreen._updateSetting: $e');
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

  Future<void> _confirmDelete(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Are you sure you want to delete ${contact.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: kSosRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(contactRepositoryProvider).deleteContact(contact.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${contact.name} deleted'), backgroundColor: kCallGreen),
        );
      }
    }
  }

  void _simulateIncomingCall(Contact contact) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallingScreen(
          contact: contact,
          initialState: CallingState.incoming,
        ),
      ),
    );
  }

  void _showContactForm([Contact? contact]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ContactFormSheet(contact: contact),
    );
  }

  Future<void> _importFromDevice() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contacts permission is required to import from device'),
            backgroundColor: kSosRed,
          ),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);
    try {
      const MethodChannel channel = MethodChannel('com.easyconnect.app/calling');
      final List<dynamic>? rawContacts = await channel.invokeMethod<List<dynamic>>('getDeviceContacts');
      
      setState(() => _isProcessing = false);

      if (rawContacts == null || rawContacts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No contacts found on device')),
          );
        }
        return;
      }

      final List<Map<String, String>> deviceContacts = rawContacts.map((c) {
        final map = Map<dynamic, dynamic>.from(c as Map);
        return {
          'name': map['name']?.toString() ?? '',
          'phoneNumber': map['phoneNumber']?.toString() ?? '',
        };
      }).toList();

      if (mounted) {
        _showDeviceContactsImportDialog(deviceContacts);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read device contacts: $e'), backgroundColor: kSosRed),
        );
      }
    }
  }

  void _showDeviceContactsImportDialog(List<Map<String, String>> contacts) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _DeviceContactsImportDialog(
          contacts: contacts,
          onImport: (selectedContacts) async {
            if (selectedContacts.isEmpty) return;

            final messenger = ScaffoldMessenger.of(context);
            setState(() => _isProcessing = true);
            try {
              final repo = ref.read(contactRepositoryProvider);
              final existing = await repo.getAllContacts();
              int maxPosition = existing.isEmpty
                  ? -1
                  : existing.map((c) => c.positionIndex).reduce((a, b) => a > b ? a : b);

              for (final c in selectedContacts) {
                maxPosition++;
                final newContact = Contact(
                  id: const Uuid().v4(),
                  name: c['name'] ?? '',
                  phoneNumber: c['phoneNumber'] ?? '',
                  positionIndex: maxPosition,
                );
                await repo.addContact(newContact);
              }

              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Successfully imported ${selectedContacts.length} contacts!'),
                    backgroundColor: kCallGreen,
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to import: $e'),
                    backgroundColor: kSosRed,
                  ),
                );
              }
            } finally {
              if (mounted) setState(() => _isProcessing = false);
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.white,
        foregroundColor: kTextDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: kTextDark, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 12.0,
                bottom: 16.0 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SECTION 1: Contacts
                  _buildSectionHeader('Contacts'),
                  const SizedBox(height: 12),
                  _buildContactsSection(contactsAsync),
                  const SizedBox(height: 28),

                  // SECTION 2: App Settings
                  _buildSectionHeader('App Settings'),
                  const SizedBox(height: 12),
                  _buildAppSettingsSection(contactsAsync),
                  const SizedBox(height: 28),

                  // SECTION 3: Backup & Import
                  _buildSectionHeader('Backup & Import'),
                  const SizedBox(height: 12),
                  _buildImportExportSection(),
                  
                  if (_parsedRows != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Preview File: $_selectedFileName',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _buildPreviewList(),
                  ],
                  const SizedBox(height: 28),

                  // SECTION 4: About & Privacy
                  _buildSectionHeader('About & Privacy'),
                  const SizedBox(height: 12),
                  _buildAboutSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18.0,
        fontWeight: FontWeight.bold,
        color: kTextDark,
      ),
    );
  }

  Widget _buildAboutSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.grey.shade50,
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Rosy circular frame with a glowing red heart icon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2), // Premium rose pink tone
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFECDD3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFDA4AF).withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.favorite_rounded,
                color: Color(0xFFF43F5E), // Rose red heart
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
                    color: Color(0xFFF43F5E), // Vibrant rose-red highlight
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
                    color: kAccentPurple, // Purple accent for Mom
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'An offline, high-privacy calling application designed to make communication simple and accessible.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          // Privacy & Terms Row
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
                        borderRadius: BorderRadius.circular(24),
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
                        borderRadius: BorderRadius.circular(24),
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
                  borderRadius: BorderRadius.circular(24),
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
            'EasyConnect v1.0.0 — Offline-First & Private',
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
                          color: kTextDark,
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
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kTextDark),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'EasyConnect is designed specifically for elderly and illiterate users to have a completely accessible, foolproof phone calling experience. We believe privacy is a fundamental human right. Because this app is built for family and loved ones, it works entirely offline with zero tracking.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '1. Zero Cloud Synchronization',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'EasyConnect does NOT send your contacts list, call logs, phone numbers, or any user activity to external servers or cloud providers. All data remains inside the private local sandbox on your physical device.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '2. Completely Local Telephony & Monitoring',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'By registering as a default phone handler, the app monitors active call states purely locally. It uses Android native services to instantly display the large Accept/Decline overlays without recording, uploading, or storing audio conversations.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '3. On-Device Voice Guidance (TTS)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'All spoken names and voice notifications are processed entirely on-device using Android\'s local system text-to-speech framework. No speech profiles or audio clips are sent to third parties.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '4. Emergency SOS Alerts',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'When the SOS button is triggered, the app compiles your current GPS location and sends a text message strictly through your cellular SIM card to the emergency contact designated in settings. This information is sent directly to your family member with no intermediate storage.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '5. Security & Device Sandbox',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark),
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
                          borderRadius: BorderRadius.circular(24),
                        ),
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
                          color: kTextDark,
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
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kTextDark),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'By installing and using EasyConnect, you agree to these terms. This app is designed to replace your system phone dialer and SMS client solely to provide enhanced accessibility.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '2. Default Dialer & Permissions',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'For the application to show large incoming call sheets and process dial requests, you must set EasyConnect as the Default Phone App and grant background overlay permissions. The application cannot process phone calls otherwise.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '3. Emergency SOS Triggers',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The SOS emergency trigger relies on standard cellular networks to place phone calls and send background SMS alerts containing GPS coordinates. Accuracy depends on your device\'s hardware GPS module and cellular coverage. EasyConnect does not guarantee real-time delivery if network signals are absent.',
                          style: TextStyle(fontSize: 15, color: Colors.grey.shade800, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '4. Safe Usage & Liability',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kTextDark),
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
                          borderRadius: BorderRadius.circular(24),
                        ),
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


  Widget _buildContactsSection(AsyncValue<List<Contact>> contactsAsync) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
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
                      ),
                      onPressed: () => _showContactForm(),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text(
                        'Add Contact',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: kMinTouchTarget,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kCallGreen,
                        side: const BorderSide(color: kCallGreen, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      onPressed: _importFromDevice,
                      icon: const Icon(Icons.contact_phone_outlined),
                      label: const Text(
                        'Import Device',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            contactsAsync.when(
              data: (contacts) {
                if (contacts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Text('No contacts found. Use the button above to add.'),
                    ),
                  );
                }

                // Sorting is verified to be done on the repository stream,
                // but list must be mutable to perform inline modifications
                final sortedContacts = List<Contact>.from(contacts);

                return ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sortedContacts.length,
                  onReorderItem: (oldIndex, newIndex) async {
                    final item = sortedContacts.removeAt(oldIndex);
                    sortedContacts.insert(newIndex, item);
                    
                    final orderedIds = sortedContacts.map((c) => c.id).toList();
                    await ref.read(contactRepositoryProvider).reorderContacts(orderedIds);
                  },
                  itemBuilder: (context, index) {
                    final contact = sortedContacts[index];
                    return Card(
                      key: ValueKey(contact.id),
                      elevation: 0,
                      color: Colors.grey.shade50,
                      margin: const EdgeInsets.symmetric(vertical: 4.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.only(left: 12.0, right: 8.0),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey.shade300,
                          backgroundImage: contact.photoPath != null && contact.photoPath!.isNotEmpty
                              ? FileImage(File(contact.photoPath!))
                              : null,
                          child: contact.photoPath == null || contact.photoPath!.isEmpty
                              ? const Icon(Icons.person, color: Colors.grey, size: 28)
                              : null,
                        ),
                        title: Text(
                          contact.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
                        ),
                        subtitle: Text(contact.phoneNumber),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.phone_callback, color: kCallGreen),
                              tooltip: 'Simulate Incoming Call',
                              onPressed: () => _simulateIncomingCall(contact),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: kVideoBlue),
                              onPressed: () => _showContactForm(contact),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: kSosRed),
                              onPressed: () => _confirmDelete(contact),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle, color: Colors.grey, size: 28),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: CircularProgressIndicator(),
              ),
              error: (error, stack) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Text('Error loading contacts: $error', style: const TextStyle(color: kSosRed)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportExportSection() {
    final validCount = _parsedRows?.where((r) => r.errors.isEmpty).length ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
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
                      ),
                      onPressed: _pickCSV,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text(
                        'Import from CSV',
                        style: TextStyle(fontWeight: FontWeight.bold),
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
                          backgroundColor: kCallGreen.withValues(alpha: 0.2),
                          foregroundColor: kCallGreen,
                          side: const BorderSide(color: kCallGreen),
                        ),
                        onPressed: _importContacts,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(
                          'Import $validCount Rows',
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: kTextDark,
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      onPressed: _exportCSV,
                      icon: const Icon(Icons.table_chart_outlined),
                      label: const Text(
                        'Export as CSV',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: kMinTouchTarget,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: kTextDark,
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      onPressed: _exportJSON,
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text(
                        'Export as JSON Backup',
                        style: TextStyle(fontWeight: FontWeight.bold),
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

  Widget _buildAppSettingsSection(AsyncValue<List<Contact>> contactsAsync) {
    final isDefaultDialer = ref.watch(defaultDialerProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Language Selector
            const Text(
              'Language Selector',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
            ),
            const SizedBox(height: 12),
            _buildLanguageSelectorRow(),
            const Divider(height: 32),

            // Voice Guidance Toggle
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: kCallGreen,
              title: const Text(
                'Voice Guidance',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
              ),
              subtitle: const Text('Audible confirmation prompts for all call inputs.'),
              value: _voiceEnabled,
              onChanged: (bool value) async {
                setState(() => _voiceEnabled = value);
                await _updateSetting((s) => s.voiceEnabled = value);
              },
            ),
            const Divider(height: 32),

            // SOS Contact Dropdown Picker (For Call)
            const Text(
              'SOS Emergency Contact (To CALL)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
            ),
            const SizedBox(height: 8),
            contactsAsync.when(
              data: (contacts) {
                return DropdownButtonFormField<String?>(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            const SizedBox(height: 16),

            // SOS Message Contact 1 Dropdown Picker
            const Text(
              'SOS Message Recipient 1 (To Text)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
            ),
            const SizedBox(height: 8),
            contactsAsync.when(
              data: (contacts) {
                return DropdownButtonFormField<String?>(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            const SizedBox(height: 16),

            // SOS Message Contact 2 Dropdown Picker
            const Text(
              'SOS Message Recipient 2 (To Text)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
            ),
            const SizedBox(height: 8),
            contactsAsync.when(
              data: (contacts) {
                return DropdownButtonFormField<String?>(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            const Divider(height: 32),

            // SOS Location Sharing Toggle
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: kCallGreen,
              title: const Text(
                'SOS Location Sharing',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
              ),
              subtitle: const Text('Sends GPS coordinates inside text alerts on SOS triggers.'),
              value: _sosLocationShare,
              onChanged: (bool value) async {
                setState(() => _sosLocationShare = value);
                await _updateSetting((s) => s.sosLocationShare = value);
              },
            ),
            const Divider(height: 32),

            // Default Phone App Integration
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Default Phone App',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0),
              ),
              subtitle: Text(
                isDefaultDialer
                    ? 'EasyConnect is active as the default phone call screen.'
                    : 'Allows EasyConnect to replace the native system dialer for normal phone calls.',
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
                  ),
                  onPressed: isDefaultDialer
                      ? null
                      : () async {
                          await ref.read(systemCallServiceProvider).requestDefaultDialer();
                          // Poll status to update UI when user returns
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
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: isSelected
                      ? kCallGreen.withValues(alpha: 0.1)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? kCallGreen : Colors.grey.shade300,
                    width: isSelected ? 2.5 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? kCallGreen : kTextDark,
                      ),
                    ),
                    Text(
                      lang['sub']!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? kCallGreen.withValues(alpha: 0.8)
                            : Colors.grey,
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


  Widget _buildPreviewList() {
    if (_parsedRows == null || _parsedRows!.isEmpty) {
      return const Card(
        child: Padding(
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
            color: hasErrors ? kStopRed.withValues(alpha: 0.1) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasErrors ? kStopRed.withValues(alpha: 0.4) : Colors.grey.shade300,
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
                        color: hasErrors && row.name == null ? Colors.red.shade900 : kTextDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Phone: ${row.phone ?? "N/A"}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    if (row.whatsapp != null && row.whatsapp!.isNotEmpty)
                      Text(
                        'WhatsApp: ${row.whatsapp}',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                      ),
                    if (row.photoPath != null && row.photoPath!.isNotEmpty)
                      Text(
                        'Photo: ${row.photoPath}',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
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
}

class _DeviceContactsImportDialog extends StatefulWidget {
  final List<Map<String, String>> contacts;
  final Function(List<Map<String, String>>) onImport;

  const _DeviceContactsImportDialog({
    required this.contacts,
    required this.onImport,
  });

  @override
  State<_DeviceContactsImportDialog> createState() => _DeviceContactsImportDialogState();
}

class _DeviceContactsImportDialogState extends State<_DeviceContactsImportDialog> {
  final List<Map<String, String>> _selected = [];
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Filter list by name or phone
    final filtered = widget.contacts.where((c) {
      final name = c['name']?.toLowerCase() ?? '';
      final phone = c['phoneNumber']?.toLowerCase() ?? '';
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();

    final allFilteredSelected = filtered.isNotEmpty && filtered.every((c) => _selected.contains(c));

    return AlertDialog(
      title: const Text('Select Contacts to Import'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400, // Explicit height to prevent layouts issues
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search Input
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or number...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
            const SizedBox(height: 8),
            // Select All Checkbox
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Select All Search Results',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              value: allFilteredSelected,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    for (final c in filtered) {
                      if (!_selected.contains(c)) {
                        _selected.add(c);
                      }
                    }
                  } else {
                    for (final c in filtered) {
                      _selected.remove(c);
                    }
                  }
                });
              },
            ),
            const Divider(height: 12),
            // Contacts checklist
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No contacts found matching search'),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final contact = filtered[index];
                        final isSelected = _selected.contains(contact);

                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            contact['name'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          subtitle: Text(contact['phoneNumber'] ?? ''),
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selected.add(contact);
                              } else {
                                _selected.remove(contact);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kCallGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _selected.isEmpty
              ? null
              : () {
                  widget.onImport(_selected);
                  Navigator.pop(context);
                },
          child: Text('Import (${_selected.length})'),
        ),
      ],
    );
  }
}
