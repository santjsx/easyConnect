import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/features/settings/screens/admin_screen.dart';
import 'package:easyconnect/services/tts_service.dart';

class PinEntryScreen extends ConsumerStatefulWidget {
  const PinEntryScreen({super.key});

  @override
  ConsumerState<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends ConsumerState<PinEntryScreen> {
  final GlobalKey<ShakeWidgetState> _shakeKey = GlobalKey<ShakeWidgetState>();
  
  final List<int> _enteredDigits = [];
  String? _firstEnteredPin;
  bool _isSettingMode = true;
  bool _isConfirmingStage = false;
  int _failedAttempts = 0;
  
  Timer? _lockoutTimer;
  int _lockoutTimeRemaining = 0;
  DateTime? _lockoutEndTime;

  @override
  void initState() {
    super.initState();
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    if (settingsBox != null && settingsBox.isNotEmpty) {
      final settings = settingsBox.values.first;
      _isSettingMode = settings.adminPin.isEmpty;
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  bool get _isLockedOut {
    if (_lockoutEndTime == null) return false;
    return DateTime.now().isBefore(_lockoutEndTime!);
  }

  void _startLockout() {
    setState(() {
      _lockoutTimeRemaining = 30;
      _lockoutEndTime = DateTime.now().add(const Duration(seconds: 30));
      _enteredDigits.clear();
    });

    ref.read(ttsServiceProvider).speak("Too many attempts. Please wait.");

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lockoutEndTime == null) {
        timer.cancel();
        return;
      }
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = _lockoutEndTime!.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        timer.cancel();
        setState(() {
          _lockoutTimeRemaining = 0;
          _lockoutEndTime = null;
          _failedAttempts = 0;
        });
      } else {
        setState(() {
          _lockoutTimeRemaining = remaining;
        });
      }
    });
  }

  void _onKeyPress(int digit) {
    if (_isLockedOut) return;
    if (_enteredDigits.length >= 4) return;
    
    HapticFeedback.lightImpact();
    setState(() {
      _enteredDigits.add(digit);
    });
  }

  void _onBackspace() {
    if (_isLockedOut) return;
    if (_enteredDigits.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() {
      _enteredDigits.removeLast();
    });
  }

  Future<void> _onConfirm() async {
    if (_isLockedOut) return;
    if (_enteredDigits.length < 4) {
      HapticFeedback.vibrate();
      _shakeKey.currentState?.shake();
      return;
    }

    final enteredPin = _enteredDigits.join();

    if (_isSettingMode) {
      if (!_isConfirmingStage) {
        // First entry in set mode
        HapticFeedback.mediumImpact();
        setState(() {
          _firstEnteredPin = enteredPin;
          _isConfirmingStage = true;
          _enteredDigits.clear();
        });
      } else {
        // Confirming entry in set mode
        if (enteredPin == _firstEnteredPin) {
          // Pins match, save to Hive
          HapticFeedback.heavyImpact();
          try {
            final Box<AppSettings> settingsBox;
            if (Hive.isBoxOpen('settings')) {
              settingsBox = Hive.box<AppSettings>('settings');
            } else {
              settingsBox = await Hive.openBox<AppSettings>('settings');
            }
            if (settingsBox.isNotEmpty) {
              final settings = settingsBox.values.first;
              settings.adminPin = enteredPin;
              await settings.save();
            } else {
              await settingsBox.add(AppSettings(adminPin: enteredPin));
            }
            
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const AdminScreen()),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to save PIN: $e'), backgroundColor: kSosRed),
              );
            }
          }
        } else {
          // Pins do not match
          HapticFeedback.vibrate();
          _shakeKey.currentState?.shake();
          setState(() {
            _enteredDigits.clear();
            _isConfirmingStage = false;
            _firstEnteredPin = null;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('PINs did not match. Please start over.'),
                backgroundColor: kSosRed,
              ),
            );
          }
        }
      }
    } else {
      final Box<AppSettings> settingsBox;
      if (Hive.isBoxOpen('settings')) {
        settingsBox = Hive.box<AppSettings>('settings');
      } else {
        settingsBox = await Hive.openBox<AppSettings>('settings');
      }
      final savedPin = settingsBox.isNotEmpty ? settingsBox.values.first.adminPin : '';

      if (enteredPin == savedPin) {
        HapticFeedback.heavyImpact();
        setState(() {
          _failedAttempts = 0;
          _enteredDigits.clear();
        });
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AdminScreen()),
          );
        }
      } else {
        HapticFeedback.vibrate();
        _shakeKey.currentState?.shake();
        setState(() {
          _enteredDigits.clear();
          _failedAttempts++;
        });

        if (_failedAttempts >= 3) {
          _startLockout();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Incorrect PIN. ${3 - _failedAttempts} attempts remaining.'),
                backgroundColor: kSosRed,
              ),
            );
          }
        }
      }
    }
  }

  String _getTitleText() {
    if (_isLockedOut) {
      return 'Locked Out';
    }
    if (_isSettingMode) {
      return _isConfirmingStage ? 'Confirm Admin PIN' : 'Set your PIN';
    }
    return 'Enter Admin PIN';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              const Spacer(flex: 1),
              
              // Centered Title
              Text(
                _getTitleText(),
                style: const TextStyle(
                  fontSize: 20.0,
                  fontWeight: FontWeight.bold,
                  color: kTextDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Locked Out Countdown or Subtitle
              if (_isLockedOut)
                Text(
                  'Please wait $_lockoutTimeRemaining seconds',
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w600,
                    color: kSosRed,
                  ),
                  textAlign: TextAlign.center,
                )
              else
                Text(
                  _isSettingMode
                      ? (_isConfirmingStage
                          ? 'Enter the 4-digit PIN again to confirm.'
                          : 'Create a 4-digit PIN to secure admin settings.')
                      : 'Enter your caregiver passcode.',
                  style: TextStyle(
                    fontSize: 14.0,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),

              const Spacer(flex: 1),

              // Digit Display Boxes Row with Shake effect
              ShakeWidget(
                key: _shakeKey,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final hasDigit = index < _enteredDigits.length;
                    return Container(
                      width: 48.0,
                      height: 48.0,
                      margin: const EdgeInsets.symmetric(horizontal: 8.0),
                      decoration: BoxDecoration(
                        color: _isLockedOut ? Colors.grey.shade100 : Colors.white,
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(
                          color: _isLockedOut
                              ? Colors.grey.shade300
                              : (hasDigit ? kCallGreen : Colors.grey.shade300),
                          width: hasDigit ? 2.5 : 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          hasDigit ? '*' : '',
                          style: const TextStyle(
                            fontSize: 24.0,
                            fontWeight: FontWeight.bold,
                            color: kTextDark,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              const Spacer(flex: 2),

              // 3x4 Numpad
              IgnorePointer(
                ignoring: _isLockedOut,
                child: Opacity(
                  opacity: _isLockedOut ? 0.4 : 1.0,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildNumButton(1),
                          _buildNumButton(2),
                          _buildNumButton(3),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildNumButton(4),
                          _buildNumButton(5),
                          _buildNumButton(6),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildNumButton(7),
                          _buildNumButton(8),
                          _buildNumButton(9),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildIconButton(Icons.backspace_outlined, _onBackspace),
                          _buildNumButton(0),
                          _buildIconButton(Icons.check, _onConfirm, color: kCallGreen),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumButton(int number) {
    return SizedBox(
      width: 72.0,
      height: 72.0,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey.shade100,
          foregroundColor: kTextDark,
          shape: const CircleBorder(),
          elevation: 1,
          padding: EdgeInsets.zero,
        ),
        onPressed: () => _onKeyPress(number),
        child: Text(
          '$number',
          style: const TextStyle(
            fontSize: 28.0,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onPressed, {Color? color}) {
    return SizedBox(
      width: 72.0,
      height: 72.0,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color?.withValues(alpha: 0.15) ?? Colors.grey.shade100,
          foregroundColor: color ?? kTextDark,
          shape: const CircleBorder(),
          elevation: 1,
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed,
        child: Icon(
          icon,
          size: 28.0,
        ),
      ),
    );
  }
}

// Shake Animation Helper Widget
class ShakeWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double shakeDistance;

  const ShakeWidget({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 350),
    this.shakeDistance = 16.0,
  });

  @override
  State<ShakeWidget> createState() => ShakeWidgetState();
}

class ShakeWidgetState extends State<ShakeWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void shake() {
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> offsetAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: widget.shakeDistance), weight: 1),
      TweenSequenceItem(tween: Tween(begin: widget.shakeDistance, end: -widget.shakeDistance), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -widget.shakeDistance, end: widget.shakeDistance), weight: 2),
      TweenSequenceItem(tween: Tween(begin: widget.shakeDistance, end: 0.0), weight: 1),
    ]).animate(_controller);

    return AnimatedBuilder(
      animation: offsetAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(offsetAnimation.value, 0.0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
