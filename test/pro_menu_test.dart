import 'package:flutter_test/flutter_test.dart';
import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/services/pro_menu_service.dart';

void main() {
  test('reads the live promenu field shape and localized labels', () {
    final item = ProMenuItem.fromData('menu-1', {
      'en': 'History',
      'jp': '履歴',
      'cn': '历史',
      'kr': '기록',
      'sort': 5,
      'url': 'https://pettogether-pro.web.app/historyreport.html',
    });

    expect(item, isNotNull);
    expect(item!.sort, 5);
    expect(item.title(AppLanguage.chinese), '历史');
    expect(item.title(AppLanguage.japanese), '履歴');
    expect(item.url.scheme, 'https');
  });

  test('skips entries without a valid HTTPS page', () {
    expect(
      ProMenuItem.fromData('unsafe', {
        'en': 'Unsafe',
        'sort': 2,
        'url': 'javascript:alert(1)',
      }),
      isNull,
    );
    expect(
      ProMenuItem.fromData('missing-sort', {
        'en': 'Missing',
        'url': 'https://example.com',
      }),
      isNull,
    );
  });
}
