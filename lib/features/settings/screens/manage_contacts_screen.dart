import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/features/contacts/widgets/contact_form_sheet.dart';
import 'package:easyconnect/features/calling/screens/calling_screen.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:google_fonts/google_fonts.dart';

class ManageContactsScreen extends ConsumerStatefulWidget {
  const ManageContactsScreen({super.key});

  @override
  ConsumerState<ManageContactsScreen> createState() => _ManageContactsScreenState();
}

class _ManageContactsScreenState extends ConsumerState<ManageContactsScreen> {
  bool _isProcessing = false;
  String? _expandedContactId;

  Color get kAccentPurple => ref.watch(dynamicAccentColorProvider);

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
          accentColor: kAccentPurple,
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
                    backgroundColor: kAccentPurple,
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

  Future<void> _confirmDelete(Contact contact) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 0.5),
        ),
        title: Text(
          'Delete Contact',
          style: GoogleFonts.inter(
            color: textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete ${contact.name}?',
          style: GoogleFonts.inter(color: textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: kAccentPurple),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: kSosRed),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(contactRepositoryProvider).deleteContact(contact.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${contact.name} deleted'), backgroundColor: kAccentPurple),
        );
      }
    }
  }

  Color _parseHexColor(String hex) {
    String cleanHex = hex.replaceAll('#', '');
    if (cleanHex.length == 6) {
      cleanHex = 'FF$cleanHex';
    }
    return Color(int.parse(cleanHex, radix: 16));
  }

  Gradient _getContactGradient(Contact contact) {
    Color baseColor;
    try {
      baseColor = _parseHexColor(contact.colorTheme);
    } catch (_) {
      baseColor = const Color(0xFF6C6BF8);
    }

    final hsl = HSLColor.fromColor(baseColor);
    final hue2 = (hsl.hue + 30) % 360;
    final saturation2 = (hsl.saturation + 0.1).clamp(0.0, 1.0);
    final lightness2 = (hsl.lightness + 0.1).clamp(0.0, 1.0);

    final color2 = HSLColor.fromAHSL(1.0, hue2, saturation2, lightness2).toColor();

    return LinearGradient(
      colors: [baseColor, color2],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  String _getInitials(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return '?';
    if (cleaned.length <= 2) return cleaned.toUpperCase();
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final p1 = parts[0];
      final p2 = parts[1];
      if (p1.isNotEmpty && p2.isNotEmpty) {
        return (p1[0] + p2[0]).toUpperCase();
      }
    }
    return cleaned.substring(0, 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;

    return Scaffold(
      backgroundColor: isDark ? kSurfaceDark : const Color(0xFFF7F7FA),
      appBar: AppBar(
        title: contactsAsync.when(
          data: (contacts) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Contacts',
                style: GoogleFonts.inter(
                  color: textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 17.0,
                ),
              ),
              Text(
                '${contacts.length} saved',
                style: GoogleFonts.inter(
                  color: kAccentPurple,
                  fontSize: 13.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          loading: () => Text(
            'Contacts',
            style: GoogleFonts.inter(
              color: textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 17.0,
            ),
          ),
          error: (error, stack) => Text(
            'Contacts',
            style: GoogleFonts.inter(
              color: textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 17.0,
            ),
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
                  color: kAccentPurple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: kAccentPurple.withValues(alpha: 0.15),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chevron_left_rounded,
                      color: kAccentPurple,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Back',
                      style: GoogleFonts.inter(
                        color: kAccentPurple,
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
            color: borderColor,
            height: 0.5,
          ),
        ),
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 14.0,
                bottom: 16.0 + MediaQuery.paddingOf(context).bottom,
              ),
              child: _buildContactsSection(contactsAsync),
            ),
    );
  }

  Widget _buildContactsSection(AsyncValue<List<Contact>> contactsAsync) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    final mutedBG = isDark ? kMutedBGDark : kMutedBGLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _showContactForm(),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: kPrimaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.person_add_alt_1_outlined, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Add Contact',
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
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: _importFromDevice,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor, width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download_outlined, color: kAccentPurple, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Import Device',
                        style: GoogleFonts.inter(
                          color: kAccentPurple,
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
        const SizedBox(height: 14),

        contactsAsync.when(
          data: (contacts) {
            if (contacts.isEmpty) {
              return Card(
                elevation: 0,
                color: surfaceColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: borderColor, width: 0.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 16.0),
                  child: Center(
                    child: Text(
                      'No contacts found. Use the buttons above to add.',
                      style: GoogleFonts.inter(
                        color: textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

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
                final hasPhoto = contact.photoPath != null && contact.photoPath!.isNotEmpty;
                final isExpanded = _expandedContactId == contact.id;

                return Card(
                  key: ValueKey(contact.id),
                  elevation: 0,
                  color: surfaceColor,
                  margin: const EdgeInsets.symmetric(vertical: 6.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: borderColor, width: 0.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            _expandedContactId = isExpanded ? null : contact.id;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: ShapeDecoration(
                                  gradient: hasPhoto ? null : _getContactGradient(contact),
                                  shape: const CircleBorder(),
                                  image: hasPhoto
                                      ? DecorationImage(
                                          image: FileImage(File(contact.photoPath!)),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: hasPhoto
                                    ? null
                                    : Text(
                                        _getInitials(contact.name),
                                        style: GoogleFonts.inter(
                                          fontSize: 14.0,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      contact.name,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.0,
                                        color: textPrimary,
                                        height: 1.15,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      contact.phoneNumber,
                                      style: GoogleFonts.inter(
                                        fontSize: 12.0,
                                        color: textSecondary,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: Container(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Icon(Icons.drag_handle, color: textSecondary.withValues(alpha: 0.5), size: 17),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeInOut,
                        child: isExpanded
                            ? Column(
                                children: [
                                  Divider(height: 1, color: borderColor, thickness: 0.5),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => _simulateIncomingCall(contact),
                                            borderRadius: BorderRadius.circular(10),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                                              decoration: BoxDecoration(
                                                color: isDark ? kGreenTintDark.withValues(alpha: 0.15) : const Color(0xFFE1F5EE),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: isDark ? kGreenIconDark.withValues(alpha: 0.2) : const Color(0xFFE1F5EE), width: 0.5),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.phone, size: 12, color: isDark ? kGreenIconDark : const Color(0xFF1D9E75)),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Call',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark ? kGreenIconDark : const Color(0xFF1D9E75),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => _showContactForm(contact),
                                            borderRadius: BorderRadius.circular(10),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                                              decoration: BoxDecoration(
                                                color: isDark ? kBlueTintDark.withValues(alpha: 0.15) : const Color(0xFFE6F1FB),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: isDark ? kBlueIconDark.withValues(alpha: 0.2) : const Color(0xFFE6F1FB), width: 0.5),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.edit, size: 12, color: isDark ? kBlueIconDark : const Color(0xFF378ADD)),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Edit',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark ? kBlueIconDark : const Color(0xFF378ADD),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => _confirmDelete(contact),
                                            borderRadius: BorderRadius.circular(10),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                                              decoration: BoxDecoration(
                                                color: isDark ? kRedTintDark.withValues(alpha: 0.15) : const Color(0xFFFCEBEB),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: isDark ? kRedIconDark.withValues(alpha: 0.2) : const Color(0xFFFCEBEB), width: 0.5),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.delete_outline, size: 12, color: isDark ? kRedIconDark : const Color(0xFFE24B4A)),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Delete',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark ? kRedIconDark : const Color(0xFFE24B4A),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48.0),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stack) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 48.0),
            child: Center(
              child: Text('Error loading contacts: $error', style: const TextStyle(color: kSosRed)),
            ),
          ),
        ),
      ],
    );
  }
}

class _DeviceContactsImportDialog extends StatefulWidget {
  final List<Map<String, String>> contacts;
  final Function(List<Map<String, String>>) onImport;
  final Color accentColor;

  const _DeviceContactsImportDialog({
    required this.contacts,
    required this.onImport,
    required this.accentColor,
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

  String _getInitials(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return '?';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final p1 = parts[0];
      final p2 = parts[1];
      if (p1.isNotEmpty && p2.isNotEmpty) {
        return (p1[0] + p2[0]).toUpperCase();
      }
    }
    return cleaned.substring(0, cleaned.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    final mutedBG = isDark ? kMutedBGDark : kMutedBGLight;

    final filtered = widget.contacts.where((c) {
      final name = c['name']?.toLowerCase() ?? '';
      final phone = c['phoneNumber']?.toLowerCase() ?? '';
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();

    final allFilteredSelected = filtered.isNotEmpty && filtered.every((c) => _selected.contains(c));

    final gradients = [
      const LinearGradient(colors: [Color(0xFF534AB7), Color(0xFF7F77DD)]),
      const LinearGradient(colors: [Color(0xFFEF9F27), Color(0xFFFFB84D)]),
      const LinearGradient(colors: [Color(0xFF1D9E75), Color(0xFF33C294)]),
      const LinearGradient(colors: [Color(0xFFE24B4A), Color(0xFFF07272)]),
    ];

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.0),
        side: BorderSide(color: borderColor, width: 0.5),
      ),
      backgroundColor: surfaceColor,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      actionsPadding: const EdgeInsets.only(right: 20, bottom: 20, left: 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.accentColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.import_contacts_rounded, color: widget.accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            'Import Contacts',
            style: GoogleFonts.inter(
              color: textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 18.0,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width * 0.9,
        height: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              style: GoogleFonts.inter(color: textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by name or number...',
                hintStyle: GoogleFonts.inter(color: textSecondary.withValues(alpha: 0.6), fontSize: 14),
                prefixIcon: Icon(Icons.search, color: widget.accentColor.withValues(alpha: 0.6), size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 18, color: textSecondary),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: mutedBG,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: borderColor, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: widget.accentColor, width: 1.0),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () {
                setState(() {
                  if (allFilteredSelected) {
                    for (final c in filtered) {
                      _selected.remove(c);
                    }
                  } else {
                    for (final c in filtered) {
                      if (!_selected.contains(c)) {
                        _selected.add(c);
                      }
                    }
                  }
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select All Search Results',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: textPrimary,
                      ),
                    ),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: allFilteredSelected ? widget.accentColor : borderColor,
                          width: 1.5,
                        ),
                        color: allFilteredSelected ? widget.accentColor : Colors.transparent,
                      ),
                      child: allFilteredSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 14)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            Divider(color: borderColor, height: 16, thickness: 0.5),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No contacts found matching search',
                        style: GoogleFonts.inter(color: textSecondary, fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final contact = filtered[index];
                        final isSelected = _selected.contains(contact);
                        final gradient = gradients[index % gradients.length];

                        return InkWell(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selected.remove(contact);
                              } else {
                                _selected.add(contact);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: gradient,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _getInitials(contact['name'] ?? ''),
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        contact['name'] ?? '',
                                        style: GoogleFonts.inter(
                                          color: textPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        contact['phoneNumber'] ?? '',
                                        style: GoogleFonts.inter(
                                          color: textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? widget.accentColor : borderColor,
                                      width: 1.5,
                                    ),
                                    color: isSelected ? widget.accentColor : Colors.transparent,
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                                      : null,
                                ),
                              ],
                            ),
                          ),
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
          child: Text(
            'Cancel',
            style: GoogleFonts.inter(
              color: textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.accentColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: isDark ? kMutedBGDark : const Color(0xFFE2E8F0),
            disabledForegroundColor: textSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            elevation: 0,
          ),
          onPressed: _selected.isEmpty
              ? null
              : () {
                  widget.onImport(_selected);
                  Navigator.pop(context);
                },
          child: Text(
            'Import (${_selected.length})',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
