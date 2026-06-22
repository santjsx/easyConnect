import 'package:flutter/material.dart';

const Color kCallGreen = Color(0xFF32E08A);
const Color kVideoBlue = Color(0xFF007AFF);
const Color kMessageOrange = Color(0xFFFF8C00);
const Color kStopRed = Color(0xFFFF2147);
const Color kSosRed = Color(0xFFFF2147);
const Color kCardBackground = Color(0xFFFFFFFF);
const Color kTextDark = Color(0xFF0F172A); // Slate-900

// Premium Typography & Accents
const Color kTextNavy = Color(0xFF0F172A); // Slate-900
const Color kTextSlate = Color(0xFF475569); // Slate-600
const Color kAppBackground = Color(0xFFF8FAFC); // Slate-50
const Color kAccentPurple = Color(0xFF4F46E5); // Indigo-600

// Gradients from mockup
const LinearGradient kPrimaryGradient = LinearGradient(
  colors: [Color(0xFF6C6BF8), Color(0xFF4443C9)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kCallGreenGradient = LinearGradient(
  colors: [Color(0xFF32E08A), Color(0xFF1BAD61)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kSosRedGradient = LinearGradient(
  colors: [Color(0xFFFF4B6E), Color(0xFFFF2147)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kVoiceOrangeGradient = LinearGradient(
  colors: [Color(0xFFFFB830), Color(0xFFFF8C00)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kPinkGradient = LinearGradient(
  colors: [Color(0xFFFF7DAD), Color(0xFFE8265E)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

Color getAccentColor(String? hex) {
  if (hex == null || hex.trim().isEmpty) return kAccentPurple;
  try {
    final buffer = StringBuffer();
    final cleanHex = hex.replaceFirst('#', '').trim();
    if (cleanHex.length == 6) {
      buffer.write('ff');
    }
    buffer.write(cleanHex);
    return Color(int.parse(buffer.toString(), radix: 16));
  } catch (_) {
    return kAccentPurple;
  }
}
