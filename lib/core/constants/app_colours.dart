import 'package:flutter/material.dart';

// Primary Brand Colors
const Color kPrimary = Color(0xFF534AB7); // Deep indigo-violet
const Color kPrimaryDark = Color(0xFF3C3489);
const Color kPrimaryDeeper = Color(0xFF26215C);

// Accent Colors
const Color kAccentGreen = Color(0xFF1D9E75);
const Color kAccentAmber = Color(0xFFEF9F27);
const Color kAccentRed = Color(0xFFE24B4A);
const Color kAccentBlue = Color(0xFF378ADD);
const Color kAccentPink = Color(0xFFD4537E);

// Legacy/Compatibility Colors mapped to Design Tokens
const Color kCallGreen = kAccentGreen;
const Color kVideoBlue = kAccentBlue;
const Color kMessageOrange = kAccentAmber;
const Color kStopRed = kAccentRed;
const Color kSosRed = kAccentRed;

// Core Surface & Text Mappings (Light Mode)
const Color kSurfaceLight = Color(0xFFFFFFFF);
const Color kMutedBGLight = Color(0xFFF5F4FC);
const Color kBorderLight = Color(0xFFE4E2F5);
const Color kTextPrimaryLight = Color(0xFF1A1830);
const Color kTextSecondaryLight = Color(0xFF7F77DD);

// Core Surface & Text Mappings (Dark Mode)
const Color kSurfaceDark = Color(0xFF0F0E1A);
const Color kMutedBGDark = Color(0xFF1A1830);
const Color kBorderDark = Color(0xFF2A2648);
const Color kTextPrimaryDark = Color(0xFFEEEDFE);
const Color kTextSecondaryDark = Color(0xFFAFA9EC);

// Semantic Tints (Light Mode)
const Color kPurpleTintLight = Color(0xFFEEEDFE);
const Color kPurpleIconLight = Color(0xFF534AB7);

const Color kGreenTintLight = Color(0xFFE1F5EE);
const Color kGreenIconLight = Color(0xFF0F6E56);

const Color kRedTintLight = Color(0xFFFCEBEB);
const Color kRedIconLight = Color(0xFFA32D2D);

const Color kAmberTintLight = Color(0xFFFAEEDA);
const Color kAmberIconLight = Color(0xFF633806);

const Color kBlueTintLight = Color(0xFFE6F1FB);
const Color kBlueIconLight = Color(0xFF185FA5);

// Semantic Tints (Dark Mode)
const Color kPurpleTintDark = Color(0xFF1A1830);
const Color kPurpleIconDark = Color(0xFFAFA9EC);

const Color kGreenTintDark = Color(0xFF0F6E56);
const Color kGreenIconDark = Color(0xFFE1F5EE);

const Color kRedTintDark = Color(0xFFA32D2D);
const Color kRedIconDark = Color(0xFFFCEBEB);

const Color kAmberTintDark = Color(0xFF633806);
const Color kAmberIconDark = Color(0xFFFAEEDA);

const Color kBlueTintDark = Color(0xFF185FA5);
const Color kBlueIconDark = Color(0xFFE6F1FB);

// Gradients
const LinearGradient kPrimaryGradient = LinearGradient(
  colors: [kPrimary, kPrimaryDark],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kCallGreenGradient = LinearGradient(
  colors: [Color(0xFF1D9E75), Color(0xFF0F6E56)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kSosRedGradient = LinearGradient(
  colors: [Color(0xFFE24B4A), Color(0xFF931A1A)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kVoiceOrangeGradient = LinearGradient(
  colors: [Color(0xFFEF9F27), Color(0xFFBA7517)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kPinkGradient = LinearGradient(
  colors: [Color(0xFFD4537E), Color(0xFFA22953)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

Color getAccentColor(String? hex) {
  if (hex == null || hex.trim().isEmpty) return kPrimary;
  try {
    final buffer = StringBuffer();
    final cleanHex = hex.replaceFirst('#', '').trim();
    if (cleanHex.length == 6) {
      buffer.write('ff');
    }
    buffer.write(cleanHex);
    return Color(int.parse(buffer.toString(), radix: 16));
  } catch (_) {
    return kPrimary;
  }
}

// Backward compatibility mappings
const Color kTextNavy = kTextPrimaryLight;
const Color kTextDark = kTextPrimaryLight;
const Color kTextSlate = kTextSecondaryLight;
const Color kAppBackground = kMutedBGLight;

