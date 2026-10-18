import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color primaryColor = Color(0xFF2196F3);
  static const Color secondaryColor = Color(0xFF1976D2);
  static const Color backgroundColor = Color(0xFFF5F5F5);
  static const Color surfaceColor = Colors.white;
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color successColor = Color(0xFF388E3C);
  static const Color textPrimaryColor = Color(0xFF212121);
  static const Color textSecondaryColor = Color(0xFF757575);
  static const Color dividerColor = Color(0xFFE0E0E0);

  static const Color darkBackgroundColor = Color(0xFF121212);
  static const Color darkSurfaceColor = Color(0xFF1E1E1E);
  static const Color darkTextPrimaryColor = Color(0xFFECECEC);
  static const Color darkTextSecondaryColor = Color(0xFFB0B0B0);
  static const Color darkDividerColor = Color(0xFF2E2E2E);
  static const Color darkInputFillColor = Color(0xFF2A2A2A);
  static const Color darkBubbleColor = Color(0xFF2C2C2C);

  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  static Color textPrimary(BuildContext context) => isDark(context) ? darkTextPrimaryColor : textPrimaryColor;

  static Color textSecondary(BuildContext context) => isDark(context) ? darkTextSecondaryColor : textSecondaryColor;

  static Color background(BuildContext context) => isDark(context) ? darkBackgroundColor : backgroundColor;

  static Color surface(BuildContext context) => isDark(context) ? darkSurfaceColor : surfaceColor;

  static Color divider(BuildContext context) => isDark(context) ? darkDividerColor : dividerColor;

  static Color inputFill(BuildContext context) => isDark(context) ? darkInputFillColor : const Color(0xFFF5F5F5);

  static Color bubbleIncoming(BuildContext context) => isDark(context) ? darkBubbleColor : Colors.white;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimaryColor,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical:14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: primaryColor,
        unselectedItemColor: textSecondaryColor,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: 1,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: darkSurfaceColor,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkTextPrimaryColor,
        onSurfaceVariant: darkTextSecondaryColor,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: darkBackgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurfaceColor,
        foregroundColor: darkTextPrimaryColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: darkTextPrimaryColor),
        actionsIconTheme: IconThemeData(color: darkTextPrimaryColor),
      ),
      iconTheme: const IconThemeData(color: darkTextPrimaryColor),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: darkTextPrimaryColor),
        bodyMedium: TextStyle(color: darkTextPrimaryColor),
        bodySmall: TextStyle(color: darkTextSecondaryColor),
        titleLarge: TextStyle(color: darkTextPrimaryColor),
        titleMedium: TextStyle(color: darkTextPrimaryColor),
        titleSmall: TextStyle(color: darkTextPrimaryColor),
        labelLarge: TextStyle(color: darkTextPrimaryColor),
      ),
      cardTheme: CardThemeData(
        color: darkSurfaceColor,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurfaceColor,
        titleTextStyle: const TextStyle(color: darkTextPrimaryColor, fontSize: 20, fontWeight: FontWeight.w600),
        contentTextStyle: const TextStyle(color: darkTextPrimaryColor, fontSize: 14),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: darkSurfaceColor,
        textStyle: TextStyle(color: darkTextPrimaryColor, fontSize: 14),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: darkTextPrimaryColor,
        iconColor: darkTextSecondaryColor,
      ),
      dividerTheme: const DividerThemeData(
        color: darkDividerColor,
        thickness: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkInputFillColor,
        hintStyle: const TextStyle(color: darkTextSecondaryColor),
        labelStyle: const TextStyle(color: darkTextSecondaryColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurfaceColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: darkTextSecondaryColor,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
