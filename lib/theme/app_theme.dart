import 'package:flutter/material.dart';
import 'custom_colors.dart';

abstract final class AppColors {
  static const ink = CustomColors.text;
  static const primary = CustomColors.primary;
  static const gold = CustomColors.gold;
  static const background = CustomColors.background;
  static const muted = CustomColors.muted;
  static const border = CustomColors.border;
  static const available = CustomColors.available;
  static const booked = CustomColors.booked;
  static const cleaning = CustomColors.cleaning;
  static const closed = CustomColors.closed;
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
          primary: AppColors.primary,
          secondary: AppColors.ink,
          tertiary: AppColors.gold,
          surface: CustomColors.surface,
          error: AppColors.booked,
        ).copyWith(
          primaryContainer: CustomColors.neutralTint,
          onPrimaryContainer: CustomColors.text,
          secondaryContainer: CustomColors.neutralTint,
          onSecondaryContainer: CustomColors.text,
          tertiaryContainer: CustomColors.neutralTint,
          onTertiaryContainer: CustomColors.text,
          surfaceTint: CustomColors.transparent,
          onSurface: CustomColors.text,
          onSurfaceVariant: CustomColors.muted,
          surfaceContainerLowest: CustomColors.surface,
          surfaceContainerLow: CustomColors.background,
          surfaceContainer: CustomColors.fieldBackground,
          surfaceContainerHigh: CustomColors.neutralTint,
          surfaceContainerHighest: CustomColors.border,
          outline: CustomColors.border,
          outlineVariant: CustomColors.border,
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Poppins',
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: ThemeData(
        fontFamily: 'Poppins',
      ).textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: CustomColors.background,
        foregroundColor: CustomColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: CustomColors.text,
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.primary, size: 22),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: CustomColors.surface,
        elevation: 0,
        margin: const EdgeInsets.all(8),
        shape: shape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: CustomColors.surface,
        surfaceTintColor: CustomColors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: CustomColors.surface,
        surfaceTintColor: CustomColors.transparent,
        elevation: 8,
        shape: shape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        labelStyle: const TextStyle(color: AppColors.muted),
        prefixIconColor: AppColors.primary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: CustomColors.onButton,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: shape,
          side: const BorderSide(color: AppColors.border),
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        shape: shape,
        contentTextStyle: const TextStyle(
          fontFamily: 'Poppins',
          color: CustomColors.surface,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
    );
  }
}
