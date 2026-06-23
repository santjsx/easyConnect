import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/features/alarm/models/alarm_model.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/services/firebase_sync_service.dart';
import 'package:google_fonts/google_fonts.dart';

class AlarmRingScreen extends ConsumerStatefulWidget {
  final Alarm alarm;

  const AlarmRingScreen({
    super.key,
    required this.alarm,
  });

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen> {
  static const _platform = MethodChannel('com.easyconnect.app/calling');
  late final Timer _ttsTimer;

  @override
  void initState() {
    super.initState();
    // 1. Set max volume and start vibration natively
    _initNativeAlarmAlerts();

    // 2. Initial TTS announcement
    _speakPrompt();

    // 3. Loop TTS announcement every 7 seconds
    _ttsTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      _speakPrompt();
    });
  }

  Future<void> _initNativeAlarmAlerts() async {
    try {
      await _platform.invokeMethod('setMaxVolume');
      await _platform.invokeMethod('startVibration');
    } catch (e) {
      debugPrint("Error initializing native alarm alerts: $e");
    }
  }

  @override
  void dispose() {
    _ttsTimer.cancel();
    _stopNativeAlarmAlerts();
    super.dispose();
  }

  Future<void> _stopNativeAlarmAlerts() async {
    try {
      await _platform.invokeMethod('stopVibration');
      await ref.read(ttsServiceProvider).stop();
    } catch (e) {
      debugPrint("Error stopping native alarm alerts: $e");
    }
  }

  Future<void> _speakPrompt() async {
    final String label = widget.alarm.label.trim();
    String alertMsg = '';
    
    final lowerLabel = label.toLowerCase();
    if (lowerLabel.contains('medicine') || lowerLabel.contains('tablet') || label.contains('మందులు') || label.contains('మాత్రలు')) {
      alertMsg = "మందులు వేసుకునే సమయం అయింది. దయచేసి మందులు వేసుకోండి.";
    } else if (lowerLabel.contains('food') || lowerLabel.contains('lunch') || lowerLabel.contains('dinner') || lowerLabel.contains('breakfast') || label.contains('భోజనం') || label.contains('అన్నం')) {
      alertMsg = "భోజనం చేసే సమయం అయింది. దయచేసి భోజనం చేయండి.";
    } else if (lowerLabel.contains('sleep') || lowerLabel.contains('bed') || label.contains('నిద్ర') || label.contains('పడుకో')) {
      alertMsg = "నిద్రపోయే సమయం అయింది. దయచేసి విశ్రాంతి తీసుకోండి.";
    } else {
      alertMsg = "అలారం! $label సమయం అయింది. అలారం ఆపడానికి స్క్రీన్ మీద నొక్కండి.";
    }

    await ref.read(ttsServiceProvider).speak(alertMsg, forceLanguage: 'te');
  }

  Future<void> _dismissAlarm() async {
    HapticFeedback.heavyImpact();
    await _stopNativeAlarmAlerts();

    if (widget.alarm.days.isEmpty) {
      widget.alarm.isEnabled = false;
      await widget.alarm.save();
      await ref.read(firebaseSyncServiceProvider).updateAlarm(widget.alarm);
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  String _formatTime(String time24) {
    try {
      final parts = time24.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour % 12 == 0 ? 12 : hour % 12;
      final minuteStr = minute.toString().padLeft(2, '0');
      return '$hour12:$minuteStr $period';
    } catch (_) {
      return time24;
    }
  }

  String _formatDays(List<int> days) {
    if (days.isEmpty) return "Once";
    if (days.length == 7) return "Daily";
    final Map<int, String> dayNames = {
      1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"
    };
    return days.map((d) => dayNames[d] ?? '').join(', ');
  }

  String _getTeluguText() {
    final String label = widget.alarm.label.toLowerCase();
    if (label.contains('medicine') || label.contains('tablet') || label.contains('మందులు') || label.contains('మాత్రలు')) {
      return "మందులు వేసుకోండి";
    } else if (label.contains('food') || label.contains('lunch') || label.contains('dinner') || label.contains('breakfast') || label.contains('భోజనం') || label.contains('అన్నం')) {
      return "భోజనం చేయండి";
    } else if (label.contains('sleep') || label.contains('bed') || label.contains('నిద్ర') || label.contains('పడుకో')) {
      return "విశ్రాంతి తీసుకోండి";
    }
    return "సమయం అయింది";
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF085041),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                // Warning Header
                Text(
                  "MEDICINE REMINDER",
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF5DCAA5),
                    letterSpacing: 0.08 * 10.0,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),

                // Icon circle: 90x90, white 0.1 bg, pill icon 40px
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.medical_services_outlined,
                    color: Color(0xFF9FE1CB),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),

                // Time / Repeat Label
                Text(
                  "${_formatTime(widget.alarm.time)} · ${_formatDays(widget.alarm.days)}",
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF9FE1CB),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Alarm Title Text
                Text(
                  widget.alarm.label,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFE1F5EE),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Telugu Text
                Text(
                  _getTeluguText(),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF5DCAA5),
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),

                // Audio card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.volume_up,
                        color: Color(0xFF9FE1CB),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Reading alarm aloud...",
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF9FE1CB),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Draggable Swipe-to-dismiss slider
                _SwipeDismissSlider(
                  onDismiss: _dismissAlarm,
                  label: "Slide to dismiss",
                ),
                const SizedBox(height: 12),

                // Snooze hint
                Text(
                  "Swipe to snooze 10 min",
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeDismissSlider extends StatefulWidget {
  final VoidCallback onDismiss;
  final String label;

  const _SwipeDismissSlider({
    required this.onDismiss,
    required this.label,
  });

  @override
  State<_SwipeDismissSlider> createState() => _SwipeDismissSliderState();
}

class _SwipeDismissSliderState extends State<_SwipeDismissSlider>
    with SingleTickerProviderStateMixin {
  double _dragValue = 0.0;
  late AnimationController _springController;
  late Animation<double> _springAnimation;
  double _sliderWidth = 0.0;
  final double _thumbSize = 52.0;
  final double _padding = 6.0;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _springAnimation = CurvedAnimation(
      parent: _springController,
      curve: Curves.easeOutBack,
    );
    _springController.addListener(() {
      setState(() {
        _dragValue = _dragValue * (1.0 - _springAnimation.value);
      });
    });
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _sliderWidth = constraints.maxWidth;
        final maxDrag = _sliderWidth - _thumbSize - (_padding * 2);

        return Container(
          width: double.infinity,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(32),
          ),
          padding: EdgeInsets.all(_padding),
          child: Stack(
            children: [
              Center(
                child: Opacity(
                  opacity: (1.0 - (_dragValue / maxDrag)).clamp(0.1, 0.5),
                  child: Text(
                    widget.label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _dragValue,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragValue = (_dragValue + details.delta.dx).clamp(0.0, maxDrag);
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_dragValue >= maxDrag * 0.85) {
                      widget.onDismiss();
                    } else {
                      _springController.forward(from: 0.0);
                    }
                  },
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Color(0xFF085041),
                      size: 24,
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
