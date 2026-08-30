import 'package:flutter/material.dart';

import '../models/health.dart';
import '../models/models.dart';

/// The pettogether color palette — the warm cream + blue "Copaw" look.
///
/// Names are kept from the original purple theme so every call site keeps
/// working: `purple` is now the primary action blue, `purpleDark` the deep
/// navy, `lavender` the soft sky tint, `peach` the warm cream-yellow tint.
abstract final class PawColors {
  static const Color green = Color(0xFF27A36A);
  static const Color cream = Color(0xFFFFF9F3);
  static const Color blue = Color(0xFF5B8DEF);
  static const Color purple = Color(0xFF2764DC); // primary action blue
  static const Color purpleDark = Color(0xFF102A56); // deep navy
  static const Color lavender = Color(0xFFEAF1FF); // soft sky tint
  static const Color peach = Color(0xFFFFF0D6); // warm cream tint
  static const Color rose = Color(0xFFE8756B);
  static const Color yellow = Color(0xFFE69A16);
  static const Color ink = Color(0xFF172033);
  static const Color muted = Color(0xFF7A8598);

  // Cozy pastel card tints, straight from the Copaw demo.
  static const Color creamYellow = Color(0xFFFFF3DE);
  static const Color skyTint = Color(0xFFE9F4FF);
  static const Color mintTint = Color(0xFFE8F8F0);
  static const Color lilacTint = Color(0xFFF0EBFF);
  static const Color blushTint = Color(0xFFFFF0EF);
}

/// Per-category accent color and icon (Material equivalents of the SF Symbols
/// used in the SwiftUI original).
Color categoryAccent(CareCategory category) {
  if (!category.isBuiltIn) return PawColors.purple;
  return switch (category.id) {
    'feeding' => PawColors.purple,
    'walking' => PawColors.blue,
    'medication' => PawColors.rose,
    'grooming' => PawColors.yellow,
    'hospital' => PawColors.rose,
    'deworming' => PawColors.green,
    'nailTrim' => PawColors.blue,
    'peePad' => PawColors.blue,
    'catLitter' => PawColors.purple,
    'water' => PawColors.blue,
    'newFood' => PawColors.purple,
    'dogBath' => PawColors.blue,
    'dogTraining' => PawColors.purple,
    'birdCage' => PawColors.yellow,
    'birdFeather' => PawColors.yellow,
    'rabbitHay' => PawColors.green,
    'rabbitBedding' => PawColors.green,
    'snakeFeed' => PawColors.green,
    'snakeShed' => PawColors.green,
    'snakeTerrarium' => PawColors.green,
    _ => PawColors.green,
  };
}

/// Cozy emoji per category, matching the Copaw demo's task cards.
String categoryEmoji(CareCategory category) {
  if (!category.isBuiltIn) return '✨';
  return switch (category.id) {
    'feeding' => '🥣',
    'walking' => '🦮',
    'medication' => '💊',
    'grooming' => '🧼',
    'hospital' => '🏥',
    'deworming' => '🛡️',
    'nailTrim' => '✂️',
    'peePad' => '🧻',
    'catLitter' => '🧹',
    'water' => '💧',
    'newFood' => '🍖',
    'dogBath' => '🛁',
    'dogTraining' => '🎾',
    'birdCage' => '🐦',
    'birdFeather' => '🪶',
    'rabbitHay' => '🌾',
    'rabbitBedding' => '🛌',
    'snakeFeed' => '🐁',
    'snakeShed' => '🐍',
    'snakeTerrarium' => '🌿',
    _ => '🐾',
  };
}

IconData categoryIcon(CareCategory category) {
  if (!category.isBuiltIn) return Icons.extension;
  return switch (category.id) {
    'feeding' => Icons.restaurant,
    'walking' => Icons.directions_walk,
    'medication' => Icons.medication,
    'grooming' => Icons.auto_awesome,
    'hospital' => Icons.local_hospital,
    'deworming' => Icons.bug_report,
    'nailTrim' => Icons.content_cut,
    'peePad' => Icons.grid_view,
    'catLitter' => Icons.cleaning_services,
    'water' => Icons.water_drop,
    'newFood' => Icons.fastfood,
    'dogBath' => Icons.bathtub,
    'dogTraining' => Icons.school,
    'birdCage' => Icons.grid_view,
    'birdFeather' => Icons.spa,
    'rabbitHay' => Icons.grass,
    'rabbitBedding' => Icons.bed,
    'snakeFeed' => Icons.set_meal,
    'snakeShed' => Icons.autorenew,
    'snakeTerrarium' => Icons.thermostat,
    _ => Icons.pets,
  };
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: PawColors.purple,
      primary: PawColors.purple,
    ),
    scaffoldBackgroundColor: PawColors.cream,
    fontFamily: null,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: PawColors.ink,
      centerTitle: false,
    ),
  );
}

/// Primary call-to-action button, matching `PawPrimaryButtonStyle`.
ButtonStyle pawPrimaryButtonStyle() {
  return ButtonStyle(
    foregroundColor: WidgetStateProperty.all(Colors.white),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? PawColors.purple.withValues(alpha: 0.45)
          : PawColors.purple,
    ),
    minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 54)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontWeight: FontWeight.w600),
    ),
    elevation: const WidgetStatePropertyAll(0),
  );
}

/// Compact secondary button, matching `PawCompactButtonStyle`.
ButtonStyle pawCompactButtonStyle(Color color, {bool filled = false}) {
  return ButtonStyle(
    foregroundColor: WidgetStatePropertyAll(filled ? Colors.white : color),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? color.withValues(alpha: 0.45)
          : (filled ? color : color.withValues(alpha: 0.12)),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 44)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
    ),
    elevation: const WidgetStatePropertyAll(0),
  );
}

// ---------------------------------------------------------------------------
// Health records
// ---------------------------------------------------------------------------

/// Per-medication-form icon, so a caregiver who has never given this medicine
/// can tell a tablet from eye drops at a glance.
IconData medicationFormIcon(MedicationForm form) {
  return switch (form) {
    MedicationForm.oral => Icons.medication,
    MedicationForm.topical => Icons.healing,
    MedicationForm.injection => Icons.vaccines,
    MedicationForm.eyeDrop => Icons.remove_red_eye_outlined,
    MedicationForm.earDrop => Icons.hearing,
    MedicationForm.inhaler => Icons.air,
    MedicationForm.powder => Icons.grain,
    MedicationForm.other => Icons.medical_services_outlined,
  };
}

IconData healthRecordIcon(HealthRecordType type) {
  return switch (type) {
    HealthRecordType.vetVisit => Icons.local_hospital,
    HealthRecordType.vaccination => Icons.vaccines,
    HealthRecordType.deworming => Icons.bug_report,
    HealthRecordType.labResult => Icons.science_outlined,
    HealthRecordType.surgery => Icons.medical_services,
    HealthRecordType.symptom => Icons.sick_outlined,
    HealthRecordType.weight => Icons.monitor_weight_outlined,
    HealthRecordType.medication => Icons.medication,
    HealthRecordType.note => Icons.sticky_note_2_outlined,
  };
}

Color healthRecordAccent(HealthRecordType type) {
  return switch (type) {
    HealthRecordType.vetVisit => PawColors.rose,
    HealthRecordType.vaccination => PawColors.green,
    HealthRecordType.deworming => PawColors.green,
    HealthRecordType.labResult => PawColors.blue,
    HealthRecordType.surgery => PawColors.rose,
    HealthRecordType.symptom => PawColors.yellow,
    HealthRecordType.weight => PawColors.blue,
    HealthRecordType.medication => PawColors.rose,
    HealthRecordType.note => PawColors.purple,
  };
}

/// State color for a medication dose, which is an ordinary care task.
///
/// Overdue borrows the same rose as the urgent badge, so "needs attention"
/// reads the same everywhere.
Color doseStateColor(CareTaskStatus status, {bool isOverdue = false}) {
  return switch (status) {
    CareTaskStatus.completed => PawColors.green,
    CareTaskStatus.skipped => PawColors.yellow,
    CareTaskStatus.claimed => PawColors.purple,
    CareTaskStatus.unclaimed => isOverdue ? PawColors.rose : PawColors.muted,
  };
}
