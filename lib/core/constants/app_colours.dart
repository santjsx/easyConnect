import 'package:flutter/material.dart';

const Color kCallGreen = Color(0xFF4CAF50); // Light Green matching mockup
const Color kVideoBlue = Color(0xFF2196F3); // Nice light blue for video
const Color kMessageOrange = Color(0xFFFF9800); // Friendly orange for voice
const Color kStopRed = Color(0xFFC62828);
const Color kSosRed = Color(0xFFEF4444); // Premium SOS Red
const Color kCardBackground = Color(0xFFFFFFFF);
const Color kTextDark = Color(0xFF0F172A);

// Premium Typography & Accents
const Color kTextNavy = Color(0xFF0F172A); // Slate 900 for dark titles
const Color kTextSlate = Color(0xFF64748B); // Slate 500 for captions
const Color kAppBackground = Color(0xFFF6F7FB); // Clean soft lavender-grey
const Color kAccentPurple = Color(0xFF6E44FF); // Bright purple accent

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
