import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import 'pet_insights_view.dart';
import 'widgets/common.dart';

/// The "Activity" tab: a pet selector plus the pet insights
/// (today / this week / trends) for the selected pet.
class ActivityView extends StatefulWidget {
  const ActivityView({super.key});

  @override
  State<ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends State<ActivityView> {
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
        title: Text(
            L10n.text(language, 'Activity', 'アクティビティ', '活动', '활동')),
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: Column(
              children: [
                if (pets.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                    child: _petSelector(pets, selectedID, language),
                  ),
                if (pet != null)
                  Expanded(child: PetInsightsView(pet: pet))
                else
                  Expanded(
                    child: Center(
                      child: Text(L10n.text(language, 'No pets yet',
                          'まだペットがいません', '还没有宠物', '아직 반려동물이 없습니다')),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _petSelector(
      List<Pet> pets, String? selectedID, AppLanguage language) {
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
