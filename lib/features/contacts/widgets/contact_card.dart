import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/calling/services/audio_call_service.dart';
import 'package:easyconnect/features/calling/services/whatsapp_call_service.dart';
import 'package:easyconnect/features/voice_message/services/recording_service.dart';
import 'package:easyconnect/features/voice_message/widgets/recording_overlay.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:hive/hive.dart';
import 'package:audioplayers/audioplayers.dart';

final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(() {
    try {
      player.stop();
    } catch (_) {}
    player.dispose();
  });
  return player;
});

class PhotolessSelectionState {
  final String? contactId;
  final int lastTapTime;

  PhotolessSelectionState({this.contactId, this.lastTapTime = 0});
}

final photolessSelectionProvider = StateProvider<PhotolessSelectionState>((ref) {
  return PhotolessSelectionState();
});

class ContactCard extends ConsumerStatefulWidget {
  final Contact contact;
  final bool isEditing;

  const ContactCard({
    super.key,
    required this.contact,
    this.isEditing = false,
  });

  @override
  ConsumerState<ContactCard> createState() => _ContactCardState();
}

class _ContactCardState extends ConsumerState<ContactCard> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _clearMissedCallIfPresent() async {
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    if (settingsBox == null || settingsBox.isEmpty) return;
    final settings = settingsBox.values.first;
    final currentMissed = List<String>.from(settings.unreadMissedCallContactIds ?? []);
    if (currentMissed.contains(widget.contact.id)) {
      currentMissed.remove(widget.contact.id);
      settings.unreadMissedCallContactIds = currentMissed;
      await settings.save();
      ref.invalidate(settingsProvider);
    }
  }

  void _announceName(WidgetRef ref) async {
    final tts = ref.read(ttsServiceProvider);
    await tts.stop();

    final nameToSpeak = widget.contact.name.trim();
    if (nameToSpeak.isEmpty) {
      await tts.speak("No name");
      ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState();
      return;
    }

    // Play custom voice label if it exists
    if (widget.contact.voiceLabelPath != null && widget.contact.voiceLabelPath!.isNotEmpty) {
      final file = File(widget.contact.voiceLabelPath!);
      if (await file.exists()) {
        try {
          final player = ref.read(audioPlayerProvider);
          await player.stop();
          await player.play(DeviceFileSource(widget.contact.voiceLabelPath!));
          return;
        } catch (e) {
          debugPrint("Error playing custom voice label: $e");
        }
      }
    }

    try {
      await tts.speak(nameToSpeak);
    } catch (e) {
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 200));
      await HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.vibrate();
    }
  }

  Future<void> _executePreferredAction(BuildContext context, WidgetRef ref) async {
    final hasWhatsapp = widget.contact.whatsappNumber != null && widget.contact.whatsappNumber!.trim().isNotEmpty;
    
    if (widget.contact.preferredAction == 'video') {
      if (hasWhatsapp) {
        await ref.read(whatsAppCallServiceProvider).makeVideoCall(context, widget.contact);
      } else {
        await ref.read(ttsServiceProvider).speak('No WhatsApp number saved. Making a standard phone call.');
        await Future.delayed(const Duration(milliseconds: 1500));
        if (context.mounted) {
          await ref.read(audioCallServiceProvider).makeCall(context, widget.contact);
        }
      }
    } else if (widget.contact.preferredAction == 'message') {
      if (hasWhatsapp) {
        final path = await ref.read(recordingServiceProvider.notifier).startRecording();
        if (path != null) {
          ref.read(voiceMessageOverlayProvider.notifier).open(widget.contact);
        }
      } else {
        await ref.read(ttsServiceProvider).speak('No WhatsApp number saved. Making a standard phone call.');
        await Future.delayed(const Duration(milliseconds: 1500));
        if (context.mounted) {
          await ref.read(audioCallServiceProvider).makeCall(context, widget.contact);
        }
      }
    } else {
      await ref.read(audioCallServiceProvider).makeCall(context, widget.contact);
    }
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    HapticFeedback.lightImpact();
    ref.read(ttsServiceProvider).stop();
    _clearMissedCallIfPresent();

    final settings = ref.read(settingsProvider).value;
    final directTap = settings?.activeDirectTapPreferredAction ?? false;

    if (directTap) {
      _executePreferredAction(context, ref);
      return;
    }

    final hasPhoto = widget.contact.photoPath != null && widget.contact.photoPath!.isNotEmpty;
    if (hasPhoto) {
      _showSeniorActionSheet(context, ref);
      return;
    }

    final selection = ref.read(photolessSelectionProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    final isDoubleTapTooFast = selection.contactId == widget.contact.id && (now - selection.lastTapTime < 300);

    if (isDoubleTapTooFast) {
      ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState(
        contactId: widget.contact.id,
        lastTapTime: now,
      );
      _announceName(ref);
      return;
    }

    if (selection.contactId == widget.contact.id) {
      ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState();
      _showSeniorActionSheet(context, ref);
    } else {
      ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState(
        contactId: widget.contact.id,
        lastTapTime: now,
      );
      _announceName(ref);

      final currentId = widget.contact.id;
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
    final hasWhatsapp = widget.contact.whatsappNumber != null && widget.contact.whatsappNumber!.trim().isNotEmpty;

    final ringColor = _parseHexColor(widget.contact.colorTheme);
    final isOnline = widget.contact.positionIndex == 0;

    ref.read(ttsServiceProvider).speak(
      "To connect with ${widget.contact.name}, tap the green button for a phone call, the blue button for a video call, or the orange button for a voice message.",
    );

    final String callLabel = language == 'te' ? 'కాల్' : (language == 'hi' ? 'कॉल' : 'Call');
    final String videoLabel = language == 'te' ? 'వీడియో' : (language == 'hi' ? 'वीडियो' : 'Video');
    final String voiceLabel = language == 'te' ? 'వాయిస్' : (language == 'hi' ? 'वाय्स' : 'Voice');

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
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 24),

                Semantics(
                  label: "Connecting with ${widget.contact.name}",
                  container: true,
                  child: Column(
                    children: [
                      _buildPhoto(ringColor, isOnline, false, language, false),
                      const SizedBox(height: 16),
                      Text(
                        widget.contact.name,
                        style: GoogleFonts.nunito(
                          fontSize: 28.0,
                          fontWeight: FontWeight.bold,
                          color: kTextNavy,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildCircularActionButton(
                      context: context,
                      color: kCallGreen,
                      icon: Icons.phone,
                      label: callLabel,
                      semanticsLabel: "Phone Call ${widget.contact.name}",
                      onTap: () {
                        Navigator.pop(context);
                        ref.read(audioCallServiceProvider).makeCall(context, widget.contact);
                      },
                    ),

                    _buildCircularActionButton(
                      context: context,
                      color: kVideoBlue,
                      icon: Icons.videocam,
                      label: videoLabel,
                      semanticsLabel: "Video Call ${widget.contact.name}",
                      isEnabled: hasWhatsapp,
                      onTap: hasWhatsapp
                          ? () {
                              Navigator.pop(context);
                              ref.read(whatsAppCallServiceProvider).makeVideoCall(context, widget.contact);
                            }
                            : () {
                                HapticFeedback.vibrate();
                                ref.read(ttsServiceProvider).speak(
                                  "No WhatsApp number saved for ${widget.contact.name}.",
                                );
                              },
                    ),

                    _buildCircularActionButton(
                      context: context,
                      color: kMessageOrange,
                      icon: Icons.mic,
                      label: voiceLabel,
                      semanticsLabel: "Voice Message ${widget.contact.name}",
                      isEnabled: hasWhatsapp,
                      onTap: hasWhatsapp
                          ? () async {
                              Navigator.pop(context);
                              final path = await ref.read(recordingServiceProvider.notifier).startRecording();
                              if (path != null) {
                                ref.read(voiceMessageOverlayProvider.notifier).open(widget.contact);
                              }
                            }
                            : () {
                                HapticFeedback.vibrate();
                                ref.read(ttsServiceProvider).speak(
                                  "No WhatsApp number saved for ${widget.contact.name}.",
                                );
                              },
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                Semantics(
                  label: language == 'te' ? 'మూసిвеయి' : (language == 'hi' ? 'बंद करें' : 'Close'),
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
            child: _InteractiveTouchScale(
              onTap: isEnabled ? () {
                HapticFeedback.mediumImpact();
                ref.read(ttsServiceProvider).stop();
                onTap();
              } : null,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isEnabled ? color : Colors.grey.shade100,
                  boxShadow: isEnabled
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : null,
                  border: isEnabled
                      ? null
                      : Border.all(color: Colors.grey.shade200, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 36,
                  color: isEnabled ? Colors.white : Colors.grey.shade400,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isEnabled ? kTextNavy : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
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
    final isMissed = settingsAsync.maybeWhen(
      data: (settings) => settings.activeUnreadMissedCallContactIds.contains(widget.contact.id),
      orElse: () => false,
    );

    final hasWhatsapp = widget.contact.whatsappNumber != null && widget.contact.whatsappNumber!.trim().isNotEmpty;
    final selection = ref.watch(photolessSelectionProvider);
    final isSelected = selection.contactId == widget.contact.id;

    final ringColor = _parseHexColor(widget.contact.colorTheme);
    final isOnline = widget.contact.positionIndex == 0;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final borderGlowColor = isMissed
            ? Color.lerp(const Color(0xFFF2F2F8), const Color(0xFFFF2147), _pulseAnimation.value)!
            : ringColor;

        if (layoutMode == 'classic') {
          return RepaintBoundary(
            child: Semantics(
              label: "Contact card for ${widget.contact.name}",
              container: true,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: isMissed
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFF2147).withValues(alpha: 0.22 * _pulseAnimation.value),
                            blurRadius: 16 + 8 * _pulseAnimation.value,
                            spreadRadius: 2 + 2 * _pulseAnimation.value,
                          ),
                          BoxShadow(
                            color: const Color(0xFFFF2147).withValues(alpha: 0.15),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                ),
                child: Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: BorderSide(
                      color: isSelected ? ringColor : (widget.isEditing ? const Color(0xFF5C5BE8).withValues(alpha: 0.5) : borderGlowColor),
                      width: isSelected ? 3.0 : (widget.isEditing ? 2.0 : (isMissed ? 2.5 : 1.5)),
                    ),
                  ),
                  child: InkWell(
                    onTap: widget.isEditing ? null : () => _handleTap(context, ref),
                    onLongPress: widget.isEditing ? null : () => _showSeniorActionSheet(context, ref),
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 10, left: 8, right: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildPhoto(ringColor, isOnline, isSelected, language, isMissed),
                              const SizedBox(height: 6.0),
                              Text(
                                widget.contact.name,
                                style: GoogleFonts.nunito(
                                  fontSize: 14.0,
                                  fontWeight: FontWeight.bold,
                                  color: kTextNavy,
                                  height: 1.1,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        if (widget.isEditing)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: const Color(0xFF9999B0).withValues(alpha: 0.8),
                              size: 15,
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
            label: "Contact card for ${widget.contact.name}",
            container: true,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: isMissed
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFF2147).withValues(alpha: 0.22 * _pulseAnimation.value),
                          blurRadius: 16 + 8 * _pulseAnimation.value,
                          spreadRadius: 2 + 2 * _pulseAnimation.value,
                        ),
                        BoxShadow(
                          color: const Color(0xFFFF2147).withValues(alpha: 0.15),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
              ),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(
                    color: isSelected ? ringColor : (widget.isEditing ? const Color(0xFF5C5BE8).withValues(alpha: 0.5) : borderGlowColor),
                    width: isSelected ? 3.0 : (widget.isEditing ? 2.0 : (isMissed ? 2.5 : 1.5)),
                  ),
                ),
                child: InkWell(
                  onTap: widget.isEditing ? null : () => _handleTap(context, ref),
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildPhoto(ringColor, isOnline, isSelected, language, isMissed),
                            const SizedBox(height: 6.0),
                            Text(
                              widget.contact.name,
                              style: GoogleFonts.nunito(
                                fontSize: 15.0,
                                fontWeight: FontWeight.bold,
                                color: kTextNavy,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8.0),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildActionButtonColumn(
                                    context: context,
                                    color: const Color(0xFF32E08A),
                                    icon: Icons.phone,
                                    label: "Call",
                                    semanticsLabel: "Call ${widget.contact.name}",
                                    onTap: () => _handleTap(context, ref),
                                  ),
                                ),
                                Expanded(
                                  child: _buildActionButtonColumn(
                                    context: context,
                                    color: const Color(0xFF007AFF),
                                    icon: Icons.videocam,
                                    label: "Video",
                                    semanticsLabel: "Video call ${widget.contact.name}",
                                    onTap: hasWhatsapp
                                        ? () {
                                            ref.read(whatsAppCallServiceProvider).makeVideoCall(context, widget.contact);
                                          }
                                        : null,
                                  ),
                                ),
                                Expanded(
                                  child: _buildActionButtonColumn(
                                    context: context,
                                    color: const Color(0xFFFF8C00),
                                    icon: Icons.mic,
                                    label: "Voice",
                                    semanticsLabel: "Send voice message to ${widget.contact.name}",
                                    onTap: hasWhatsapp
                                        ? () async {
                                            final path = await ref.read(recordingServiceProvider.notifier).startRecording();
                                            if (path != null) {
                                              ref.read(voiceMessageOverlayProvider.notifier).open(widget.contact);
                                            }
                                          }
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (widget.isEditing)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Icon(
                            Icons.drag_handle_rounded,
                            color: const Color(0xFF9999B0).withValues(alpha: 0.8),
                            size: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhoto(Color ringColor, bool isOnline, bool isSelected, String language, bool isMissed) {
    final hasPhoto = widget.contact.photoPath != null && widget.contact.photoPath!.isNotEmpty;
    const photoSize = 66.0;

    return Semantics(
      label: "${widget.contact.name}'s profile photo",
      image: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: photoSize + 10,
          maxHeight: photoSize + 10,
        ),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: photoSize + 10,
                height: photoSize + 10,
                decoration: ShapeDecoration(
                  shape: ContinuousRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                    side: BorderSide(
                      color: isSelected ? ringColor : ringColor.withValues(alpha: 0.3),
                      width: isSelected ? 3.5 : 1.5,
                    ),
                  ),
                ),
                padding: const EdgeInsets.all(4.0),
                child: ClipPath(
                  clipper: ShapeBorderClipper(
                    shape: ContinuousRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: hasPhoto
                        ? Image.file(
                            File(widget.contact.photoPath!),
                              key: ValueKey(widget.contact.photoPath),
                              fit: BoxFit.cover,
                              width: photoSize,
                              height: photoSize,
                              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                if (wasSynchronouslyLoaded) return child;
                                return AnimatedOpacity(
                                  opacity: frame == null ? 0 : 1,
                                  duration: const Duration(milliseconds: 250),
                                  child: child,
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  key: const ValueKey('initials_error_fallback'),
                                  decoration: ShapeDecoration(
                                    gradient: _getContactGradient(widget.contact),
                                    shape: ContinuousRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _getInitials(widget.contact.name),
                                    style: GoogleFonts.nunito(
                                      fontSize: 22.0,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                );
                              },
                            )
                        : Container(
                            key: const ValueKey('initials'),
                            decoration: ShapeDecoration(
                              gradient: _getContactGradient(widget.contact),
                              shape: ContinuousRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _getInitials(widget.contact.name),
                              style: GoogleFonts.nunito(
                                fontSize: 22.0,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              if (isOnline)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF32E08A),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.0),
                    ),
                  ),
                ),
              if (isMissed)
                Positioned(
                  left: 2,
                  top: 2,
                  child: Transform.scale(
                    scale: 1.0 + 0.1 * _pulseAnimation.value,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF2147),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.phone_missed_rounded,
                        color: Colors.white,
                        size: 11,
                      ),
                    ),
                  ),
                ),
              if (isSelected && !hasPhoto)
                Positioned(
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: ShapeDecoration(
                      color: ringColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      language == 'te' ? 'మళ్ళీ నొక్కు' : (language == 'hi' ? 'फिर दबाएं' : 'TAP AGAIN'),
                      style: GoogleFonts.nunito(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
        child: _InteractiveTouchScale(
          onTap: isEnabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44.0,
                  height: 44.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isEnabled ? color : const Color(0xFFEEEEF8),
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
                    color: isEnabled ? Colors.white : const Color(0xFF9999B0),
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 10.0,
                    fontWeight: FontWeight.bold,
                    color: isEnabled ? kTextNavy : const Color(0xFF9999B0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InteractiveTouchScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _InteractiveTouchScale({required this.child, this.onTap});

  @override
  State<_InteractiveTouchScale> createState() => _InteractiveTouchScaleState();
}

class _InteractiveTouchScaleState extends State<_InteractiveTouchScale> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _scale = 0.92),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _scale = 1.0),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
