import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import 'pet_insights_view.dart';
import 'widgets/common.dart';

/// Detailed view for a single pet: header card + the reusable pet insights
/// (today / this week / trends).
class PetDetailView extends StatelessWidget {
  const PetDetailView({super.key, required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final current = store.household?.pets
            .where((p) => p.id == pet.id)
            .firstOrNull ??
        pet;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(current.name),
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                  child: _header(context, store, current, language),
                ),
                const SizedBox(height: 10),
                Expanded(child: PetInsightsView(pet: current)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(
      BuildContext context, CareStore store, Pet pet, AppLanguage language) {
    return PetCard(
      padding: 16,
      child: Row(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: PetPhotoView(photoURL: pet.photoURL),
                ),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: InkWell(
                  onTap: () => _pickPhoto(context, store, pet),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: PawColors.purple,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.photo_camera,
                        size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(petTypeEmoji(pet.type),
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 6),
                    Text(
                      petTypeName(language, pet.type),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PawColors.purpleDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _infoRow(Icons.cake_outlined,
                    pet.ageYears == null
                        ? '—'
                        : '${pet.ageYears} ${L10n.text(language, 'years old', '歳', '岁', '살')}'),
                _infoRow(
                    Icons.monitor_weight_outlined,
                    pet.weightKg == null
                        ? '—'
                        : '${pet.weightKg} kg'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: PawColors.muted),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 13, color: PawColors.ink)),
        ],
      ),
    );
  }

  Future<void> _pickPhoto(
      BuildContext context, CareStore store, Pet pet) async {
    final picker = ImagePicker();
    try {
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      await store.savePetPhoto(pet, bytes);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't use that photo")),
        );
      }
    }
  }
}
