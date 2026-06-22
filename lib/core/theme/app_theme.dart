import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';

import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Font size constants
  static const double fontSizeDefault = 16.0;
  static const double fontSizeLarge = 20.0;
  static const double fontSizeExtraLarge = 24.0;

  static ThemeData get themeData => getThemeData(kAccentPurple);

  static ThemeData getThemeData(Color accentColor) {
    final baseTextTheme = GoogleFonts.nunitoTextTheme();
    return ThemeData(
      useMaterial3: true,
      primaryColor: accentColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accentColor,
        primary: accentColor,
        surface: kAppBackground,
      ),
      scaffoldBackgroundColor: kAppBackground,
      appBarTheme: const AppBarTheme(
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      textTheme: baseTextTheme.copyWith(
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontSize: fontSizeDefault,
          color: kTextDark,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          fontSize: fontSizeDefault,
          color: kTextDark,
        ),
        titleLarge: GoogleFonts.outfit(
          fontSize: fontSizeLarge,
          fontWeight: FontWeight.w700,
          color: kTextDark,
          letterSpacing: -0.3,
        ),
        headlineMedium: GoogleFonts.outfit(
          fontSize: fontSizeExtraLarge,
          fontWeight: FontWeight.w800,
          color: kTextDark,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
          side: const BorderSide(color: Color(0xFFF1F5F9), width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(kMinTouchTarget),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCardBorderRadius),
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
