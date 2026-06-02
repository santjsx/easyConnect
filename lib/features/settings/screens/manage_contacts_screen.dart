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
          SnackBar(content: Text('${contact.name} deleted'), backgroundColor: kAccentPurple),
        );
      }
    }
  }

  Gradient _getInitialsGradient(int index) {
    final gradients = [
      kPrimaryGradient,
      kVoiceOrangeGradient,
      kCallGreenGradient,
      kPinkGradient,
    ];
    return gradients[index % gradients.length];
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

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      appBar: AppBar(
        title: contactsAsync.when(
          data: (contacts) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Contacts',
                style: GoogleFonts.nunito(
                  color: const Color(0xFF1B1B2E),
                  fontWeight: FontWeight.w700,
                  fontSize: 17.0,
                ),
              ),
              Text(
                '${contacts.length} saved',
                style: GoogleFonts.nunito(
                  color: const Color(0xFF5C5BE8),
                  fontSize: 13.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          loading: () => Text(
            'Contacts',
            style: GoogleFonts.nunito(
              color: const Color(0xFF1B1B2E),
              fontWeight: FontWeight.w700,
              fontSize: 17.0,
            ),
          ),
          error: (error, stack) => Text(
            'Contacts',
            style: GoogleFonts.nunito(
              color: const Color(0xFF1B1B2E),
              fontWeight: FontWeight.w700,
              fontSize: 17.0,
            ),
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
                      style: GoogleFonts.nunito(
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
            color: const Color(0x12000000),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Add & Import Action Row
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
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: _importFromDevice,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x4D5C5BE8), width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.download_outlined, color: Color(0xFF5C5BE8), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Import Device',
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
        ),
        const SizedBox(height: 14),

        // Contacts list
        contactsAsync.when(
          data: (contacts) {
            if (contacts.isEmpty) {
              return Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 16.0),
                  child: Center(
                    child: Text(
                      'No contacts found. Use the buttons above to add.',
                      style: GoogleFonts.nunito(
                        color: const Color(0xFF9999B0),
                        fontWeight: FontWeight.w700,
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

                return Card(
                  key: ValueKey(contact.id),
                  elevation: 0,
                  color: Colors.white,
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: hasPhoto ? null : _getInitialsGradient(index),
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
                                      style: GoogleFonts.nunito(
                                        fontSize: 14.0,
                                        fontWeight: FontWeight.w800,
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
                                    style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.0,
                                      color: const Color(0xFF1B1B2E),
                                      height: 1.15,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    contact.phoneNumber,
                                    style: GoogleFonts.nunito(
                                      fontSize: 11.0,
                                      color: const Color(0xFF9999B0),
                                      fontWeight: FontWeight.w500,
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
                                child: const Icon(Icons.drag_handle, color: Color(0xFFCCCCDA), size: 17),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 0.5,
                        color: const Color(0xFFF2F2F8),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _simulateIncomingCall(contact),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.phone, size: 12, color: Color(0xFF32E08A)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Call',
                                      style: GoogleFonts.nunito(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF32E08A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 0.5,
                            height: 24,
                            color: const Color(0xFFF2F2F8),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => _showContactForm(contact),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.edit, size: 12, color: Color(0xFF5C5BE8)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Edit',
                                      style: GoogleFonts.nunito(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF5C5BE8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 0.5,
                            height: 24,
                            color: const Color(0xFFF2F2F8),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => _confirmDelete(contact),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.delete_outline, size: 12, color: Color(0xFFFF4B6E)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Delete',
                                      style: GoogleFonts.nunito(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFFFF4B6E),
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
    final filtered = widget.contacts.where((c) {
      final name = c['name']?.toLowerCase() ?? '';
      final phone = c['phoneNumber']?.toLowerCase() ?? '';
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();

    final allFilteredSelected = filtered.isNotEmpty && filtered.every((c) => _selected.contains(c));

    final gradients = [
      const LinearGradient(colors: [Color(0xFF6C6BF8), Color(0xFF8B8AFA)]),
      const LinearGradient(colors: [Color(0xFFFF8C00), Color(0xFFFFA534)]),
      const LinearGradient(colors: [Color(0xFF32E08A), Color(0xFF66FFA6)]),
      const LinearGradient(colors: [Color(0xFFE8265E), Color(0xFFFF5E8C)]),
    ];

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
      backgroundColor: Colors.white,
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
            style: GoogleFonts.fraunces(
              color: kTextNavy,
              fontWeight: FontWeight.bold,
              fontSize: 20.0,
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
              style: GoogleFonts.nunito(color: kTextNavy, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by name or number...',
                hintStyle: GoogleFonts.nunito(color: const Color(0xFF9999B0), fontSize: 14),
                prefixIcon: Icon(Icons.search, color: widget.accentColor.withValues(alpha: 0.6), size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: widget.accentColor, width: 1.5),
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
                      style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: kTextNavy,
                      ),
                    ),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: allFilteredSelected ? widget.accentColor : const Color(0xFFCBD5E1),
                          width: 2.0,
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
            const Divider(color: Color(0xFFF1F5F9), height: 16, thickness: 1.5),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No contacts found matching search',
                        style: GoogleFonts.nunito(color: const Color(0xFF9999B0), fontSize: 14),
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
                                    style: const TextStyle(
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
                                        style: GoogleFonts.nunito(
                                          color: kTextNavy,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        contact['phoneNumber'] ?? '',
                                        style: GoogleFonts.nunito(
                                          color: const Color(0xFF9999B0),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
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
                                      color: isSelected ? widget.accentColor : const Color(0xFFE2E8F0),
                                      width: 2.0,
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
            style: GoogleFonts.nunito(
              color: const Color(0xFF9999B0),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.accentColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFE2E8F0),
            disabledForegroundColor: const Color(0xFF9999B0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            elevation: _selected.isEmpty ? 0 : 4,
            shadowColor: widget.accentColor.withValues(alpha: 0.3),
          ),
          onPressed: _selected.isEmpty
              ? null
              : () {
                  widget.onImport(_selected);
                  Navigator.pop(context);
                },
          child: Text(
            'Import (${_selected.length})',
            style: GoogleFonts.nunito(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
