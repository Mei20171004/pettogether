
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/care_catalog.dart';
import '../../models/health.dart';
import '../../models/models.dart';
import '../../store/care_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/id.dart';
import '../widgets/common.dart';

/// Creates or edits one medical record.
///
/// The form changes shape with the record type instead of asking the owner to
/// cram a visit, a diagnosis, a prescription and the vet's instructions into a
/// single free-text box. The event time can be backdated, because nobody opens
/// their phone while the vet is still talking.
class HealthRecordEditorView extends StatefulWidget {
  const HealthRecordEditorView({
    super.key,
    this.record,
    this.initialPetId,
    this.initialType,
  });

  final HealthRecord? record;
  final String? initialPetId;
  final HealthRecordType? initialType;

  @override
  State<HealthRecordEditorView> createState() => _HealthRecordEditorViewState();
}

class _HealthRecordEditorViewState extends State<HealthRecordEditorView> {
  late String _petId;
  late String _recordId;
  late HealthRecordType _type;
  late DateTime _occurredAt;
  DateTime? _nextDueAt;

  final _title = TextEditingController();
  final _clinic = TextEditingController();
  final _vet = TextEditingController();
  final _diagnosis = TextEditingController();
  final _treatment = TextEditingController();
  final _cost = TextEditingController();
  final _productName = TextEditingController();
  final _lotNumber = TextEditingController();
  final _weight = TextEditingController();
  final _temperature = TextEditingController();
  final _notes = TextEditingController();

  List<HealthAttachment> _attachments = [];
  bool _uploading = false;

  bool get _isEditing => widget.record != null;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _recordId = record?.id ?? uuid();
    _petId = record?.petId ?? widget.initialPetId ?? '';
    _type = record?.type ?? widget.initialType ?? HealthRecordType.vetVisit;
    _occurredAt = record?.occurredAt ?? DateTime.now();
    _nextDueAt = record?.nextDueAt;
    _attachments = [...?record?.attachments];

    _title.text = record?.title ?? '';
    _clinic.text = record?.clinicName ?? '';
    _vet.text = record?.vetName ?? '';
    _diagnosis.text = record?.diagnosis ?? '';
    _treatment.text = record?.treatment ?? '';
    _cost.text = record?.costMinor?.toString() ?? '';
    _productName.text = record?.productName ?? '';
    _lotNumber.text = record?.lotNumber ?? '';
    _weight.text = record?.weightKg?.toString() ?? '';
    _temperature.text = record?.temperatureC?.toString() ?? '';
    _notes.text = record?.notes ?? '';
  }

  @override
  void dispose() {
    for (final controller in [
      _title, _clinic, _vet, _diagnosis, _treatment, _cost,
      _productName, _lotNumber, _weight, _temperature, _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final pets = store.household?.pets ?? const <Pet>[];
    if (_petId.isEmpty && pets.isNotEmpty) _petId = pets.first.id;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_isEditing
            ? L10n.text(language, 'Edit record', '記録を編集', '编辑记录', '기록 편집')
            : L10n.text(language, 'New record', '記録を追加', '新建记录', '기록 추가')),
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                if (pets.length > 1) ...[
                  _petPicker(pets, language),
                  const SizedBox(height: 16),
                ],
                _typeCard(language),
                const SizedBox(height: 16),
                _detailsCard(language),
                const SizedBox(height: 16),
                _attachmentsCard(store, language),
                const SizedBox(height: 22),
                ElevatedButton(
                  style: pawPrimaryButtonStyle(),
                  onPressed: store.isSavingHealth || _uploading
                      ? null
                      : () => _save(store),
                  child: store.isSavingHealth
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(L10n.text(language, 'Save record', '保存', '保存记录',
                          '저장')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _petPicker(List<Pet> pets, AppLanguage language) {
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(L10n.text(language, 'Which pet', 'どのこ', '哪只宠物', '어느 아이'),
              Icons.pets),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pet in pets)
                ChoiceChip(
                  selected: _petId == pet.id,
                  onSelected: (_) => setState(() => _petId = pet.id),
                  label: Text('${petTypeEmoji(pet.type)} ${pet.name}'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _typeCard(AppLanguage language) {
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(
              L10n.text(language, 'What happened', '種類', '记录类型', '기록 종류'),
              Icons.category_outlined),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in HealthRecordType.values
                  .where((t) => !t.isCourseGenerated))
                ChoiceChip(
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                  avatar: Icon(healthRecordIcon(type), size: 16),
                  label: Text(L10n.healthRecordTypeTitle(language, type)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailsCard(AppLanguage language) {
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(
              L10n.healthRecordTypeTitle(language, _type), healthRecordIcon(_type)),
          const SizedBox(height: 10),
          TextField(
            controller: _title,
            maxLength: HealthRecord.maxTitleLength,
            decoration: petFieldDecoration(hintText: _titleHint(language))
                .copyWith(counterText: ''),
          ),
          const SizedBox(height: 12),
          // Backdating is the normal case: you write this up in the evening,
          // about something that happened at the clinic that morning.
          _dateTimeTile(
            label: L10n.text(language, 'When it happened', '日時', '发生时间', '발생 시각'),
            value: _occurredAt,
            language: language,
            onTap: _pickOccurredAt,
          ),
          if (_type.hasClinicDetails) ...[
            const SizedBox(height: 12),
            _field(_clinic,
                L10n.text(language, 'Clinic', '動物病院', '医院', '병원')),
            const SizedBox(height: 12),
            _field(_vet, L10n.text(language, 'Vet', '担当獣医', '医生', '수의사')),
          ],
          if (_type.hasDiagnosis) ...[
            const SizedBox(height: 12),
            _field(
              _diagnosis,
              L10n.text(language, 'Diagnosis', '診断', '诊断', '진단'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _field(
              _treatment,
              L10n.text(language, 'Treatment and medicine prescribed', '処置・処方',
                  '处置与开的药', '처치 및 처방'),
              maxLines: 3,
            ),
          ],
          if (_type == HealthRecordType.labResult) ...[
            const SizedBox(height: 12),
            _field(
              _diagnosis,
              L10n.text(language, 'What the results said', '検査結果', '化验结论',
                  '검사 결과'),
              maxLines: 3,
            ),
          ],
          if (_type.hasNextDue) ...[
            const SizedBox(height: 12),
            _field(
              _productName,
              L10n.text(language, 'Product name', '製品名', '产品名称', '제품명'),
            ),
            const SizedBox(height: 12),
            _field(
              _lotNumber,
              L10n.text(language, 'Lot number', 'ロット番号', '批号', '로트 번호'),
            ),
            const SizedBox(height: 12),
            // The field that turns a filed record into a reminder.
            _nextDueTile(language),
          ],
          if (_type == HealthRecordType.weight) ...[
            const SizedBox(height: 12),
            _numberField(
              _weight,
              L10n.text(language, 'Weight in kg', '体重 (kg)', '体重（kg）',
                  '체중 (kg)'),
            ),
          ],
          if (_type == HealthRecordType.symptom) ...[
            const SizedBox(height: 12),
            _numberField(
              _temperature,
              L10n.text(language, 'Temperature in °C (optional)', '体温 (℃・任意)',
                  '体温（°C，可选）', '체온 (°C, 선택)'),
            ),
          ],
          if (_type.hasCost) ...[
            const SizedBox(height: 12),
            _numberField(
              _cost,
              L10n.text(language, 'Cost (optional)', '費用（任意）', '费用（可选）',
                  '비용 (선택)'),
              decimal: false,
            ),
          ],
          const SizedBox(height: 12),
          _field(
            _notes,
            L10n.text(language, 'Notes', 'メモ', '备注', '메모'),
            maxLines: 4,
            maxLength: HealthRecord.maxNotesLength,
          ),
        ],
      ),
    );
  }

  String _titleHint(AppLanguage language) {
    return switch (_type) {
      HealthRecordType.vetVisit => L10n.text(language, 'e.g. vomiting and off food',
          '例：嘔吐と食欲不振', '例：呕吐、不吃东西', '예: 구토와 식욕 저하'),
      HealthRecordType.vaccination => L10n.text(
          language, 'e.g. rabies vaccination', '例：狂犬病ワクチン', '例：狂犬疫苗',
          '예: 광견병 예방접종'),
      HealthRecordType.deworming => L10n.text(
          language, 'e.g. monthly dewormer', '例：月1回の駆虫薬', '例：每月驱虫',
          '예: 매월 구충제'),
      HealthRecordType.labResult => L10n.text(
          language, 'e.g. blood panel', '例：血液検査', '例：血常规', '예: 혈액 검사'),
      HealthRecordType.surgery => L10n.text(
          language, 'e.g. dental extraction', '例：抜歯手術', '例：拔牙手术', '예: 발치 수술'),
      HealthRecordType.symptom => L10n.text(
          language, 'e.g. limping on the back left leg', '例：左後ろ足を引きずる',
          '例：左后腿一瘸一拐', '예: 왼쪽 뒷다리를 절뚝임'),
      HealthRecordType.weight => L10n.text(
          language, 'e.g. weekly weigh-in', '例：定期の体重測定', '例：每周称重',
          '예: 주간 체중 측정'),
      HealthRecordType.medication => L10n.text(
          language, 'e.g. amoxicillin', '例：アモキシシリン', '例：阿莫西林',
          '예: 아목시실린'),
      HealthRecordType.note => L10n.text(
          language, 'e.g. drinking more water than usual', '例：水をよく飲む',
          '例：比平时喝水多', '예: 평소보다 물을 많이 마심'),
    };
  }

  Widget _field(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength ?? HealthRecord.maxFieldLength,
      decoration:
          petFieldDecoration(hintText: hint).copyWith(counterText: ''),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String hint, {
    bool decimal = true,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]')),
      ],
      decoration: petFieldDecoration(hintText: hint),
    );
  }

  Widget _dateTimeTile({
    required String label,
    required DateTime value,
    required AppLanguage language,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: PawColors.lavender.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            const Icon(Icons.event, size: 16, color: PawColors.purpleDark),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(fontSize: 13, color: PawColors.muted)),
            const Spacer(),
            Text(
              '${DateFormat.yMMMd(language.rawValue).format(value)} '
              '${DateFormat.Hm(language.rawValue).format(value)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: PawColors.purple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nextDueTile(AppLanguage language) {
    final due = _nextDueAt;
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: _pickNextDue,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: PawColors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            const Icon(Icons.notifications_active_outlined,
                size: 16, color: PawColors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                L10n.text(language, 'Next one due', '次回の予定', '下次到期',
                    '다음 예정일'),
                style: const TextStyle(fontSize: 13, color: PawColors.ink),
              ),
            ),
            Text(
              due == null
                  ? L10n.text(language, 'Set a date', '設定する', '设置日期', '날짜 설정')
                  : DateFormat.yMMMd(language.rawValue).format(due),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: PawColors.green,
              ),
            ),
            if (due != null)
              IconButton(
                onPressed: () => setState(() => _nextDueAt = null),
                icon: const Icon(Icons.close, size: 16, color: PawColors.muted),
              ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentsCard(CareStore store, AppLanguage language) {
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(
              L10n.text(language, 'Photos', '写真', '照片', '사진'),
              Icons.photo_library_outlined),
          const SizedBox(height: 4),
          Text(
            L10n.text(
              language,
              'Lab printouts, prescriptions, or the spot you are worried about.',
              '検査結果や処方箋、気になる部分の写真。',
              '化验单、处方，或者你担心的那个部位。',
              '검사지, 처방전, 걱정되는 부위 사진.',
            ),
            style: const TextStyle(fontSize: 12, color: PawColors.muted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final attachment in _attachments)
                _thumbnail(attachment, language),
              if (_attachments.length < HealthRecord.maxAttachments)
                _addPhotoTile(store, language),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumbnail(HealthAttachment attachment, AppLanguage language) {
    return GestureDetector(
      onLongPress: () => _confirmRemoveAttachment(attachment, language),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: SizedBox(
              width: 88,
              height: 88,
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
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: () => _confirmRemoveAttachment(attachment, language),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addPhotoTile(CareStore store, AppLanguage language) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: _uploading ? null : () => _pickPhoto(store, language),
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: PawColors.lavender.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: PawColors.purple.withValues(alpha: 0.25),
            style: BorderStyle.solid,
          ),
        ),
        alignment: Alignment.center,
        child: _uploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_a_photo_outlined,
                color: PawColors.purple, size: 22),
      ),
    );
  }

  Widget _fieldLabel(String title, IconData icon) =>
      fieldLabel(title, icon);

  Future<void> _pickOccurredAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (!mounted) return;
    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _occurredAt.hour,
        time?.minute ?? _occurredAt.minute,
      );
    });
  }

  Future<void> _pickNextDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDueAt ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    setState(() => _nextDueAt = picked);
  }

  Future<void> _pickPhoto(CareStore store, AppLanguage language) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: PawColors.purple),
              title: Text(
                  L10n.text(language, 'Take a photo', '写真を撮る', '拍照', '사진 찍기')),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: PawColors.purple),
              title: Text(L10n.text(
                  language, 'Choose from library', 'ライブラリから選ぶ', '从相册选择',
                  '앨범에서 선택')),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    setState(() => _uploading = true);
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (image == null) return;
      final Uint8List bytes = await image.readAsBytes();
      final attachment = await store.uploadHealthAttachment(
        recordID: _recordId,
        bytes: bytes,
      );
      if (attachment == null || !mounted) return;
      setState(() => _attachments = [..._attachments, attachment]);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmRemoveAttachment(
    HealthAttachment attachment,
    AppLanguage language,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.text(
            language, 'Remove this photo?', 'この写真を削除しますか？', '删除这张照片？',
            '이 사진을 삭제할까요?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              L10n.text(language, 'Remove', '削除', '删除', '삭제'),
              style: const TextStyle(color: PawColors.rose),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _attachments =
          _attachments.where((a) => a.id != attachment.id).toList();
    });
  }

  double? _parseDouble(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  String? _trimmedOrNull(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save(CareStore store) async {
    final caregiver = store.currentCaregiver;
    final pet = store.household?.pets.where((p) => p.id == _petId).firstOrNull;
    if (caregiver == null || pet == null) return;
    final existing = widget.record;
    final isClinic = _type.hasClinicDetails;

    final record = HealthRecord(
      id: _recordId,
      petId: _petId,
      petNameSnapshot: pet.name,
      type: _type,
      occurredAt: _occurredAt,
      title: _title.text.trim(),
      clinicName: isClinic || _type.hasNextDue ? _trimmedOrNull(_clinic) : null,
      vetName: isClinic ? _trimmedOrNull(_vet) : null,
      diagnosis: _type.hasDiagnosis || _type == HealthRecordType.labResult
          ? _trimmedOrNull(_diagnosis)
          : null,
      treatment: _type.hasDiagnosis ? _trimmedOrNull(_treatment) : null,
      costMinor: _type.hasCost ? int.tryParse(_cost.text.trim()) : null,
      currency: _type.hasCost && _cost.text.trim().isNotEmpty ? 'JPY' : null,
      productName: _type.hasNextDue ? _trimmedOrNull(_productName) : null,
      lotNumber: _type.hasNextDue ? _trimmedOrNull(_lotNumber) : null,
      nextDueAt: _type.hasNextDue ? _nextDueAt : null,
      weightKg: _type == HealthRecordType.weight ? _parseDouble(_weight) : null,
      temperatureC: _type == HealthRecordType.symptom
          ? _parseDouble(_temperature)
          : null,
      notes: _trimmedOrNull(_notes),
      attachments: _attachments,
      createdByID: existing?.createdByID ?? caregiver.id,
      createdByNameSnapshot:
          existing?.createdByNameSnapshot ?? caregiver.displayName,
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: existing == null ? null : DateTime.now(),
      updatedByID: existing == null ? null : caregiver.id,
      updatedByNameSnapshot: existing == null ? null : caregiver.displayName,
      revision: existing?.revision ?? 0,
    );

    final saved = await store.saveHealthRecord(record);
    if (saved && mounted) Navigator.of(context).pop();
  }
}
