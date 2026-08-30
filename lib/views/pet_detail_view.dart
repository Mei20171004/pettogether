import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import 'health/pet_health_section.dart';
import 'pet_insights_view.dart';
import 'widgets/common.dart';

/// Detailed view for a single pet: header card, then either the care insights
/// (today / this week / trends) or the health file (medication, medical
/// history, weight, vet visit pack).
class PetDetailView extends StatefulWidget {
  const PetDetailView({super.key, required this.pet, this.initialTab = 0});

  final Pet pet;

  /// 0 = care insights, 1 = health file. Lets a reminder open straight onto
  /// the health tab instead of dropping the reader on the wrong page.
  final int initialTab;

  @override
  State<PetDetailView> createState() => _PetDetailViewState();
}

class _PetDetailViewState extends State<PetDetailView> {
  /// 0 = care insights, 1 = health file.
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final current = store.household?.pets
            .where((p) => p.id == widget.pet.id)
            .firstOrNull ??
        widget.pet;

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
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: 0,
                        icon: const Icon(Icons.insights, size: 16),
                        label: Text(L10n.text(
                            language, 'Care', 'ケア', '照护', '케어')),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: const Icon(Icons.favorite_border, size: 16),
                        label: Text(L10n.text(
                            language, 'Health', '健康', '健康', '건강')),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _tab == 0
                      ? PetInsightsView(pet: current)
                      : PetHealthSection(pet: current),
                ),
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
