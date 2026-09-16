import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../l10n/l10n.dart';
import '../store/purchase_store.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

/// Marketing + paywall page for pettogether Pro. Plans come from the current
/// RevenueCat offering; the hero CTA buys the selected package and the footer
/// restores previous purchases.
class ProView extends StatefulWidget {
  const ProView({super.key, this.reason});

  /// Short, already-localized sentence naming the feature that sent the user
  /// here. Null when the page is opened from settings.
  final String? reason;

  @override
  State<ProView> createState() => _ProViewState();
}

/// Opens the Pro page from a gated feature.
Future<void> showProPaywall(BuildContext context, {String? reason}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ProView(reason: reason),
    ),
  );
}

class _ProViewState extends State<ProView> {
  Package? _selected;

  @override
  void initState() {
    super.initState();
    final purchases = context.read<PurchaseStore>();
    if (purchases.isAvailable && purchases.packages.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => purchases.refreshOfferings(),
      );
    }
  }

  Package? _selectedOrDefault(List<Package> packages) {
    if (_selected != null && packages.contains(_selected)) return _selected;
    if (packages.isEmpty) return null;
    return packages.firstWhere(
      (p) => p.packageType == PackageType.annual,
      orElse: () => packages.first,
    );
  }

  Future<void> _buy(Package package) async {
    final purchases = context.read<PurchaseStore>();
    final language = context.read<AppLanguageStore>().language;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final unlocked = await purchases.purchase(package);
      if (!mounted) return;
      if (unlocked) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              L10n.text(
                language,
                'Welcome to pettogether Pro!',
                'pettogether Pro へようこそ！',
                '欢迎加入 pettogether Pro！',
                'pettogether Pro에 오신 것을 환영합니다!',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            L10n.text(
              language,
              'Purchase failed. Please try again.',
              '購入に失敗しました。もう一度お試しください。',
              '购买失败，请重试。',
              '구매에 실패했습니다. 다시 시도해 주세요.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _restore() async {
    final purchases = context.read<PurchaseStore>();
    final language = context.read<AppLanguageStore>().language;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final restored = await purchases.restore();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            restored
                ? L10n.text(
                    language,
                    'Pro restored.',
                    'Pro を復元しました。',
                    '已恢复 Pro。',
                    'Pro를 복원했습니다.',
                  )
                : L10n.text(
                    language,
                    'No previous purchase found.',
                    '以前の購入が見つかりませんでした。',
                    '未找到之前的购买记录。',
                    '이전 구매 내역을 찾을 수 없습니다.',
                  ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            L10n.text(
              language,
              'Restore failed. Please try again.',
              '復元に失敗しました。もう一度お試しください。',
              '恢复失败，请重试。',
              '복원에 실패했습니다. 다시 시도해 주세요.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    final purchases = context.watch<PurchaseStore>();
    final packages = purchases.packages;
    final selected = _selectedOrDefault(packages);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          L10n.text(
            language,
            'pettogether Pro',
            'pettogether Pro',
            'pettogether Pro',
            'pettogether Pro',
          ),
        ),
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _heroCard(context, language, purchases, selected),
                const SizedBox(height: 22),
                PetSectionTitle(
                  title: L10n.text(
                    language,
                    'Made for shared care',
                    'シェアケアのために',
                    '为共同照护而生',
                    '함께하는 케어를 위해',
                  ),
                  detail: L10n.text(
                    language,
                    "What's included",
                    '含まれるもの',
                    '包含内容',
                    '포함 내용',
                  ),
                ),
                const SizedBox(height: 12),
                const _Feature(
                  icon: Icons.auto_awesome_rounded,
                  color: PawColors.purple,
                  title: 'AI care entry',
                  titleJa: 'AIでケア入力',
                  titleZh: 'AI 待办录入',
                  titleKo: 'AI 케어 입력',
                  detail: 'Describe the routine in a sentence and get the schedule.',
                  detailJa: '一文で説明すれば、予定ができあがります。',
                  detailZh: '一句话描述，自动生成日程。',
                  detailKo: '한 문장으로 설명하면 일정이 만들어집니다.',
                ),
                const SizedBox(height: 12),
                const _Feature(
                  icon: Icons.photo_library_rounded,
                  color: PawColors.rose,
                  title: 'Photos on medical records',
                  titleJa: '医療記録に写真',
                  titleZh: '医疗记录照片',
                  titleKo: '진료 기록 사진',
                  detail: 'Keep lab sheets and prescriptions with the record.',
                  detailJa: '検査結果や処方を記録と一緒に保存。',
                  detailZh: '把检查单和处方留在记录里。',
                  detailKo: '검사지와 처방을 기록과 함께 보관합니다.',
                ),
                const SizedBox(height: 12),
                const _Feature(
                  icon: Icons.picture_as_pdf_rounded,
                  color: PawColors.blue,
                  title: 'Vet visit pack',
                  titleJa: '受診パック',
                  titleZh: '兽医就诊包',
                  titleKo: '진료 패키지',
                  detail: 'Export one PDF to hand to the vet.',
                  detailJa: '獣医に渡せるPDFを書き出せます。',
                  detailZh: '导出一份可直接交给兽医的 PDF。',
                  detailKo: '수의사에게 건넬 PDF를 내보냅니다.',
                ),
                const SizedBox(height: 12),
                const _Feature(
                  icon: Icons.medication_rounded,
                  color: PawColors.green,
                  title: 'Multiple medication courses',
                  titleJa: '複数の投薬コース',
                  titleZh: '多个用药疗程',
                  titleKo: '여러 투약 코스',
                  detail: 'Track every course at once, with adherence.',
                  detailJa: 'すべてのコースを同時に、服薬率つきで管理。',
                  detailZh: '同时跟踪所有疗程，含依从率。',
                  detailKo: '모든 코스를 한 번에, 복약률과 함께 관리합니다.',
                ),
                const SizedBox(height: 22),
                if (!purchases.isPro)
                  ..._plans(language, purchases, packages, selected),
                const SizedBox(height: 16),
                if (purchases.isAvailable)
                  Center(
                    child: TextButton(
                      onPressed: purchases.isPurchasing ? null : _restore,
                      child: Text(
                        L10n.text(
                          language,
                          'Restore purchases',
                          '購入を復元',
                          '恢复购买',
                          '구매 복원',
                        ),
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

  List<Widget> _plans(
    AppLanguage language,
    PurchaseStore purchases,
    List<Package> packages,
    Package? selected,
  ) {
    if (!purchases.isAvailable) {
      return [
        _notice(
          L10n.text(
            language,
            'Purchases are not available on this platform.',
            'このプラットフォームでは購入できません。',
            '此平台不支持购买。',
            '이 플랫폼에서는 구매할 수 없습니다.',
          ),
        ),
      ];
    }
    if (purchases.isLoadingOfferings && packages.isEmpty) {
      return const [Center(child: CircularProgressIndicator())];
    }
    if (packages.isEmpty) {
      return [
        _notice(
          L10n.text(
            language,
            'Plans could not be loaded. Pull to retry.',
            'プランを読み込めませんでした。',
            '无法加载套餐。',
            '요금제를 불러올 수 없습니다.',
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton(
            onPressed: purchases.refreshOfferings,
            child: Text(L10n.text(language, 'Retry', '再試行', '重试', '다시 시도')),
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < packages.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        _PriceCard(
          package: packages[i],
          highlighted: packages[i] == selected,
          onTap: purchases.isPurchasing
              ? null
              : () => setState(() => _selected = packages[i]),
        ),
      ],
    ];
  }

  Widget _notice(String text) => PetCard(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: PawColors.muted),
    ),
  );

  Widget _heroCard(
    BuildContext context,
    AppLanguage language,
    PurchaseStore purchases,
    Package? selected,
  ) {
    final isPro = purchases.isPro;
    final canBuy =
        purchases.isAvailable && selected != null && !purchases.isPurchasing;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [PawColors.purpleDark, PawColors.purple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: PawColors.purpleDark.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 32,
            backgroundColor: Color(0x33FFFFFF),
            child: Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: 12),
          if (widget.reason != null && !isPro) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                widget.reason!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            isPro
                ? L10n.text(
                    language,
                    "You're Pro. Thank you!",
                    'Pro をご利用中。ありがとう！',
                    '您已是 Pro 用户，感谢支持！',
                    'Pro 이용 중입니다. 감사합니다!',
                  )
                : L10n.text(
                    language,
                    'More calm, more care.',
                    'もっと穏やかに、もっとケアを。',
                    '更从容，更用心。',
                    '더 차분하게, 더 세심하게.',
                  ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            L10n.text(
              language,
              'pettogether Pro gives every caregiver a clearer shared routine.',
              'pettogether Pro はすべてのケアギバーに、より明確な共有ルーティンを。',
              'pettogether Pro 让每位照护者的共享日常更清晰。',
              'pettogether Pro는 모든 케어기버에게 더 명확한 공유 루틴을 제공합니다.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xEFFFFFFF), height: 1.35),
          ),
          if (!isPro) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: canBuy ? () => _buy(selected) : null,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: PawColors.purpleDark,
              ),
              icon: purchases.isPurchasing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(
                selected == null
                    ? L10n.text(
                        language,
                        'Go Pro',
                        'Pro にする',
                        '升级 Pro',
                        'Pro 시작',
                      )
                    : L10n.text(
                        language,
                        'Go Pro · ${selected.storeProduct.priceString}',
                        'Pro にする · ${selected.storeProduct.priceString}',
                        '升级 Pro · ${selected.storeProduct.priceString}',
                        'Pro 시작 · ${selected.storeProduct.priceString}',
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.titleJa,
    required this.titleZh,
    required this.titleKo,
    required this.detail,
    required this.detailJa,
    required this.detailZh,
    required this.detailKo,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String titleJa;
  final String titleZh;
  final String titleKo;
  final String detail;
  final String detailJa;
  final String detailZh;
  final String detailKo;

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    return PetCard(
      padding: 14,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.text(language, title, titleJa, titleZh, titleKo),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: PawColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  L10n.text(language, detail, detailJa, detailZh, detailKo),
                  style: const TextStyle(color: PawColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.package,
    required this.highlighted,
    this.onTap,
  });

  final Package package;
  final bool highlighted;
  final VoidCallback? onTap;

  String _title(AppLanguage language) => switch (package.packageType) {
    PackageType.annual => L10n.text(language, 'Yearly', '年額', '按年', '연간'),
    PackageType.monthly => L10n.text(language, 'Monthly', '月額', '按月', '월간'),
    PackageType.weekly => L10n.text(language, 'Weekly', '週額', '按周', '주간'),
    PackageType.sixMonth => L10n.text(
      language,
      '6 months',
      '6か月',
      '6 个月',
      '6개월',
    ),
    PackageType.threeMonth => L10n.text(
      language,
      '3 months',
      '3か月',
      '3 个月',
      '3개월',
    ),
    PackageType.twoMonth => L10n.text(
      language,
      '2 months',
      '2か月',
      '2 个月',
      '2개월',
    ),
    PackageType.lifetime => L10n.text(language, 'Lifetime', '買い切り', '终身', '평생'),
    _ => package.storeProduct.title,
  };

  String _period(AppLanguage language) => switch (package.packageType) {
    PackageType.annual => L10n.text(
      language,
      ' / year',
      ' / 年',
      ' / 年',
      ' / 년',
    ),
    PackageType.monthly => L10n.text(
      language,
      ' / month',
      ' / 月',
      ' / 月',
      ' / 월',
    ),
    PackageType.weekly => L10n.text(
      language,
      ' / week',
      ' / 週',
      ' / 周',
      ' / 주',
    ),
    _ => '',
  };

  String _detail(AppLanguage language) {
    if (package.packageType == PackageType.annual) {
      return L10n.text(language, 'Best value', 'おすすめ', '最划算', '최고의 가치');
    }
    if (package.packageType == PackageType.lifetime) {
      return L10n.text(language, 'One-time payment', '一回払い', '一次性付款', '일회성 결제');
    }
    return L10n.text(
      language,
      'Cancel anytime',
      'いつでも解約可能',
      '随时取消',
      '언제든 해지 가능',
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: highlighted ? PawColors.lavender : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: highlighted
                ? PawColors.purple
                : PawColors.purple.withValues(alpha: 0.1),
            width: highlighted ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title(language),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: PawColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _detail(language),
                    style: TextStyle(
                      color: highlighted
                          ? PawColors.purpleDark
                          : PawColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              package.storeProduct.priceString,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: PawColors.ink,
              ),
            ),
            Text(
              _period(language),
              style: const TextStyle(color: PawColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
