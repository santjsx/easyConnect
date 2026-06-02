import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/features/contacts/widgets/contact_form_sheet.dart';
import 'package:easyconnect/features/calling/screens/calling_screen.dart';

class ManageContactsScreen extends ConsumerStatefulWidget {
  const ManageContactsScreen({super.key});

  @override
  ConsumerState<ManageContactsScreen> createState() => _ManageContactsScreenState();
}

class _ManageContactsScreenState extends ConsumerState<ManageContactsScreen> {
  bool _isProcessing = false;

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

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsStreamProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Manage Contacts',
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
              child: _buildContactsSection(contactsAsync),
            ),
    );
  }

  Widget _buildContactsSection(AsyncValue<List<Contact>> contactsAsync) {
    return Column(
      children: [
        // Add & Import Action Row
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: kMinTouchTarget,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccentPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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
        const SizedBox(height: 20),

        // Contacts list
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: contactsAsync.when(
              data: (contacts) {
                if (contacts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48.0),
                    child: Center(
                      child: Text(
                        'No contacts found. Use the buttons above to add.',
                        style: TextStyle(color: kTextSlate, fontWeight: FontWeight.bold),
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
                    return Card(
                      key: ValueKey(contact.id),
                      elevation: 0,
                      color: Colors.grey.shade50,
                      margin: const EdgeInsets.symmetric(vertical: 6.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: Colors.grey.shade300,
                                  backgroundImage: contact.photoPath != null && contact.photoPath!.isNotEmpty
                                      ? FileImage(File(contact.photoPath!))
                                      : null,
                                  child: contact.photoPath == null || contact.photoPath!.isEmpty
                                      ? const Icon(Icons.person, color: Colors.grey, size: 28)
                                      : null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        contact.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16.0,
                                          color: kTextNavy,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        contact.phoneNumber,
                                        style: TextStyle(
                                          fontSize: 14.0,
                                          color: Colors.grey.shade600,
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
                                    child: Icon(Icons.drag_handle, color: Colors.grey.shade400, size: 24),
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: Colors.grey.shade200,
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: kMinTouchTarget,
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: kAccentPurple,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () => _simulateIncomingCall(contact),
                                      icon: const Icon(Icons.phone_callback, size: 18),
                                      label: const Text(
                                        'Simulate Call',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: SizedBox(
                                    height: kMinTouchTarget,
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: kAccentPurple,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () => _showContactForm(contact),
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      label: const Text(
                                        'Edit',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: SizedBox(
                                    height: kMinTouchTarget,
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: kSosRed,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () => _confirmDelete(contact),
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                      label: const Text(
                                        'Delete',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
          ),
        ),
      ],
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
        height: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            backgroundColor: kAccentPurple,
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
