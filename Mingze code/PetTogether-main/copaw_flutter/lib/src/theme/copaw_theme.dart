import 'package:flutter/material.dart';

abstract final class CopawColors {
  static const green = Color(0xFF267456);
  static const cream = Color(0xFFF9FAFF);
  static const blue = Color(0xFF5A6FF0);
  static const purple = Color(0xFF5B4DE0);
  static const purpleDark = Color(0xFF302A67);
  static const lavender = Color(0xFFE9EBFF);
  static const peach = Color(0xFFFFE7D2);
  static const orange = Color(0xFFF99943);
  static const orangeStrong = Color(0xFFC65A00);
  static const rose = Color(0xFFED7D78);
  static const roseStrong = Color(0xFFB84E45);
  static const yellow = Color(0xFFFFD978);
  static const ink = Color(0xFF27263B);
  static const muted = Color(0xFF66667A);
}

ThemeData buildCopawTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: CopawColors.purple,
    brightness: Brightness.light,
    surface: CopawColors.cream,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: Typography.blackCupertino.apply(
      bodyColor: CopawColors.ink,
      displayColor: CopawColors.ink,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      backgroundColor: Colors.white.withValues(alpha: 0.97),
      indicatorColor: CopawColors.lavender,
      elevation: 12,
      shadowColor: CopawColors.purpleDark.withValues(alpha: 0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? CopawColors.purpleDark
              : CopawColors.muted,
          fontSize: 10,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? CopawColors.purple
              : CopawColors.muted,
          size: 23,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CopawColors.purple,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: CopawColors.purpleDark,
        side: const BorderSide(color: Color(0x33665AF2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CopawColors.lavender.withValues(alpha: 0.62),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0x14665AF2)),
      ),
    ),
  );
}

class CopawBackground extends StatelessWidget {
  const CopawBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF9FAFF), Color(0xFFF0F1FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(
          top: -84,
          right: -68,
          child: _BackgroundOrb(
            size: 220,
            color: CopawColors.peach.withValues(alpha: 0.58),
          ),
        ),
        Positioned(
          top: 245,
          left: -90,
          child: _BackgroundOrb(
            size: 210,
            color: CopawColors.lavender.withValues(alpha: 0.8),
          ),
        ),
        child,
      ],
    );
  }
}

class _BackgroundOrb extends StatelessWidget {
  const _BackgroundOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class CopawCard extends StatelessWidget {
  const CopawCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12302A67),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}
