import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:uuid/uuid.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';

class ContactFormSheet extends ConsumerStatefulWidget {
  final Contact? contact;

  const ContactFormSheet({super.key, this.contact});

  @override
  ConsumerState<ContactFormSheet> createState() => _ContactFormSheetState();
}

class _ContactFormSheetState extends ConsumerState<ContactFormSheet> {
  final _formKey = GlobalKey<FormState>();
  
  Color get kAccentPurple => ref.watch(dynamicAccentColorProvider);
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();

  String _preferredAction = 'call';
  String? _photoPath;

  // --- Voice Label State ---
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _voiceLabelPath;

  String? _nameError;
  String? _phoneError;
  String? _whatsappError;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
      }
    });
    if (widget.contact != null) {
      final c = widget.contact!;
      _nameController.text = c.name;
      _phoneController.text = c.phoneNumber;
      _whatsappController.text = c.whatsappNumber ?? '';
      _preferredAction = c.preferredAction;
      _photoPath = c.photoPath;
      _voiceLabelPath = (c.voiceLabelPath == null || c.voiceLabelPath!.isEmpty) ? null : c.voiceLabelPath;
    }
    // Validate file paths exist on disk; null out stale references
    _validateFilePaths();
  }

  Future<void> _validateFilePaths() async {
    if (_photoPath != null) {
      final file = File(_photoPath!);
      if (!await file.exists()) {
        if (mounted) {
          setState(() => _photoPath = null);
        }
      }
    }
    if (_voiceLabelPath != null) {
      final file = File(_voiceLabelPath!);
      if (!await file.exists()) {
        if (mounted) {
          setState(() => _voiceLabelPath = null);
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    try {
      _audioRecorder.stop();
    } catch (_) {}
    _audioRecorder.dispose();
    try {
      _audioPlayer.stop();
    } catch (_) {}
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      // Check microphone permission
      var status = await Permission.microphone.status;
      if (status.isPermanentlyDenied) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Microphone Permission Required', style: GoogleFonts.fraunces(fontWeight: FontWeight.bold, color: kTextNavy)),
              content: Text(
                'Microphone permission is permanently denied. Please open your phone settings to enable it for EasyConnect so you can record voice labels.',
                style: GoogleFonts.nunito(color: kTextDark),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.nunito(color: kTextSlate, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    openAppSettings();
                  },
                  child: Text('Open Settings', style: GoogleFonts.nunito(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
        return;
      }
      
      if (!status.isGranted) {
        status = await Permission.microphone.request();
      }
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required to record voice labels.')),
          );
        }
        return;
      }

      // Stop preview player if active
      if (_isPlaying) {
        await _audioPlayer.stop();
        setState(() => _isPlaying = false);
      }

      // Generate a temporary file path
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${tempDir.path}/temp_voice_label_$timestamp.m4a';

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 16000,
      );

      await _audioRecorder.start(config, path: path);
      setState(() {
        _isRecording = true;
        _voiceLabelPath = path;
      });

      // Automatically stop after 5 seconds safety limit for names
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _isRecording) {
          _stopRecording();
        }
      });
    } catch (e) {
      debugPrint('Error starting recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        if (path != null) {
          _voiceLabelPath = path;
        }
      });
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      setState(() => _isRecording = false);
    }
  }

  Future<void> _pickAudioFile() async {
    try {
      // Stop preview player if active
      if (_isPlaying) {
        await _audioPlayer.stop();
        setState(() => _isPlaying = false);
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
        withData: true, // Crucial for reading bytes directly on Scoped Storage
      );

      if (result != null && result.files.isNotEmpty) {
        final fileVal = result.files.single;
        final extension = fileVal.extension?.toLowerCase() ?? 
            fileVal.name.split('.').last.toLowerCase();
        
        // Ensure extension is clean and reasonable, e.g. mp3, wav, m4a, etc.
        final cleanExt = extension.isNotEmpty ? extension : 'm4a';

        // Get a secure path in the temporary directory to save the file copy
        final tempDir = await getTemporaryDirectory();
        final tempCopyPath = '${tempDir.path}/picked_voice_${DateTime.now().millisecondsSinceEpoch}.$cleanExt';
        
        final bytes = fileVal.bytes;
        if (bytes != null) {
          // Bypasses File path read permissions completely by writing in-memory bytes to cache
          final newFile = File(tempCopyPath);
          await newFile.writeAsBytes(bytes);
          setState(() {
            _voiceLabelPath = tempCopyPath;
          });
          debugPrint('Successfully picked and saved audio bytes to: $tempCopyPath');
        } else if (fileVal.path != null) {
          // Fallback if path is available and bytes are not
          final srcFile = File(fileVal.path!);
          if (await srcFile.exists()) {
            await srcFile.copy(tempCopyPath);
            setState(() {
              _voiceLabelPath = tempCopyPath;
            });
            debugPrint('Successfully copied picked audio file to: $tempCopyPath');
          } else {
            throw Exception('Selected file path does not exist on disk.');
          }
        } else {
          throw Exception('No file data or path returned from picker.');
        }
      }
    } catch (e) {
      debugPrint('Error picking audio file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick audio file: $e'),
            backgroundColor: kSosRed,
          ),
        );
      }
    }
  }

  Future<void> _togglePlayPreview() async {
    if (_voiceLabelPath == null || _voiceLabelPath!.isEmpty) return;
    try {
      if (_isPlaying) {
        await _audioPlayer.stop();
        setState(() => _isPlaying = false);
      } else {
        await _audioPlayer.play(DeviceFileSource(_voiceLabelPath!));
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('Error playing preview: $e');
    }
  }

  Future<void> _deleteVoiceLabel() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.stop();
        setState(() => _isPlaying = false);
      }
      if (_voiceLabelPath != null) {
        final file = File(_voiceLabelPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      setState(() {
        _voiceLabelPath = null;
      });
    } catch (e) {
      debugPrint('Error deleting voice label: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 200,
        maxHeight: 200,
      );

      if (pickedFile != null) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          maxWidth: 200,
          maxHeight: 200,
          compressQuality: 60,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Photo',
              toolbarColor: kAccentPurple,
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
        title: Text('Select Contact Photo', style: GoogleFonts.fraunces(fontWeight: FontWeight.bold, color: kTextNavy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt_outlined, color: kAccentPurple),
              title: Text('Take Photo', style: GoogleFonts.nunito(fontWeight: FontWeight.bold, color: kTextDark)),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined, color: kVideoBlue),
              title: Text('Choose from Gallery', style: GoogleFonts.nunito(fontWeight: FontWeight.bold, color: kTextDark)),
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
          voiceLabelPath: (_voiceLabelPath == null || _voiceLabelPath!.isEmpty) ? null : _voiceLabelPath,
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
          voiceLabelPath: (_voiceLabelPath == null || _voiceLabelPath!.isEmpty) ? null : _voiceLabelPath,
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
    final mediaQueryData = MediaQuery.of(context);

    return MediaQuery(
      data: mediaQueryData.copyWith(
        textScaler: mediaQueryData.textScaler.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.35,
        ),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: kAppBackground,
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
                            style: GoogleFonts.fraunces(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: kTextNavy,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Card 1: Avatar & Name
                          Card(
                            margin: const EdgeInsets.only(bottom: 20.0),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'Profile Photo & Name',
                                    style: GoogleFonts.nunito(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: kTextNavy,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Photo Picker Section
                                  GestureDetector(
                                    onTap: _showPhotoOptions,
                                    child: Stack(
                                      alignment: Alignment.bottomRight,
                                      children: [
                                        Container(
                                          width: 120,
                                          height: 120,
                                          decoration: ShapeDecoration(
                                            color: Colors.grey.shade100,
                                            shape: ContinuousRectangleBorder(
                                              borderRadius: BorderRadius.circular(42),
                                              side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                                            ),
                                            image: (_photoPath != null && _photoPath!.isNotEmpty && !_photoPath!.startsWith('data:') && File(_photoPath!).existsSync())
                                                ? DecorationImage(
                                                    image: FileImage(File(_photoPath!)),
                                                    fit: BoxFit.cover,
                                                  )
                                                : null,
                                          ),
                                          child: (_photoPath == null || _photoPath!.isEmpty || _photoPath!.startsWith('data:') || !File(_photoPath!).existsSync())
                                              ? const Icon(
                                                  Icons.person,
                                                  size: 72,
                                                  color: Colors.grey,
                                                )
                                              : null,
                                        ),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: kAccentPurple,
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
                                    style: GoogleFonts.nunito(fontSize: 18.0, color: kTextDark),
                                    decoration: InputDecoration(
                                      labelText: 'Contact Name',
                                      labelStyle: GoogleFonts.nunito(color: kTextSlate, fontWeight: FontWeight.w600),
                                      floatingLabelStyle: GoogleFonts.nunito(color: kAccentPurple, fontWeight: FontWeight.bold),
                                      filled: true,
                                      fillColor: const Color(0xFFF2F2F7),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      errorText: _nameError,
                                      errorStyle: GoogleFonts.nunito(color: kSosRed, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Card 2: Phone Settings
                          Card(
                            margin: const EdgeInsets.only(bottom: 20.0),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Center(
                                    child: Text(
                                      'Phone Numbers',
                                      style: GoogleFonts.nunito(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: kTextNavy,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Phone Number Field
                                  TextFormField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    style: GoogleFonts.nunito(fontSize: 18.0, color: kTextDark),
                                    decoration: InputDecoration(
                                      labelText: 'Phone Number',
                                      labelStyle: GoogleFonts.nunito(color: kTextSlate, fontWeight: FontWeight.w600),
                                      floatingLabelStyle: GoogleFonts.nunito(color: kAccentPurple, fontWeight: FontWeight.bold),
                                      filled: true,
                                      fillColor: const Color(0xFFF2F2F7),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      errorText: _phoneError,
                                      errorStyle: GoogleFonts.nunito(color: kSosRed, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // WhatsApp Number Field
                                  TextFormField(
                                    controller: _whatsappController,
                                    keyboardType: TextInputType.phone,
                                    style: GoogleFonts.nunito(fontSize: 18.0, color: kTextDark),
                                    decoration: InputDecoration(
                                      labelText: 'WhatsApp Number (optional)',
                                      labelStyle: GoogleFonts.nunito(color: kTextSlate, fontWeight: FontWeight.w600),
                                      floatingLabelStyle: GoogleFonts.nunito(color: kAccentPurple, fontWeight: FontWeight.bold),
                                      filled: true,
                                      fillColor: const Color(0xFFF2F2F7),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      errorText: _whatsappError,
                                      errorStyle: GoogleFonts.nunito(color: kSosRed, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Card 3: Voice Pronunciation Label Section
                          Card(
                            margin: const EdgeInsets.only(bottom: 20.0),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.mic, color: kAccentPurple, size: 24),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Voice Pronunciation',
                                        style: GoogleFonts.nunito(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: kTextNavy,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Record the contact's name in your own voice if the automatic voice guide is hard to understand.",
                                    style: GoogleFonts.nunito(
                                      fontSize: 14,
                                      color: kTextSlate,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (_isRecording) ...[
                                    // Recording state UI
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const _PulsingRecordIndicator(),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Recording... (Max 5s)',
                                          style: GoogleFonts.nunito(
                                            fontWeight: FontWeight.bold,
                                            color: kSosRed,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const Spacer(),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: kSosRed,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          onPressed: _stopRecording,
                                          icon: const Icon(Icons.stop),
                                          label: Text(
                                            'Stop',
                                            style: GoogleFonts.nunito(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else if (_voiceLabelPath != null && _voiceLabelPath!.isNotEmpty) ...[
                                    // Recorded state UI — voice file exists
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: kAccentPurple.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: kAccentPurple.withValues(alpha: 0.2)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.check_circle, color: kAccentPurple, size: 18),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  'Custom voice recorded',
                                                  style: GoogleFonts.nunito(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: kAccentPurple,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: _isPlaying ? Colors.grey.shade800 : kAccentPurple,
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                  ),
                                                  onPressed: _togglePlayPreview,
                                                  icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow, size: 18),
                                                  label: Text(
                                                    _isPlaying ? 'Stop' : 'Play',
                                                    style: GoogleFonts.nunito(fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                ),
                                                OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: kAccentPurple,
                                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                    side: BorderSide(color: kAccentPurple),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                  ),
                                                  onPressed: _startRecording,
                                                  icon: const Icon(Icons.mic, size: 18),
                                                  label: Text(
                                                    'Re-record',
                                                    style: GoogleFonts.nunito(fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                ),
                                                OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: kAccentPurple,
                                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                    side: BorderSide(color: kAccentPurple),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                  ),
                                                  onPressed: _pickAudioFile,
                                                  icon: const Icon(Icons.audio_file, size: 18),
                                                  label: Text(
                                                    'Upload File',
                                                    style: GoogleFonts.nunito(fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                ),
                                                OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: kSosRed,
                                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                    side: const BorderSide(color: kSosRed),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                  ),
                                                  onPressed: _deleteVoiceLabel,
                                                  icon: const Icon(Icons.delete_outline, size: 18),
                                                  label: Text(
                                                    'Delete',
                                                    style: GoogleFonts.nunito(fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  ] else ...[
                                    // Default/Empty state UI (Record button + Pick audio file button)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: kAccentPurple,
                                              side: BorderSide(color: kAccentPurple, width: 1.5),
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                            onPressed: _startRecording,
                                            icon: const Icon(Icons.mic),
                                            label: Text(
                                              'Record Voice',
                                              style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.bold),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: kAccentPurple,
                                              side: BorderSide(color: kAccentPurple, width: 1.5),
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                            onPressed: _pickAudioFile,
                                            icon: const Icon(Icons.audio_file),
                                            label: Text(
                                              'Upload File',
                                              style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.bold),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          // Card 4: Preferred Action SegmentedButton
                          Card(
                            margin: const EdgeInsets.only(bottom: 24.0),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Center(
                                    child: Text(
                                      'Preferred Action',
                                      style: GoogleFonts.nunito(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: kTextNavy,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: ColorScheme.fromSeed(
                                        seedColor: kAccentPurple,
                                        primary: kAccentPurple,
                                      ),
                                    ),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: SegmentedButton<String>(
                                        segments: [
                                          ButtonSegment(
                                            value: 'call',
                                            icon: const Icon(Icons.phone),
                                            label: Text('Call', style: GoogleFonts.nunito(fontWeight: FontWeight.bold)),
                                          ),
                                          ButtonSegment(
                                            value: 'video',
                                            icon: const Icon(Icons.video_call),
                                            label: Text('Video', style: GoogleFonts.nunito(fontWeight: FontWeight.bold)),
                                          ),
                                          ButtonSegment(
                                            value: 'message',
                                            icon: const Icon(Icons.mic),
                                            label: Text('Message', style: GoogleFonts.nunito(fontWeight: FontWeight.bold)),
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
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Action Buttons Row
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: kMinTouchTarget,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: kTextSlate,
                                      side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.pop(context);
                                    },
                                    child: Text(
                                      'Cancel',
                                      style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.bold),
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
                                      backgroundColor: kAccentPurple,
                                      foregroundColor: Colors.white,
                                      elevation: 2,
                                      shadowColor: kAccentPurple.withValues(alpha: 0.3),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    onPressed: () {
                                      HapticFeedback.mediumImpact();
                                      _saveContact();
                                    },
                                    child: Text(
                                      'Save',
                                      style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.bold),
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
      ),
    );
  }
}

class _PulsingRecordIndicator extends StatefulWidget {
  const _PulsingRecordIndicator();

  @override
  State<_PulsingRecordIndicator> createState() => _PulsingRecordIndicatorState();
}

class _PulsingRecordIndicatorState extends State<_PulsingRecordIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withValues(alpha: 0.3 + 0.7 * _controller.value),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.4 * _controller.value),
                blurRadius: 8 * _controller.value,
                spreadRadius: 2 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
