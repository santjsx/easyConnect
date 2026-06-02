import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/calling/services/audio_call_service.dart';
import 'package:easyconnect/features/calling/services/whatsapp_call_service.dart';
import 'package:easyconnect/features/voice_message/services/recording_service.dart';
import 'package:easyconnect/features/voice_message/widgets/recording_overlay.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';

class PhotolessSelectionState {
  final String? contactId;
  final int lastTapTime;

  PhotolessSelectionState({this.contactId, this.lastTapTime = 0});
}

final photolessSelectionProvider = StateProvider<PhotolessSelectionState>((ref) {
  return PhotolessSelectionState();
});

class ContactCard extends ConsumerWidget {
  final Contact contact;

  const ContactCard({super.key, required this.contact});

  void _announceName(WidgetRef ref) async {
    final tts = ref.read(ttsServiceProvider);
    await tts.stop();

    final nameToSpeak = contact.name.trim();
    if (nameToSpeak.isEmpty) {
      // Empty contact name: Speak casual error phrase and reset selection (no call)
      await tts.speak("పేరు లేదు", forceLanguage: 'te');
      ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState();
      return;
    }

    try {
      // Announce the name using warm natural Telugu pitch configurations
      await tts.speak(nameToSpeak, forceLanguage: 'te');
    } catch (e) {
      // Fallback: TTS engine failed / not initialized -> Buzz long-short-long tactile pattern
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 200));
      await HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.vibrate();
    }
  }

  Future<void> _executePreferredAction(BuildContext context, WidgetRef ref) async {
    final hasWhatsapp = contact.whatsappNumber != null && contact.whatsappNumber!.trim().isNotEmpty;
    
    if (contact.preferredAction == 'video') {
      if (hasWhatsapp) {
        await ref.read(whatsAppCallServiceProvider).makeVideoCall(context, contact);
      } else {
        // Fallback or guidance if WhatsApp number is empty
        final settings = ref.read(settingsProvider).value;
        final language = settings?.language ?? 'en';
        final prompt = language == 'te'
            ? 'వాట్సాప్ నెంబర్ లేదు. మామూలు ఫోన్ కాల్ చేస్తున్నాను.'
            : (language == 'hi'
                ? 'व्हाट्सएप नंबर नहीं है। सामान्य फोन कॉल किया जा रहा है।'
                : 'No WhatsApp number saved. Making a standard phone call.');
        await ref.read(ttsServiceProvider).speak(prompt);
        await Future.delayed(const Duration(milliseconds: 1500));
        if (context.mounted) {
          await ref.read(audioCallServiceProvider).makeCall(context, contact);
        }
      }
    } else if (contact.preferredAction == 'message') {
      if (hasWhatsapp) {
        // Voice message flow: start recording, then open recording overlay
        final path = await ref.read(recordingServiceProvider.notifier).startRecording();
        if (path != null) {
          ref.read(voiceMessageOverlayProvider.notifier).open(contact);
        }
      } else {
        final settings = ref.read(settingsProvider).value;
        final language = settings?.language ?? 'en';
        final prompt = language == 'te'
            ? 'వాట్సాప్ నెంబర్ లేదు. మామూలు ఫోన్ కాల్ చేస్తున్నాను.'
            : (language == 'hi'
                ? 'व्हाट्सएप नंबर नहीं है। सामान्य फोन कॉल किया जा रहा है।'
                : 'No WhatsApp number saved. Making a standard phone call.');
        await ref.read(ttsServiceProvider).speak(prompt);
        await Future.delayed(const Duration(milliseconds: 1500));
        if (context.mounted) {
          await ref.read(audioCallServiceProvider).makeCall(context, contact);
        }
      }
    } else {
      // Default to audio call
      await ref.read(audioCallServiceProvider).makeCall(context, contact);
    }
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    final hasPhoto = contact.photoPath != null && contact.photoPath!.isNotEmpty;

    if (hasPhoto) {
      // Contact has photo -> immediately place the call
      _executePreferredAction(context, ref);
      return;
    }

    final selection = ref.read(photolessSelectionProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Check if double-tapped too fast (< 300ms)
    final isDoubleTapTooFast = selection.contactId == contact.id && (now - selection.lastTapTime < 300);

    if (isDoubleTapTooFast) {
      // Treat as single tap: announce name, do not call, update timestamp
      ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState(
        contactId: contact.id,
        lastTapTime: now,
      );
      _announceName(ref);
      return;
    }

    if (selection.contactId == contact.id) {
      // Second tap: Confirm call placement and reset selection
      ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState();
      _executePreferredAction(context, ref);
    } else {
      // First tap or selection changed: Reset previous selection, start TTS name readout, and log active selection
      ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState(
        contactId: contact.id,
        lastTapTime: now,
      );
      _announceName(ref);

      // Auto-reset selection after 4 seconds of inactivity
      final currentId = contact.id;
      Future.delayed(const Duration(seconds: 4), () {
        final currentSelection = ref.read(photolessSelectionProvider);
        if (currentSelection.contactId == currentId) {
          ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState();
        }
      });
    }
  }

  void _showSeniorActionSheet(BuildContext context, WidgetRef ref) {
    HapticFeedback.heavyImpact();

    final settings = ref.read(settingsProvider).value;
    final language = settings?.language ?? 'en';
    final hasWhatsapp = contact.whatsappNumber != null && contact.whatsappNumber!.trim().isNotEmpty;

    // Glowing border ring colors mapped based on position index
    final ringColors = [
      const Color(0xFF4CAF50), // Green (Santhosh)
      const Color(0xFF9C27B0), // Purple (Anitha)
      const Color(0xFFE91E63), // Pink (Nandini)
      const Color(0xFFFF5722), // Orange (Latha Akka)
      const Color(0xFFFFC107), // Yellow (Ramesh Mama)
      const Color(0xFF009688), // Teal (Vikram)
    ];
    final ringColor = ringColors[contact.positionIndex % ringColors.length];
    final isOnline = contact.positionIndex == 0;

    // Speak prompt
    String prompt = '';
    if (language == 'te') {
      prompt = "${contact.name} à°•à°¿ à°«à±‹à°¨à± à°šà±‡à°¯à°¡à°¾à°¨à°¿à°•à°¿ à°†à°•à±à°ªà°šà±à°š à°¬à°Ÿà°¨à±, à°µà±€à°¡à°¿à°¯à±‹ à°•à°¾à°²à± à°•à°¿ à°¨à±€à°²à°‚ à°¬à°Ÿà°¨à±, à°²à±‡à°¦à°¾ à°µà°¾à°¯à°¿à°¸à± à°®à±†à°¸à±‡à°œà± à°•à°¿ à°¨à°¾à°°à°¿à°‚à°œ à°¬à°Ÿà°¨à± à°¨à±Šà°•à±à°•à°‚à°¡à°¿.";
    } else if (language == 'hi') {
      prompt = "${contact.name} à¤•à¥‹ à¤«à¤¼à¥‹à¤¨ à¤•à¤°à¤¨à¥‡ à¤•à¥‡ à¤²à¤¿à¤ à¤¹à¤°à¤¾ à¤¬à¤Ÿà¤¨, à¤µà¥€à¤¡à¤¿à¤¯à¥‹ à¤•à¥‰à¤² à¤•à¥‡ à¤²à¤¿à¤ à¤¨à¥€à¤²à¤¾ à¤¬à¤Ÿà¤¨, à¤¯à¤¾ à¤†à¤µà¤¾à¤œà¤¼ à¤¸à¤‚à¤¦à¥‡à¤¶ à¤•à¥‡ à¤²à¤¿à¤ à¤¨à¤¾à¤°à¤‚à¤—à¥€ à¤¬à¤Ÿà¤¨ à¤¦à¤¬à¤¾à¤à¤‚à¥¤";
    } else {
      prompt = "To connect with ${contact.name}, tap the green button for a phone call, the blue button for a video call, or the orange button for a voice message.";
    }
    ref.read(ttsServiceProvider).speak(prompt);

    final String callLabel = language == 'te' ? 'à°•à°¾à°²à±' : (language == 'hi' ? 'à¤•à¥‰à¤²' : 'Call');
    final String videoLabel = language == 'te' ? 'à°µà±€à°¡à°¿à°¯à±‹' : (language == 'hi' ? 'à¤µà¥€à¤¡à¤¿à¤¯à¥‹' : 'Video');
    final String voiceLabel = language == 'te' ? 'à°µà°¾à°¯à°¿à°¸à±' : (language == 'hi' ? 'à¤µà¥‰à¤¯à¤¸' : 'Voice');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      elevation: 10,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pull bar (modern, light matching)
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 24),

                // Contact Header with large photo or initials (Navy/Light themed)
                Semantics(
                  label: "Connecting with ${contact.name}",
                  container: true,
                  child: Column(
                    children: [
                      _buildPhoto(ringColor, isOnline, false, language),
                      const SizedBox(height: 16),
                      Text(
                        contact.name,
                        style: const TextStyle(
                          fontSize: 28.0,
                          fontWeight: FontWeight.bold,
                          color: kTextNavy,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Row of Action Circle Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Button 1: Normal Phone Call (Green)
                    _buildCircularActionButton(
                      context: context,
                      color: kCallGreen,
                      icon: Icons.phone,
                      label: callLabel,
                      semanticsLabel: "Phone Call ${contact.name}",
                      onTap: () {
                        Navigator.pop(context);
                        ref.read(audioCallServiceProvider).makeCall(context, contact);
                      },
                    ),

                    // Button 2: WhatsApp Video Call (Blue)
                    _buildCircularActionButton(
                      context: context,
                      color: kVideoBlue,
                      icon: Icons.videocam,
                      label: videoLabel,
                      semanticsLabel: "Video Call ${contact.name}",
                      isEnabled: hasWhatsapp,
                      onTap: hasWhatsapp
                          ? () {
                              Navigator.pop(context);
                              ref.read(whatsAppCallServiceProvider).makeVideoCall(context, contact);
                            }
                          : () {
                              HapticFeedback.vibrate();
                              ref.read(ttsServiceProvider).speak(
                                language == 'te' ? 'à°µà°¾à°Ÿà±à°¸à°¾à°ªà± à°¨à±†à°‚à°¬à°°à± à°²à±‡à°¦à±' : (language == 'hi' ? 'à¤µà¥à¤¹à¤¾à¤Ÿà¥à¤¸à¤à¤ª à¤¨à¤‚à¤¬à¤° à¤¨à¤¹à¥€à¤‚ à¤¹à¥ˆ' : 'No WhatsApp number'),
                              );
                            },
                    ),

                    // Button 3: Voice Message (Orange)
                    _buildCircularActionButton(
                      context: context,
                      color: kMessageOrange,
                      icon: Icons.mic,
                      label: voiceLabel,
                      semanticsLabel: "Voice Message ${contact.name}",
                      isEnabled: hasWhatsapp,
                      onTap: hasWhatsapp
                          ? () async {
                              Navigator.pop(context);
                              final path = await ref.read(recordingServiceProvider.notifier).startRecording();
                              if (path != null) {
                                ref.read(voiceMessageOverlayProvider.notifier).open(contact);
                              }
                            }
                          : () {
                              HapticFeedback.vibrate();
                              ref.read(ttsServiceProvider).speak(
                                language == 'te' ? 'à°µà°¾à°Ÿà±à°¸à°¾à°ªà± à°¨à±†à°‚à°¬à°°à± à°²à±‡à°¦à±' : (language == 'hi' ? 'à¤µà¥à¤¹à¤¾à¤Ÿà¥à¤¸à¤à¤ª à¤¨à¤‚à¤¬à¤° à¤¨à¤¹à¥€à¤‚ à¤¹à¥ˆ' : 'No WhatsApp number'),
                              );
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Close Button (Gray circle)
                Semantics(
                  label: language == 'te' ? 'à°®à±‚à°¸à°¿à°µà±‡à°¯à°¿' : (language == 'hi' ? 'à¤¬à¤‚à¤¦ à¤•à¤°à¥‡à¤‚' : 'Close'),
                  button: true,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: kTextSlate,
                        shape: const CircleBorder(),
                      ),
                      icon: const Icon(Icons.close, size: 28),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ref.read(ttsServiceProvider).stop();
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCircularActionButton({
    required BuildContext context,
    required Color color,
    required IconData icon,
    required String label,
    required String semanticsLabel,
    required VoidCallback onTap,
    bool isEnabled = true,
  }) {
    const double buttonSize = 80.0;
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: isEnabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isEnabled ? color : Colors.grey.shade100,
                foregroundColor: isEnabled ? Colors.white : Colors.grey.shade400,
                elevation: isEnabled ? 4 : 0,
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                shadowColor: isEnabled ? color.withValues(alpha: 0.3) : Colors.transparent,
                side: isEnabled
                    ? BorderSide.none
                    : BorderSide(color: Colors.grey.shade200, width: 1.5),
              ),
              onPressed: () {
                HapticFeedback.mediumImpact();
                onTap();
              },
              child: Icon(
                icon,
                size: 36,
                color: isEnabled ? Colors.white : Colors.grey.shade400,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isEnabled ? kTextNavy : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Color _getInitialsColor(int index) {
    final colors = [
      const Color(0xFF2196F3), // Blue (Manu)
      const Color(0xFFFFB300), // Gold/Yellow (Husband)
      const Color(0xFF4CAF50), // Green (Ammi)
      const Color(0xFFE91E63), // Pink (Santhosh)
      const Color(0xFFFF5722), // Orange/Coral (Nagesh)
      const Color(0xFF9C27B0), // Purple (Prashanthi)
      const Color(0xFF009688), // Teal (Ramadevi)
    ];
    return colors[index % colors.length];
  }

  Gradient _getInitialsGradient(int index) {
    final gradients = [
      const LinearGradient(
        colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // Indigo/Blue
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      const LinearGradient(
        colors: [Color(0xFFF59E0B), Color(0xFFB45309)], // Amber/Warm Gold
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      const LinearGradient(
        colors: [Color(0xFF10B981), Color(0xFF047857)], // Emerald/Teal
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      const LinearGradient(
        colors: [Color(0xFFEC4899), Color(0xFFBE185D)], // Pink/Magenta
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      const LinearGradient(
        colors: [Color(0xFFF97316), Color(0xFFC2410C)], // Orange/Rust
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      const LinearGradient(
        colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // Purple/Violet
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      const LinearGradient(
        colors: [Color(0xFF06B6D4), Color(0xFF0E7490)], // Cyan/Teal
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final language = settingsAsync.when(
      data: (settings) => settings.language,
      loading: () => 'en',
      error: (err, stack) => 'en',
    );
    final layoutMode = settingsAsync.when(
      data: (settings) => settings.activeLayoutMode,
      loading: () => 'classic',
      error: (err, stack) => 'classic',
    );

    final hasWhatsapp = contact.whatsappNumber != null && contact.whatsappNumber!.trim().isNotEmpty;
    final selection = ref.watch(photolessSelectionProvider);
    final isSelected = selection.contactId == contact.id;

    // Glowing border ring colors mapped based on position index
    final ringColors = [
      const Color(0xFF4CAF50), // Green (Santhosh)
      const Color(0xFF9C27B0), // Purple (Anitha)
      const Color(0xFFE91E63), // Pink (Nandini)
      const Color(0xFFFF5722), // Orange (Latha Akka)
      const Color(0xFFFFC107), // Yellow (Ramesh Mama)
      const Color(0xFF009688), // Teal (Vikram)
    ];
    final ringColor = ringColors[contact.positionIndex % ringColors.length];

    // Santhosh (index 0) gets a green active status dot
    final isOnline = contact.positionIndex == 0;

    if (layoutMode == 'classic') {
      final hasPhoto = contact.photoPath != null && contact.photoPath!.isNotEmpty;
      return RepaintBoundary(
        child: Semantics(
          label: "Contact card for ${contact.name}",
          container: true,
          child: Card(
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.05),
            color: Colors.white, // White card for unified premium light mode
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: isSelected
                  ? BorderSide(color: ringColor, width: 3.0)
                  : const BorderSide(color: Color(0xFFE2E8F0), width: 1.5), // Slate 200 border
            ),
            child: InkWell(
              onTap: () => _handleTap(context, ref),
              onLongPress: () => _showSeniorActionSheet(context, ref),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 1. Large Rounded Square initials / photo with optional TAP AGAIN overlay
                    AspectRatio(
                      aspectRatio: 1.0,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: double.infinity,
                            height: double.infinity,
                            decoration: BoxDecoration(
                              color: hasPhoto ? null : _getInitialsColor(contact.positionIndex),
                              borderRadius: BorderRadius.circular(12),
                              image: hasPhoto
                                  ? DecorationImage(
                                      image: ResizeImage(
                                        FileImage(File(contact.photoPath!)),
                                        width: 180,
                                        height: 180,
                                      ),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: hasPhoto
                                ? null
                                : Text(
                                    _getInitials(contact.name),
                                    style: const TextStyle(
                                      fontSize: 24.0,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                          if (isSelected && !hasPhoto)
                            Positioned(
                              bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: ringColor,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  language == 'te' ? 'మళ్ళీ నొక్కు' : (language == 'hi' ? 'फिर दबाएं' : 'TAP AGAIN'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8.0),

                    // 2. Name Text (Supports 2 Lines for perfect legibility without scaling down)
                    SizedBox(
                      width: double.infinity,
                      height: 34.0,
                      child: Text(
                        contact.name,
                        style: const TextStyle(
                          fontSize: 13.5, // Legible font size
                          fontWeight: FontWeight.bold,
                          color: kTextNavy, // Dark Navy font color for perfect light mode contrast
                          height: 1.15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: Semantics(
        label: "Contact card for ${contact.name}",
        container: true,
        child: Card(
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          color: kCardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            // Subtle visual highlight border indicating "tap again to call"
            side: isSelected ? BorderSide(color: ringColor, width: 3.5) : BorderSide.none,
          ),
        child: InkWell(
          onTap: () => _handleTap(context, ref),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.only(top: 10.0, bottom: 8.0, left: 6.0, right: 6.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Photo with colored ring and optional online status indicator
                _buildPhoto(ringColor, isOnline, isSelected, language),
                const SizedBox(height: 6.0),
                
                // 2. Name Text (Supports 2 Lines for perfect legibility without scaling down)
                SizedBox(
                  width: double.infinity,
                  height: 42.0,
                  child: Text(
                    contact.name,
                    style: const TextStyle(
                      fontSize: 16.0,
                      fontWeight: FontWeight.w900,
                      color: kTextNavy,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8.0),
                
                // 3. Action Buttons Row (Call, Video, Voice) with generous gaps
                Row(
                  children: [
                    // Phone (Call) Button Column
                    Expanded(
                      child: _buildActionButtonColumn(
                        context: context,
                        color: kCallGreen,
                        icon: Icons.phone,
                        label: "Call",
                        semanticsLabel: "Call ${contact.name}",
                        onTap: () => _handleTap(context, ref),
                      ),
                    ),
                    
                    // Video Button Column
                    Expanded(
                      child: _buildActionButtonColumn(
                        context: context,
                        color: kVideoBlue,
                        icon: Icons.videocam,
                        label: "Video",
                        semanticsLabel: "Video call ${contact.name}",
                        onTap: hasWhatsapp
                            ? () {
                                ref.read(whatsAppCallServiceProvider).makeVideoCall(context, contact);
                              }
                            : null,
                      ),
                    ),
                    
                    // Mic (Voice Message) Button Column
                    Expanded(
                      child: _buildActionButtonColumn(
                        context: context,
                        color: kMessageOrange,
                        icon: Icons.mic,
                        label: "Voice",
                        semanticsLabel: "Send voice message to ${contact.name}",
                        onTap: () async {
                          final path = await ref.read(recordingServiceProvider.notifier).startRecording();
                          if (path != null) {
                            ref.read(voiceMessageOverlayProvider.notifier).open(contact);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildPhoto(Color ringColor, bool isOnline, bool isSelected, String language) {
    final hasPhoto = contact.photoPath != null && contact.photoPath!.isNotEmpty;
    const photoSize = 84.0;

    return Semantics(
      label: "${contact.name}'s profile photo",
      image: true,
      child: Stack(
        alignment: Alignment.center,
        children: [
        Container(
          width: photoSize + 12,
          height: photoSize + 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              // Pulsing / highlighted border ring visual cue
              color: isSelected ? ringColor : ringColor.withValues(alpha: 0.4),
              width: isSelected ? 4.0 : 2.0,
            ),
          ),
          padding: const EdgeInsets.all(5.0),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasPhoto ? null : Colors.transparent,
              gradient: hasPhoto ? null : _getInitialsGradient(contact.positionIndex),
              image: hasPhoto
                  ? DecorationImage(
                      image: ResizeImage(
                        FileImage(File(contact.photoPath!)),
                        width: 180,
                        height: 180,
                      ),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: hasPhoto
                ? null
                : Text(
                    _getInitials(contact.name),
                    style: const TextStyle(
                      fontSize: 24.0,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          offset: Offset(0, 1.5),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        if (isOnline)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.0),
              ),
            ),
          ),
        if (isSelected && !hasPhoto)
          Positioned(
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ringColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                language == 'te' ? 'మళ్ళీ నొక్కు' : (language == 'hi' ? 'फिर दबाएं' : 'TAP AGAIN'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtonColumn({
    required BuildContext context,
    required Color color,
    required IconData icon,
    required String label,
    required String semanticsLabel,
    required VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    return RepaintBoundary(
      child: Semantics(
        label: semanticsLabel,
        button: true,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44.0,
                      height: 44.0,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isEnabled ? color : Colors.grey[300],
                        boxShadow: isEnabled
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        icon,
                        size: 22.0,
                        color: isEnabled ? Colors.white : Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        color: kTextSlate,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
