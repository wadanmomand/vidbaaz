/// Shared theme: deep navy + gold (Aatish Studio brand line).
library;

import 'package:flutter/material.dart';

class AppTheme {
  static const navy = Color(0xFF0D1330);
  static const navyLight = Color(0xFF1A237E);
  static const gold = Color(0xFFFFD54F);
  static const goldDark = Color(0xFFE6A817);

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: navy,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          secondary: goldDark,
          surface: Color(0xFF141B45),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: navyLight,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: navyLight,
          selectedItemColor: gold,
          unselectedItemColor: Colors.white54,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: gold,
            foregroundColor: navy,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF141B45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF141B45),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(color: Colors.white38),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: navyLight,
          contentTextStyle: TextStyle(color: Colors.white),
        ),
      );
}
