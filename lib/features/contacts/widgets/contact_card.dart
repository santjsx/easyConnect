import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/calling/services/audio_call_service.dart';
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

  Color _getContactColor(String name) {
    final cleanName = name.trim().toLowerCase();
    if (cleanName.contains('tsunami')) return const Color(0xFFE24B4A);
    if (cleanName.contains('santhosh')) return const Color(0xFF1D9E75);
    if (cleanName.contains('manu')) return const Color(0xFF534AB7);
    if (cleanName.contains('ammi')) return const Color(0xFF3C3489);
    if (cleanName.contains('prasanthi') || cleanName.contains('anusha') || cleanName.contains('jyothi')) return const Color(0xFFEF9F27);
    if (cleanName.contains('aruna') || cleanName.contains('krishnaveni')) return const Color(0xFF1D9E75);
    if (cleanName.contains('bhadramma')) return const Color(0xFFD4537E);
    if (cleanName.contains('dhanamma')) return const Color(0xFF378ADD);
    if (cleanName.contains('gs reddy')) return const Color(0xFF534AB7);
    
    final colors = [
      const Color(0xFF534AB7),
      const Color(0xFF1D9E75),
      const Color(0xFFEF9F27),
      const Color(0xFFE24B4A),
      const Color(0xFF378ADD),
      const Color(0xFFD4537E),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  Map<String, Color> _getContactTints(Color contactColor) {
    final hex = contactColor.value & 0xFFFFFF;
    if (hex == 0xE24B4A) {
      return {'bg': const Color(0xFFFCEBEB), 'text': const Color(0xFFA32D2D)};
    }
    if (hex == 0xFF2147) {
      return {'bg': const Color(0xFFFCEBEB), 'text': const Color(0xFFA32D2D)};
    }
    if (hex == 0xFF4B6E) {
      return {'bg': const Color(0xFFFCEBEB), 'text': const Color(0xFFA32D2D)};
    }
    if (hex == 0xFF3D00) {
      return {'bg': const Color(0xFFFCEBEB), 'text': const Color(0xFFA32D2D)};
    }
    if (hex == 0x1D9E75 || hex == 0x0F6E56) {
      return {'bg': const Color(0xFFE1F5EE), 'text': const Color(0xFF0F6E56)};
    }
    if (hex == 0x534AB7) {
      return {'bg': const Color(0xFFEEEDFE), 'text': const Color(0xFF534AB7)};
    }
    if (hex == 0x3C3489 || hex == 0x26215C) {
      return {'bg': const Color(0xFFEEEDFE), 'text': const Color(0xFF3C3489)};
    }
    if (hex == 0xFFB830) {
      return {'bg': const Color(0xFFFAEEDA), 'text': const Color(0xFF633806)};
    }
    if (hex == 0xFF8C00) {
      return {'bg': const Color(0xFFFAEEDA), 'text': const Color(0xFF633806)};
    }
    if (hex == 0xEF9F27) {
      return {'bg': const Color(0xFFFAEEDA), 'text': const Color(0xFF633806)};
    }
    if (hex == 0x378ADD) {
      return {'bg': const Color(0xFFE6F1FB), 'text': const Color(0xFF185FA5)};
    }
    if (hex == 0xD4537E) {
      return {'bg': const Color(0xFFFCEBEB), 'text': const Color(0xFFA32D2D)};
    }
    return {'bg': const Color(0xFFEEEDFE), 'text': const Color(0xFF534AB7)};
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

  void _handleTap(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    ref.read(ttsServiceProvider).stop();
    await _clearMissedCallIfPresent();

    // Custom voice label play if exists
    if (widget.contact.voiceLabelPath != null && widget.contact.voiceLabelPath!.isNotEmpty) {
      final file = File(widget.contact.voiceLabelPath!);
      if (await file.exists()) {
        try {
          final player = ref.read(audioPlayerProvider);
          await player.stop();
          await player.play(DeviceFileSource(widget.contact.voiceLabelPath!));
          // Wait briefly for sound to finish before placing call
          await Future.delayed(const Duration(milliseconds: 1500));
          if (context.mounted) {
            await ref.read(audioCallServiceProvider).makeCall(context, widget.contact);
          }
          return;
        } catch (e) {
          debugPrint("Error playing custom voice label: $e");
        }
      }
    }

    // Default call action sequence
    if (context.mounted) {
      await ref.read(audioCallServiceProvider).makeCall(context, widget.contact);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final layoutMode = settingsAsync.maybeWhen(
      data: (settings) => settings.activeLayoutMode,
      orElse: () => 'classic',
    );
    final isMissed = settingsAsync.maybeWhen(
      data: (settings) => settings.activeUnreadMissedCallContactIds.contains(widget.contact.id),
      orElse: () => false,
    );

    final isOnline = widget.contact.positionIndex == 0 || widget.contact.name.toLowerCase().contains('santhosh') || widget.contact.name.toLowerCase().contains('tsunami');

    // Get assigned contact color
    Color contactColor;
    try {
      if (widget.contact.colorTheme.startsWith('#')) {
        contactColor = getAccentColor(widget.contact.colorTheme);
      } else {
        contactColor = _getContactColor(widget.contact.name);
      }
    } catch (_) {
      contactColor = _getContactColor(widget.contact.name);
    }

    final tints = _getContactTints(contactColor);
    final bgTint = tints['bg']!;
    final textTint = tints['text']!;

    final hasPhoto = widget.contact.photoPath != null && widget.contact.photoPath!.isNotEmpty;

    final isClassic = layoutMode == 'classic';
    final double cardRadius = isClassic ? 12.0 : 14.0;
    final double avatarRadius = isClassic ? 12.0 : 14.0;
    final double avatarFontSize = isClassic ? 11.0 : 20.0;
    final double nameFontSize = 10.0;

    return _InteractiveTouchScale(
      onTap: widget.isEditing ? null : () => _handleTap(context, ref),
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final borderGlowColor = isMissed
              ? Color.lerp(Theme.of(context).dividerColor, kAccentRed, _pulseAnimation.value)!
              : contactColor;

          return Semantics(
            label: "Contact card for ${widget.contact.name}. Double tap to call.",
            button: true,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(cardRadius),
                boxShadow: isMissed
                    ? [
                        BoxShadow(
                          color: kAccentRed.withValues(alpha: 0.22 * _pulseAnimation.value),
                          blurRadius: 12 + 6 * _pulseAnimation.value,
                          spreadRadius: 1 + 1 * _pulseAnimation.value,
                        ),
                      ]
                    : null,
              ),
              child: Card(
                elevation: 0,
                color: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(cardRadius),
                  side: BorderSide(
                    color: isMissed ? borderGlowColor : contactColor,
                    width: isMissed ? 2.5 : 2.0, // 2px solid colored border
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Avatar Area (Square aspect ratio)
                      AspectRatio(
                        aspectRatio: 1.0,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: bgTint, // bg=color-tint matching border
                                borderRadius: BorderRadius.circular(avatarRadius),
                              ),
                              alignment: Alignment.center,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(avatarRadius),
                                child: hasPhoto
                                    ? Image.file(
                                        File(widget.contact.photoPath!),
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                        errorBuilder: (context, error, stackTrace) => Text(
                                          _getInitials(widget.contact.name),
                                          style: GoogleFonts.inter(
                                            fontSize: avatarFontSize,
                                            fontWeight: FontWeight.w500, // weight 500
                                            color: textTint, // initials in matching dark color
                                          ),
                                        ),
                                      )
                                    : Text(
                                        _getInitials(widget.contact.name),
                                        style: GoogleFonts.inter(
                                          fontSize: avatarFontSize,
                                          fontWeight: FontWeight.w500,
                                          color: textTint,
                                        ),
                                      ),
                              ),
                            ),
                            // Online Dot
                            if (isOnline)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: kAccentGreen, // bg=#1D9E75
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5), // border 1.5px white
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Name label: 10px weight 500, centered
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                        child: Text(
                          widget.contact.name,
                          style: GoogleFonts.inter(
                            fontSize: nameFontSize,
                            fontWeight: FontWeight.w500, // weight 500
                            color: Theme.of(context).textTheme.bodyMedium?.color, // text-primary
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _scale = 0.96), // scale-down (0.96)
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
