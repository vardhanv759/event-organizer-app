import 'package:flutter/material.dart';

class AppThemeX {
  static const bg = Color(0xFFF6F7FB);
  static const card = Colors.white;

  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);

  static const indigo = Color(0xFF4F46E5);
  static const sky = Color(0xFF0EA5E9);
  static const violet = Color(0xFF8B5CF6);
  static const emerald = Color(0xFF22C55E);
  static const amber = Color(0xFFF59E0B);
  static const slate = Color(0xFF334155);

  static LinearGradient heroGradient({bool alt = false}) => LinearGradient(
    colors: alt
        ? const [Color(0xFF8B5CF6), Color(0xFF6366F1), Color(0xFF0EA5E9)]
        : const [Color(0xFF0EA5E9), Color(0xFF6366F1), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static BoxShadow softShadow({double opacity = 0.08}) => BoxShadow(
    color: Colors.black.withOpacity(opacity),
    blurRadius: 22,
    offset: const Offset(0, 14),
  );

  static BorderRadius br(double r) => BorderRadius.circular(r);
}
