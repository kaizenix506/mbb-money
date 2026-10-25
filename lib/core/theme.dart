import 'dart:ui';
import 'package:flutter/material.dart';

/// Ultra-Modern Liquid Glass / Cyberpunk Design System
/// Specially crafted for Hoang: Deep void backdrop, glowing translucent glass panes,
/// frosted liquid glass blur (BackdropFilter), holographic cyan (#00F0FF),
/// neon magenta (#FF0055), and laser yellow accents.
abstract final class AppColors {
  // Deep Liquid Obsidian Backgrounds
  static const Color bgTop = Color(0xFF04060A);
  static const Color bgMid = Color(0xFF080C14);
  static const Color bgBottom = Color(0xFF020306);

  // Translucent Liquid Glass Panels
  static const Color glassPanel = Color(0x33101A2E);
  static const Color glassPanelStrong = Color(0x5516223D);
  static const Color glassBorder = Color(0x3800F0FF);
  static const Color glassBorderPink = Color(0x40FF0055);

  // Neon Core Palette
  static const Color neonCyan = Color(0xFF00F0FF);      // Primary data / Hologram
  static const Color neonPink = Color(0xFFFF0055);      // Expense alert / Pulse
  static const Color neonYellow = Color(0xFFFFE600);    // Daily limits
  static const Color neonGreen = Color(0xFF39FF14);     // Live connection
  static const Color neonViolet = Color(0xFF9D00FF);    // AI Core & Cognitive
  static const Color neonOrange = Color(0xFFFF7700);

  // Text & Glyphs
  static const Color ink = Color(0xFFF0F6FC);
  static const Color inkDim = Color(0xFF8FA0B8);
  static const Color inkFaint = Color(0xFF4A576E);

  // Compatibility aliases
  static const Color mint = neonCyan;
  static const Color mintDeep = Color(0xFF00C8D7);
  static const Color coral = neonPink;
  static const Color sky = neonCyan;
  static const Color stroke = glassBorder;
  static const Color strokeFaint = Color(0x1A8FA0B8);
  static const Color panel = Color(0xFF0A0F1D);
  static const Color glass = glassPanel;

  static List<BoxShadow> liquidGlow(Color color, {double blur = 18, double spread = 0}) => [
    BoxShadow(
      color: color.withValues(alpha: 0.32),
      blurRadius: blur,
      spreadRadius: spread,
    ),
  ];

  static List<BoxShadow> neonGlow(Color color, {double blur = 18, double spread = 0}) =>
      liquidGlow(color, blur: blur, spread: spread);
}

abstract final class AppRadius {
  static const double card = 24;
  static const double list = 20;
  static const double field = 16;
  static const double tile = 14;
  static const double pill = 100;
}

abstract final class AppText {
  static const String mono = 'Courier New';
  static const String sans = 'Inter';

  static const TextStyle cyberHeader = TextStyle(
    fontFamily: sans,
    fontSize: 22,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.5,
    color: AppColors.neonCyan,
  );

  static const TextStyle balance = TextStyle(
    fontFamily: mono,
    fontSize: 38,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.0,
    color: AppColors.ink,
  );

  static const TextStyle amount = TextStyle(
    fontFamily: mono,
    fontSize: 16,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: AppColors.neonPink,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.2,
    color: AppColors.inkDim,
  );

  static const TextStyle rowTitle = TextStyle(
    fontFamily: sans,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    color: AppColors.ink,
  );

  static const TextStyle rowMeta = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.inkDim,
  );
}

ThemeData buildLiquidGlassTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bgTop,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.neonCyan,
      secondary: AppColors.neonPink,
      tertiary: AppColors.neonYellow,
      surface: AppColors.bgMid,
      error: AppColors.neonPink,
      onPrimary: Colors.black,
      onSurface: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: AppText.cyberHeader,
    ),
  );
}

/// Frost-frosted Liquid Glass Widget with BackdropFilter blur
class LiquidGlassCard extends StatelessWidget {
  const LiquidGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppRadius.card,
    this.borderColor,
    this.glowColor,
    this.blur = 16,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? borderColor;
  final Color? glowColor;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final border = borderColor ?? AppColors.glassBorder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.glassPanel,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border, width: 1.2),
            boxShadow: glowColor != null ? AppColors.liquidGlow(glowColor!, blur: 20) : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
