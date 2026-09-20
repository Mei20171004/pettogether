import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';

/// A compact wheel picker used anywhere the app asks for a time.
///
/// The previous Material clock face made precise minute selection needlessly
/// fiddly. Keeping this picker in one place also prevents task and medication
/// forms from drifting into different interactions.
Future<TimeOfDay?> showPetTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  required AppLanguage language,
}) {
  var selected = initialTime;
  final now = DateTime.now();

  return showModalBottomSheet<TimeOfDay>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: PawColors.cream,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: 330,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  TextButton(
                    key: const ValueKey('pet-time-picker-cancel'),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(
                      L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소'),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      L10n.text(
                        language,
                        'Choose time',
                        '時間を選択',
                        '选择时间',
                        '시간 선택',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: PawColors.ink,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('pet-time-picker-done'),
                    onPressed: () => Navigator.of(sheetContext).pop(selected),
                    child: Text(
                      L10n.text(language, 'Done', '完了', '完成', '완료'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: CupertinoDatePicker(
                key: const ValueKey('pet-time-picker-wheel'),
                mode: CupertinoDatePickerMode.time,
                use24hFormat: MediaQuery.alwaysUse24HourFormatOf(sheetContext),
                initialDateTime: DateTime(
                  now.year,
                  now.month,
                  now.day,
                  initialTime.hour,
                  initialTime.minute,
                ),
                onDateTimeChanged: (value) {
                  selected = TimeOfDay(hour: value.hour, minute: value.minute);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
