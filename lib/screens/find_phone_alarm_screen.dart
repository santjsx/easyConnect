import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:google_fonts/google_fonts.dart';

class FindPhoneAlarmScreen extends ConsumerStatefulWidget {
  final String familyCode;

  const FindPhoneAlarmScreen({
    super.key,
    required this.familyCode,
  });

  @override
  ConsumerState<FindPhoneAlarmScreen> createState() => _FindPhoneAlarmScreenState();
}

class _FindPhoneAlarmScreenState extends ConsumerState<FindPhoneAlarmScreen>
    with TickerProviderStateMixin {
  static const _platform = MethodChannel('com.easyconnect.app/calling');
  late AnimationController _rotationController;
  late AnimationController _rippleController;
  late final Timer _ttsTimer;

  @override
  void initState() {
    super.initState();

    // Immersive fullscreen mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _initNativeAlarmAlerts();
    _speakPrompt();

    _ttsTimer = Timer.periodic(const Duration(seconds: 6), (_) {
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
    _rotationController.dispose();
    _rippleController.dispose();
    _ttsTimer.cancel();
    _stopNativeAlarmAlerts();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    final lang = settingsBox != null && settingsBox.isNotEmpty ? settingsBox.values.first.language : 'en';

    String alertMsg = '';
    if (lang == 'te') {
      alertMsg = "నేను ఇక్కడ ఉన్నాను! నన్ను తీసుకో!";
    } else if (lang == 'hi') {
      alertMsg = "मैं यहाँ हूँ! मुझे उठाओ!";
    } else {
      alertMsg = "I am here! Come pick me up!";
    }

    await ref.read(ttsServiceProvider).speak(alertMsg, forceLanguage: lang);
  }

  Future<void> _dismissAlarm() async {
    HapticFeedback.heavyImpact();
    await _stopNativeAlarmAlerts();

    try {
      await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyCode)
          .collection('commands')
          .doc('find_phone')
          .set({
        'trigger': false,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error resetting Firestore find_phone command: $e");
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF26215C),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                // Header
                Text(
                  "REMOTE COMMAND",
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF7F77DD),
                    letterSpacing: 0.08 * 10.0,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),

                // Pulsing + Rotating Icon
                _buildPulsingRotatingPhoneIcon(),
                const SizedBox(height: 36),

                // Title
                Text(
                  "Find my phone",
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFEEEDFE),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),

                // Telugu Title
                Text(
                  "ఫోన్ మోగుతోంది",
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF7F77DD),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Subtitle
                Text(
                  "Triggered remotely by caregiver from web dashboard",
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF7F77DD).withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),

                // Sender Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person,
                        color: Color(0xFF7F77DD),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Sent by: Santhosh",
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFFEEEDFE),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Via web dashboard · just now",
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF7F77DD).withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Draggable Stop Slider
                _SwipeStopSlider(
                  onStop: _dismissAlarm,
                  label: "Slide to stop ringing",
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPulsingRotatingPhoneIcon() {
    const double baseSize = 84.0;
    final colorTint = const Color(0xFF7F77DD);

    return AnimatedBuilder(
      animation: _rippleController,
      builder: (context, child) {
        final progress = _rippleController.value;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Concentric Ring 3
            Container(
              width: baseSize + 60.0 * (1.0 + progress * 0.1),
              height: baseSize + 60.0 * (1.0 + progress * 0.1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorTint.withOpacity((0.05 * (1.0 - progress)).clamp(0.0, 1.0)),
              ),
            ),
            // Concentric Ring 2
            Container(
              width: baseSize + 40.0 * (1.0 + progress * 0.1),
              height: baseSize + 40.0 * (1.0 + progress * 0.1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorTint.withOpacity((0.10 * (1.0 - progress)).clamp(0.0, 1.0)),
              ),
            ),
            // Concentric Ring 1
            Container(
              width: baseSize + 20.0 * (1.0 + progress * 0.1),
              height: baseSize + 20.0 * (1.0 + progress * 0.1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorTint.withOpacity((0.15 * (1.0 - progress)).clamp(0.0, 1.0)),
              ),
            ),

            // Center circle with rotation transition
            RotationTransition(
              turns: _rotationController,
              child: Container(
                width: baseSize,
                height: baseSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorTint.withOpacity(0.2),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.phone_android_rounded,
                  color: Color(0xFFAFA9EC),
                  size: 38,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SwipeStopSlider extends StatefulWidget {
  final VoidCallback onStop;
  final String label;

  const _SwipeStopSlider({
    required this.onStop,
    required this.label,
  });

  @override
  State<_SwipeStopSlider> createState() => _SwipeStopSliderState();
}

class _SwipeStopSliderState extends State<_SwipeStopSlider>
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
            color: const Color(0xFF7F77DD).withOpacity(0.15),
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
                      color: const Color(0xFFEEEDFE),
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
                      widget.onStop();
                    } else {
                      _springController.forward(from: 0.0);
                    }
                  },
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFEEEDFE),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Color(0xFF3C3489),
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
