import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const double fontSizeCaption = 10.0;
  static const double fontSizeBody = 13.0;
  static const double fontSizeHeading = 18.0;
  static const double fontSizeDisplay = 36.0;

  static ThemeData get lightTheme => getThemeData(kPrimary, isDark: false);
  static ThemeData get darkTheme => getThemeData(kPrimary, isDark: true);

  static ThemeData getThemeData(Color accentColor, {required bool isDark}) {
    final surfaceColor = isDark ? kSurfaceDark : kSurfaceLight;
    final mutedBG = isDark ? kMutedBGDark : kMutedBGLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    final textPrimary = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;

    final baseTextTheme = GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primaryColor: accentColor,
      cardColor: surfaceColor,
      dividerColor: borderColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accentColor,
        primary: accentColor,
        surface: surfaceColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
      ),
      scaffoldBackgroundColor: mutedBG,
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: GoogleFonts.inter(
          fontSize: fontSizeHeading,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      textTheme: baseTextTheme.copyWith(
        // Display styles
        displayMedium: GoogleFonts.inter(
          fontSize: fontSizeDisplay,
          fontWeight: FontWeight.w500,
          letterSpacing: -1.0,
          color: textPrimary,
        ),
        // Heading styles
        titleLarge: GoogleFonts.inter(
          fontSize: fontSizeHeading,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        // Body styles
        bodyMedium: GoogleFonts.inter(
          fontSize: fontSizeBody,
          fontWeight: FontWeight.w400,
          color: textPrimary,
        ),
        // Caption/Label styles
        labelSmall: GoogleFonts.inter(
          fontSize: fontSizeCaption,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.08,
          color: textSecondary,
        ),
        // Subtitle/Secondary text styles
        bodySmall: GoogleFonts.inter(
          fontSize: fontSizeBody - 2.0,
          fontWeight: FontWeight.w400,
          color: textSecondary,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0), // border-radius 14-18px
          side: BorderSide(color: borderColor, width: 0.5), // All borders: 0.5px, color = border token
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: isDark ? kSurfaceDark : Colors.white,
          minimumSize: const Size.fromHeight(kMinTouchTarget),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.0), // border-radius 12-16px
            side: BorderSide(color: borderColor, width: 0.5),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: borderColor, width: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.0),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: BorderSide(color: borderColor, width: 0.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
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
