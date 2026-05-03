import 'package:flutter/material.dart';

/// Kelas terpusat untuk warna tema aplikasi POS Panglima.
/// Ubah nilai di sini untuk mengganti warna tema di seluruh aplikasi.
class AppColors {
  AppColors._(); // Prevent instantiation

  // ─── PRIMARY (Maroon-based) ───────────────────────────────────────────────
  static const Color primary = Color(0xFFA61A1A); // Merah Maroon
  static const Color primaryLight = Color(0xFFF2D9D9);
  static const Color primaryMedium = Color(0xFFE6B3B3);
  static const Color primaryDark = Color(0xFF800000);
  static const Color primaryDarker = Color(0xFF4D0000);
  static const Color primaryDarkest = Color(0xFF330000);
  static const Color primaryAccent = Color(0xFFCC4D4D);
  static const Color primarySelected = Color(0xFFA61A1A);

  // ─── ACCENT (Orange-based, digunakan sebagai highlight/teks harga) ──────
  static const Color accent = Colors.yellow;
  static final Color accentDark = Colors.yellow.shade700;
  static final Color accentDarker = Colors.yellow.shade900;

  // ─── SUCCESS (Green) ────────────────────────────────────────────────────
  static const Color success = Colors.green;
  static final Color successLight = Colors.green.shade50;
  static final Color successMedium = Colors.green.shade200;
  static final Color successDark = Colors.green.shade700;
  static final Color successDarker = Colors.green.shade800;

  // ─── DANGER (Red) ───────────────────────────────────────────────────────
  static const Color danger = Colors.red;
  static final Color dangerLight = Colors.red.shade50;
  static final Color dangerMedium = Colors.red.shade100;
  static final Color dangerDark = Colors.red.shade300;
  static final Color dangerDarker = Colors.red.shade900;

  // ─── INFO / BLUE ────────────────────────────────────────────────────────
  static final Color infoDark = Colors.blue.shade700;

  // ─── NEUTRAL (Greys & Whites) ───────────────────────────────────────────
  static const Color white = Colors.white;
  static const Color black87 = Colors.black87;
  static const Color black54 = Colors.black54;
  static const Color textDark = Color(0xFF2D3436);
}
