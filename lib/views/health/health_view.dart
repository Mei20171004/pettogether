import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/care_catalog.dart';
import '../../models/models.dart';
import '../../store/care_store.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'pet_health_section.dart';

/// The Health tab: pick a pet, see its whole health file.
///
/// Health used to live two taps down, behind a pet photo and a segmented
/// control. It earns a place in the main navigation because medication and
/// medical history are the things people most need to check quickly and
/// least want to hunt for.
class HealthView extends StatefulWidget {
  const HealthView({super.key});

  @override
  State<HealthView> createState() => _HealthViewState();
}

class _HealthViewState extends State<HealthView> {
  String? _petID;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final pets = store.household?.pets ?? const <Pet>[];
    final selectedID = _petID ?? pets.firstOrNull?.id;
    final pet = pets.where((p) => p.id == selectedID).firstOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(L10n.text(language, 'Health', '健康', '健康', '건강')),
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: Column(
              children: [
                if (pets.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                    child: _petSelector(pets, selectedID),
                  ),
                if (pet != null)
                  Expanded(child: PetHealthSection(pet: pet))
                else
                  Expanded(
                    child: Center(
                      child: Text(
                        L10n.text(language, 'No pets yet', 'まだペットがいません',
                            '还没有宠物', '아직 반려동물이 없습니다'),
                        style: const TextStyle(color: PawColors.muted),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _petSelector(List<Pet> pets, String? selectedID) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final pet in pets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Text(petTypeEmoji(pet.type)),
                label: Text(pet.name),
                selected: selectedID == pet.id,
                onSelected: (_) => setState(() => _petID = pet.id),
              ),
            ),
        ],
      ),
    );
  }
}
