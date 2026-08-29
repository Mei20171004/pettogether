import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/health.dart';
import '../models/models.dart';

enum AppLanguage {
  english('en', 'English'),
  japanese('ja', '日本語'),
  chinese('zh', '中文'),
  korean('ko', '한국어');

  const AppLanguage(this.rawValue, this.label);

  final String rawValue;
  final String label;
}

/// Minimal four-language helper, mirroring `L10n.text` in the Swift code.
/// Every call site passes all four strings; this keeps the port readable
/// without a full ARB/flutter_localizations setup.
abstract final class L10n {
  static String text(
    AppLanguage language,
    String english,
    String japanese,
    String chinese,
    String korean,
  ) {
    return switch (language) {
      AppLanguage.english => english,
      AppLanguage.japanese => japanese,
      AppLanguage.chinese => chinese,
      AppLanguage.korean => korean,
    };
  }

  static String categoryTitle(AppLanguage language, CareCategory category) {
    if (!category.isBuiltIn) return category.name ?? category.id;
    return switch (category.id) {
      'feeding' => text(language, 'Feeding', '食事', '喂食', '식사'),
      'walking' => text(language, 'Walking', '散歩', '散步', '산책'),
      'medication' => text(language, 'Medication', '薬', '用药', '약'),
      'grooming' => text(language, 'Grooming', 'グルーミング', '美容', '미용'),
      'hospital' => text(language, 'Vet visit', '病院', '去医院', '병원 방문'),
      'deworming' => text(language, 'Deworming', '駆虫', '驱虫', '구충'),
      'nailTrim' => text(language, 'Trim nails', '爪切り', '修剪指甲', '발톱 정리'),
      'peePad' => text(language, 'Change pee pad', 'トイレシート交換', '更换尿垫',
          '배변패드 교체'),
      'catLitter' => text(language, 'Change litter', '猫砂交換', '更换猫砂', '모래 교체'),
      'water' => text(language, 'Change water', '水替え', '换水', '물 갈기'),
      'newFood' => text(language, 'New food', '新しいごはん', '添加新猫粮', '새 사료'),
      'dogBath' => text(language, 'Bath', 'シャンプー', '洗澡', '목욕'),
      'dogTraining' => text(language, 'Training', 'しつけ', '训练', '훈련'),
      'birdCage' => text(language, 'Clean cage', 'ケージ掃除', '清洗鸟笼', '새장 청소'),
      'birdFeather' => text(language, 'Feather care', '羽のお手入れ', '羽毛护理',
          '깃털 관리'),
      'rabbitHay' => text(language, 'Fresh hay', '牧草', '喂干草', '건초'),
      'rabbitBedding' => text(language, 'Change bedding', '床材交換', '更换垫料',
          '깔짚 교체'),
      'snakeFeed' => text(language, 'Feed', '給餌', '喂食', '먹이'),
      'snakeShed' => text(language, 'Shed check', '脱皮チェック', '检查蜕皮', '탈피 확인'),
      'snakeTerrarium' => text(language, 'Terrarium', '温度・湿度管理', '调节温湿度',
          '사육장 관리'),
      _ => text(language, 'Other', 'その他', '其他', '기타'),
    };
  }

  static String medicationFormTitle(AppLanguage language, MedicationForm form) {
    return switch (form) {
      MedicationForm.oral => text(language, 'Tablet / oral', '飲み薬', '口服', '경구약'),
      MedicationForm.topical =>
        text(language, 'Ointment / spot-on', '塗り薬', '外用', '연고'),
      MedicationForm.injection => text(language, 'Injection', '注射', '注射', '주사'),
      MedicationForm.eyeDrop => text(language, 'Eye drops', '目薬', '滴眼液', '안약'),
      MedicationForm.earDrop => text(language, 'Ear drops', '点耳薬', '滴耳液', '점이약'),
      MedicationForm.inhaler => text(language, 'Inhaler', '吸入薬', '吸入剂', '흡입기'),
      MedicationForm.powder => text(language, 'Powder', '粉薬', '散剂', '가루약'),
      MedicationForm.other => text(language, 'Other', 'その他', '其他', '기타'),
    };
  }

  static String healthRecordTypeTitle(
    AppLanguage language,
    HealthRecordType type,
  ) {
    return switch (type) {
      HealthRecordType.vetVisit =>
        text(language, 'Vet visit', '通院', '就诊', '병원 방문'),
      HealthRecordType.vaccination =>
        text(language, 'Vaccination', 'ワクチン', '疫苗', '예방접종'),
      HealthRecordType.deworming =>
        text(language, 'Deworming', '駆虫', '驱虫', '구충'),
      HealthRecordType.labResult =>
        text(language, 'Test result', '検査結果', '化验/影像', '검사 결과'),
      HealthRecordType.surgery => text(language, 'Surgery', '手術', '手术', '수술'),
      HealthRecordType.symptom =>
        text(language, 'Symptom', '症状', '症状', '증상'),
      HealthRecordType.weight => text(language, 'Weight', '体重', '体重', '체중'),
      HealthRecordType.medication =>
        text(language, 'Medication', '服薬', '用药', '복약'),
      HealthRecordType.note => text(language, 'Note', 'メモ', '随手记', '메모'),
    };
  }

  static String skipReasonTitle(
    AppLanguage language,
    MedicationSkipReason reason,
  ) {
    return switch (reason) {
      MedicationSkipReason.petRefused =>
        text(language, 'Refused it', '飲んでくれない', '不肯吃', '먹지 않음'),
      MedicationSkipReason.vomited =>
        text(language, 'Brought it back up', '吐いた', '吐了', '토함'),
      MedicationSkipReason.outOfStock =>
        text(language, 'Ran out of medicine', '薬が切れた', '药没了', '약이 떨어짐'),
      MedicationSkipReason.vetInstruction =>
        text(language, 'Vet said to stop', '獣医の指示', '医嘱停用', '수의사 지시'),
      MedicationSkipReason.alreadyGiven =>
        text(language, 'Already given', 'すでにあげた', '已经喂过了', '이미 먹였음'),
      MedicationSkipReason.other =>
        text(language, 'Something else', 'その他', '其他', '기타'),
    };
  }

  /// "Every day" / "Mon, Thu" — how often a course is given.
  static String weekdaySummary(AppLanguage language, List<int> weekdays) {
    if (weekdays.length >= 7) {
      return text(language, 'Every day', '毎日', '每天', '매일');
    }
    final sorted = [...weekdays]..sort();
    return sorted.map((d) => weekdayShort(language, d)).join(' · ');
  }

  /// [weekday] uses this app's 1 = Sunday … 7 = Saturday convention.
  static String weekdayShort(AppLanguage language, int weekday) {
    return switch (weekday) {
      1 => text(language, 'Sun', '日', '日', '일'),
      2 => text(language, 'Mon', '月', '一', '월'),
      3 => text(language, 'Tue', '火', '二', '화'),
      4 => text(language, 'Wed', '水', '三', '수'),
      5 => text(language, 'Thu', '木', '四', '목'),
      6 => text(language, 'Fri', '金', '五', '금'),
      _ => text(language, 'Sat', '土', '六', '토'),
    };
  }
}

/// Persists the selected language to `shared_preferences`, like the Swift
/// `AppLanguageStore`.
class AppLanguageStore extends ChangeNotifier {
  AppLanguageStore(this._language);

  static const _key = 'pettogether.language';

  AppLanguage _language;
  AppLanguage get language => _language;

  set language(AppLanguage value) {
    if (value == _language) return;
    _language = value;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_key, value.rawValue);
    });
  }

  static Future<AppLanguage> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? 'en';
    return AppLanguage.values.firstWhere(
      (e) => e.rawValue == raw,
      orElse: () => AppLanguage.english,
    );
  }
}
