import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Soft cream-to-lavender screen background used across the app.
class PetScreenBackground extends StatelessWidget {
  const PetScreenBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            PawColors.cream,
            Color(0xCCEDEBFF), // pawLavender @ ~0.72 opacity
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

/// Rounded icon tile with a tinted background, matching `CareIcon`.
class CareIcon extends StatelessWidget {
  const CareIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.4, color: color),
    );
  }
}

/// Hero illustration shipped as an asset (the SwiftUI `CopawPets` image).
class PetArtwork extends StatelessWidget {
  const PetArtwork({super.key, this.height = 180});

  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(28),
      ),
      child: Image.asset(
        'assets/images/copaw_pets.png',
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// Shows a pet's photo (from Firebase Storage) or the default artwork.
class PetPhotoView extends StatelessWidget {
  const PetPhotoView({super.key, this.photoURL});

  final String? photoURL;

  @override
  Widget build(BuildContext context) {
    if (photoURL != null && photoURL!.isNotEmpty) {
      return Image.network(
        photoURL!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          'assets/images/default_pet_photo.png',
          fit: BoxFit.cover,
        ),
      );
    }
    return Image.asset(
      'assets/images/default_pet_photo.png',
      fit: BoxFit.cover,
    );
  }
}

/// Section header with an optional trailing detail label.
class PetSectionTitle extends StatelessWidget {
  const PetSectionTitle({super.key, required this.title, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: PawColors.ink,
            ),
          ),
        ),
        if (detail != null)
          Text(
            detail!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: PawColors.purple,
            ),
          ),
      ],
    );
  }
}

/// Small tinted pill with an icon, matching `PetTag`.
class PetTag extends StatelessWidget {
  const PetTag({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// White rounded card with a soft shadow, matching `petCard`.
class PetCard extends StatelessWidget {
  const PetCard({super.key, required this.child, this.padding = 18});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: PawColors.purpleDark.withValues(alpha: 0.09),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Input decoration used by the text fields in create/join/profile/edit forms.
InputDecoration petFieldDecoration({String? hintText}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: PawColors.muted),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    filled: true,
    fillColor: PawColors.lavender.withValues(alpha: 0.52),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(
        color: PawColors.purple.withValues(alpha: 0.08),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(
        color: PawColors.purple.withValues(alpha: 0.08),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: PawColors.purple, width: 1.4),
    ),
  );
}
