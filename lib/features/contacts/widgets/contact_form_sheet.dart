import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:uuid/uuid.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/services/tts_service.dart';

class ContactFormSheet extends ConsumerStatefulWidget {
  final Contact? contact;

  const ContactFormSheet({super.key, this.contact});

  @override
  ConsumerState<ContactFormSheet> createState() => _ContactFormSheetState();
}

class _ContactFormSheetState extends ConsumerState<ContactFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();

  String _preferredAction = 'call';
  String? _photoPath;

  String? _nameError;
  String? _phoneError;
  String? _whatsappError;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.contact != null) {
      final c = widget.contact!;
      _nameController.text = c.name;
      _phoneController.text = c.phoneNumber;
      _whatsappController.text = c.whatsappNumber ?? '';
      _preferredAction = c.preferredAction;
      _photoPath = c.photoPath;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Photo',
              toolbarColor: kCallGreen,
              toolbarWidgetColor: Colors.white,
              aspectRatioPresets: [
                CropAspectRatioPreset.square,
              ],
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
            ),
            IOSUiSettings(
              title: 'Crop Photo',
              aspectRatioPresets: [
                CropAspectRatioPreset.square,
              ],
              aspectRatioLockEnabled: true,
            ),
          ],
        );

        if (croppedFile != null && mounted) {
          setState(() {
            _photoPath = croppedFile.path;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select image: $e'), backgroundColor: kSosRed),
        );
      }
    }
  }

  void _showPhotoOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Contact Photo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: kCallGreen),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined, color: kVideoBlue),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _validate() {
    bool isValid = true;
    setState(() {
      _nameError = null;
      _phoneError = null;
      _whatsappError = null;
    });

    if (_nameController.text.trim().isEmpty) {
      setState(() => _nameError = 'Name is required');
      isValid = false;
    }

    final phoneVal = _phoneController.text.trim();
    final phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');
    if (phoneVal.isEmpty) {
      setState(() => _phoneError = 'Phone number is required');
      isValid = false;
    } else if (!phoneRegex.hasMatch(phoneVal)) {
      setState(() => _phoneError = 'Invalid phone number (must be 7-15 digits)');
      isValid = false;
    }

    final whatsappVal = _whatsappController.text.trim();
    if (whatsappVal.isNotEmpty && !phoneRegex.hasMatch(whatsappVal)) {
      setState(() => _whatsappError = 'Invalid WhatsApp number (must be 7-15 digits)');
      isValid = false;
    }

    return isValid;
  }

  Future<void> _saveContact() async {
    if (!_validate()) return;

    final repo = ref.read(contactRepositoryProvider);
    final isEditMode = widget.contact != null;

    try {
      if (isEditMode) {
        final existingContact = widget.contact!;
        final updatedContact = Contact(
          id: existingContact.id,
          name: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          whatsappNumber: _whatsappController.text.trim().isEmpty
              ? null
              : _whatsappController.text.trim(),
          photoPath: _photoPath,
          colorTheme: existingContact.colorTheme,
          preferredAction: _preferredAction,
          positionIndex: existingContact.positionIndex,
          voiceLabelPath: existingContact.voiceLabelPath,
        );
        await repo.updateContact(updatedContact);
      } else {
        final contacts = await repo.getAllContacts();
        final maxPosition = contacts.isEmpty
            ? -1
            : contacts.map((c) => c.positionIndex).reduce((a, b) => a > b ? a : b);
        
        final newContact = Contact(
          id: const Uuid().v4(),
          name: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          whatsappNumber: _whatsappController.text.trim().isEmpty
              ? null
              : _whatsappController.text.trim(),
          photoPath: _photoPath,
          preferredAction: _preferredAction,
          positionIndex: maxPosition + 1,
        );
        await repo.addContact(newContact);
      }

      await ref.read(ttsServiceProvider).speak('Contact saved.');
      
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save contact: $e'), backgroundColor: kSosRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardPadding = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Top drag bar indicator
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.only(
                    left: 24.0,
                    right: 24.0,
                    top: 8.0,
                    bottom: 24.0 + keyboardPadding,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          widget.contact == null ? 'Add Contact' : 'Edit Contact',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: kTextDark,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Photo Picker Section
                        GestureDetector(
                          onTap: _showPhotoOptions,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey.shade300, width: 1.5),
                                  image: _photoPath != null
                                      ? DecorationImage(
                                          image: FileImage(File(_photoPath!)),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: _photoPath == null
                                    ? const Icon(
                                        Icons.person,
                                        size: 72,
                                        color: Colors.grey,
                                      )
                                    : null,
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: kCallGreen,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Contact Name Field
                        TextFormField(
                          controller: _nameController,
                          maxLength: 30,
                          style: const TextStyle(fontSize: 18.0),
                          decoration: InputDecoration(
                            labelText: 'Contact Name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            errorText: _nameError,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Phone Number Field
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            errorText: _phoneError,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // WhatsApp Number Field
                        TextFormField(
                          controller: _whatsappController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'WhatsApp Number (optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            errorText: _whatsappError,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Preferred Action SegmentedButton
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Preferred Action',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'call',
                                icon: Icon(Icons.phone),
                                label: Text('Call'),
                              ),
                              ButtonSegment(
                                value: 'video',
                                icon: Icon(Icons.video_call),
                                label: Text('Video'),
                              ),
                              ButtonSegment(
                                value: 'message',
                                icon: Icon(Icons.mic),
                                label: Text('Message'),
                              ),
                            ],
                            selected: {_preferredAction},
                            onSelectionChanged: (Set<String> newSelection) {
                              setState(() {
                                _preferredAction = newSelection.first;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Action Buttons Row
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: kMinTouchTarget,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.grey.shade700,
                                    side: BorderSide(color: Colors.grey.shade400),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SizedBox(
                                height: kMinTouchTarget,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kCallGreen,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _saveContact,
                                  child: const Text(
                                    'Save',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              ),
            ],
          ),
        );
      },
    );
  }
}
