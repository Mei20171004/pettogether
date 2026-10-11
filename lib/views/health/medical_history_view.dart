import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../store/care_store.dart';
import 'health_record_detail_view.dart';
import 'health_record_editor_view.dart';

class MedicalHistoryView extends StatelessWidget {
  const MedicalHistoryView({super.key, required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final records = store
        .recordsForPet(petId)
        .where((record) => !record.type.isCourseGenerated)
        .toList();
    final dateFormat = DateFormat.yMMMd(language.rawValue);

    void addRecord() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => HealthRecordEditorView(initialPetId: petId),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          L10n.text(
            language,
            'Medical history',
            '医療記録の履歴',
            '医疗记录历史',
            '진료 기록 내역',
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: addRecord,
            icon: const Icon(Icons.add),
            label: Text(
              L10n.text(language, 'New record', '記録を追加', '新增记录', '기록 추가'),
            ),
          ),
        ],
      ),
      body: records.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.text(
                      language,
                      'No medical records yet.',
                      '医療記録はまだありません。',
                      '还没有医疗记录。',
                      '아직 진료 기록이 없습니다.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: addRecord,
                    child: Text(
                      L10n.text(
                        language,
                        'Add your first record',
                        '最初の記録を追加',
                        '添加第一条记录',
                        '첫 기록 추가',
                      ),
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: records.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final record = records[index];
                return ListTile(
                  title: Text(record.title),
                  subtitle: Text(
                    '${record.petNameSnapshot} · '
                    '${dateFormat.format(record.occurredAt)} · '
                    '${L10n.healthRecordTypeTitle(language, record.type)}',
                  ),
                  leading: record.attachments.isEmpty
                      ? const Icon(Icons.description_outlined)
                      : const Icon(Icons.photo_library_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          HealthRecordDetailView(recordId: record.id),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
