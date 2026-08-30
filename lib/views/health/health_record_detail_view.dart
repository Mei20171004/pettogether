import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/health.dart';
import '../../store/care_store.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'health_record_editor_view.dart';

/// One medical record in full, with its photos, and the edit / delete actions
/// 明泽's version never offered — a typo in a vet note used to be permanent.
class HealthRecordDetailView extends StatelessWidget {
  const HealthRecordDetailView({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final record = store.recordByID(recordId);

    if (record == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Stack(
          children: [
            const PetScreenBackground(),
            Center(
              child: Text(
                L10n.text(language, 'This record is no longer available.',
                    'この記録は見つかりません。', '这条记录已不存在。', '이 기록을 찾을 수 없습니다.'),
                style: const TextStyle(color: PawColors.muted),
              ),
            ),
          ],
        ),
      );
    }

    final accent = healthRecordAccent(record.type);
    final dateFormat = DateFormat.yMMMd(language.rawValue);
    final timeFormat = DateFormat.Hm(language.rawValue);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(L10n.healthRecordTypeTitle(language, record.type)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => value == 'edit'
                ? _edit(context, record)
                : _confirmDelete(context, store, record, language),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(L10n.text(language, 'Edit', '編集', '编辑', '편집')),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  L10n.text(language, 'Delete', '削除', '删除', '삭제'),
                  style: const TextStyle(color: PawColors.rose),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
              children: [
                PetCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CareIcon(
                            icon: healthRecordIcon(record.type),
                            color: accent,
                            size: 48,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: PawColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${record.petNameSnapshot} · '
                                  '${dateFormat.format(record.occurredAt)} '
                                  '${timeFormat.format(record.occurredAt)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: PawColors.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ..._details(record, language, dateFormat),
                    ],
                  ),
                ),
                if (record.attachments.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  PetSectionTitle(
                    title:
                        L10n.text(language, 'Photos', '写真', '照片', '사진'),
                    detail: '${record.attachments.length}',
                  ),
                  const SizedBox(height: 12),
                  _gallery(context, record),
                ],
                const SizedBox(height: 18),
                _provenance(record, language, dateFormat),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _details(
    HealthRecord record,
    AppLanguage language,
    DateFormat dateFormat,
  ) {
    final rows = <Widget>[];

    void add(String label, String? value, {Color? color}) {
      if (value == null || value.isEmpty) return;
      rows.add(_block(label, value, color: color));
    }

    add(L10n.text(language, 'Clinic', '動物病院', '医院', '병원'), record.clinicName);
    add(L10n.text(language, 'Vet', '担当獣医', '医生', '수의사'), record.vetName);
    add(
      record.type == HealthRecordType.labResult
          ? L10n.text(language, 'Results', '検査結果', '化验结论', '검사 결과')
          : L10n.text(language, 'Diagnosis', '診断', '诊断', '진단'),
      record.diagnosis,
    );
    add(
        L10n.text(language, 'Treatment', '処置・処方', '处置与用药', '처치 및 처방'),
        record.treatment);
    add(L10n.text(language, 'Product', '製品名', '产品名称', '제품명'),
        record.productName);
    add(L10n.text(language, 'Lot number', 'ロット番号', '批号', '로트 번호'),
        record.lotNumber);
    if (record.nextDueAt != null) {
      final days = record.daysUntilDue() ?? 0;
      add(
        L10n.text(language, 'Next one due', '次回の予定', '下次到期', '다음 예정일'),
        '${dateFormat.format(record.nextDueAt!)} · '
        '${days < 0 ? L10n.text(language, '${-days} days overdue', '${-days}日超過', '已过期 ${-days} 天', '${-days}일 지남') : L10n.text(language, 'in $days days', 'あと$days日', '还有 $days 天', '$days일 남음')}',
        color: days <= 0 ? PawColors.rose : PawColors.green,
      );
    }
    if (record.weightKg != null) {
      add(L10n.text(language, 'Weight', '体重', '体重', '체중'),
          '${record.weightKg} kg');
    }
    if (record.temperatureC != null) {
      add(L10n.text(language, 'Temperature', '体温', '体温', '체온'),
          '${record.temperatureC} °C');
    }
    if (record.costMinor != null) {
      add(L10n.text(language, 'Cost', '費用', '费用', '비용'),
          '${record.currency ?? ''} ${record.costMinor}'.trim());
    }
    add(L10n.text(language, 'Notes', 'メモ', '备注', '메모'), record.notes);

    if (rows.isEmpty) return const [];
    return [
      Divider(height: 1, color: PawColors.purple.withValues(alpha: 0.08)),
      const SizedBox(height: 12),
      ...rows,
    ];
  }

  Widget _block(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color ?? PawColors.purpleDark,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
                fontSize: 14, color: PawColors.ink, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _gallery(BuildContext context, HealthRecord record) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final attachment in record.attachments)
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _PhotoViewer(attachment: attachment),
              ),
            ),
            child: Hero(
              tag: attachment.id,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Image.network(
                    attachment.url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Container(
                      color: PawColors.lavender,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined,
                          color: PawColors.muted),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Who wrote this down, and whether anyone has changed it since. A shared
  /// medical history is only trustworthy if you can see where a line came from.
  Widget _provenance(
    HealthRecord record,
    AppLanguage language,
    DateFormat dateFormat,
  ) {
    final lines = <String>[
      L10n.text(
        language,
        'Added by ${record.createdByNameSnapshot} on ${dateFormat.format(record.createdAt)}',
        '${dateFormat.format(record.createdAt)} に ${record.createdByNameSnapshot} が追加',
        '由 ${record.createdByNameSnapshot} 于 ${dateFormat.format(record.createdAt)} 添加',
        '${record.createdByNameSnapshot} 님이 ${dateFormat.format(record.createdAt)}에 추가',
      ),
    ];
    if (record.wasEdited) {
      final who = record.updatedByNameSnapshot ?? '';
      final when = dateFormat.format(record.updatedAt!);
      lines.add(L10n.text(
        language,
        'Edited by $who on $when',
        '$when に $who が編集',
        '由 $who 于 $when 修改',
        '$who 님이 $when에 편집',
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              line,
              style: const TextStyle(fontSize: 11, color: PawColors.muted),
            ),
          ),
      ],
    );
  }

  void _edit(BuildContext context, HealthRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => HealthRecordEditorView(record: record),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CareStore store,
    HealthRecord record,
    AppLanguage language,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.text(language, 'Delete this record?', '削除しますか？',
            '删除这条记录？', '삭제할까요?')),
        content: Text(L10n.text(
          language,
          'It will be removed for everyone in the household, along with its photos.',
          '家族全員の画面から写真ごと削除されます。',
          '这会从所有家庭成员那里删除，照片也会一起删掉。',
          '가족 모두의 화면에서 사진과 함께 삭제됩니다.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              L10n.text(language, 'Delete', '削除', '删除', '삭제'),
              style: const TextStyle(color: PawColors.rose),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await store.deleteHealthRecord(record);
    if (removed && context.mounted) Navigator.of(context).pop();
  }
}

/// Full-screen, pinch-to-zoom view of one attachment — a lab printout is
/// unreadable at thumbnail size.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.attachment});

  final HealthAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: Hero(
          tag: attachment.id,
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Image.network(
              attachment.url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
