import 'package:flutter/material.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';

class AppTheme {
  // Font size constants
  static const double fontSizeDefault = 16.0;
  static const double fontSizeLarge = 20.0;
  static const double fontSizeExtraLarge = 24.0;

  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      primaryColor: kCallGreen,
      colorScheme: ColorScheme.fromSeed(
        seedColor: kCallGreen,
        primary: kCallGreen,
        surface: kCardBackground,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(
          fontSize: fontSizeDefault,
          color: kTextDark,
        ),
        bodyLarge: TextStyle(
          fontSize: fontSizeDefault,
          color: kTextDark,
        ),
        titleLarge: TextStyle(
          fontSize: fontSizeLarge,
          fontWeight: FontWeight.bold,
          color: kTextDark,
        ),
        headlineMedium: TextStyle(
          fontSize: fontSizeExtraLarge,
          fontWeight: FontWeight.bold,
          color: kTextDark,
        ),
      ),
      cardTheme: CardThemeData(
        color: kCardBackground,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kCardBorderRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(kMinTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCardBorderRadius),
          ),
        ),
      ),
    );
  }
}
