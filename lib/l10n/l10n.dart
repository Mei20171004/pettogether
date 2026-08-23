import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}

/// Persists the selected language to `shared_preferences`, like the Swift
/// `AppLanguageStore`.
class AppLanguageStore extends ChangeNotifier {
  AppLanguageStore(this._language);

  static const _key = 'copaw.language';

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
