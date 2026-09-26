import 'package:cloud_firestore/cloud_firestore.dart';

import '../l10n/l10n.dart';

class ProMenuItem {
  const ProMenuItem({
    required this.id,
    required this.sort,
    required this.url,
    required this.labels,
  });

  final String id;
  final int sort;
  final Uri url;
  final Map<String, String> labels;

  String title(AppLanguage language) {
    final code = switch (language) {
      AppLanguage.english => 'en',
      AppLanguage.japanese => 'jp',
      AppLanguage.chinese => 'cn',
      AppLanguage.korean => 'kr',
    };
    return labels[code] ?? labels['en'] ?? labels.values.first;
  }

  static ProMenuItem? fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) => fromData(document.id, document.data());

  static ProMenuItem? fromData(String id, Map<String, dynamic> data) {
    final sort = data['sort'];
    final rawUrl = data['url'];
    if (sort is! int || rawUrl is! String) return null;
    final url = Uri.tryParse(rawUrl.trim());
    if (url == null || url.scheme != 'https' || url.host.isEmpty) return null;
    final labels = <String, String>{};
    for (final code in ['en', 'jp', 'cn', 'kr']) {
      final value = data[code];
      if (value is String && value.trim().isNotEmpty) {
        labels[code] = value.trim();
      }
    }
    if (labels.isEmpty) return null;
    return ProMenuItem(id: id, sort: sort, url: url, labels: labels);
  }
}

class ProMenuService {
  ProMenuService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<ProMenuItem>> watchItems() => _firestore
      .collection('promenu')
      .orderBy('sort', descending: true)
      .snapshots()
      .map((snapshot) {
        final items = snapshot.docs
            .map(ProMenuItem.fromDocument)
            .whereType<ProMenuItem>()
            .toList();
        items.sort((a, b) {
          final bySort = b.sort.compareTo(a.sort);
          return bySort != 0 ? bySort : a.id.compareTo(b.id);
        });
        return items;
      });
}
