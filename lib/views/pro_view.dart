import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/app_config.dart';
import '../l10n/l10n.dart';
import '../store/purchase_store.dart';
import '../store/pro_access.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

enum ProFeature { health, multiPet, ai }

extension ProFeatureDetails on ProFeature {
  String get entitlementId => switch (this) {
    ProFeature.health => AppConfig.proEntitlementId,
    ProFeature.multiPet => AppConfig.multiPetEntitlementId,
    ProFeature.ai => AppConfig.aiEntitlementId,
  };

  bool isUnlocked(PurchaseStore purchases) => switch (this) {
    ProFeature.health => purchases.isPro,
    ProFeature.multiPet => purchases.hasMultiPet,
    ProFeature.ai => purchases.hasAi,
  };

  bool matches(Package package) {
    final productId = package.storeProduct.identifier;
    return switch (this) {
      ProFeature.health => productId.startsWith('pettogether_pro_'),
      ProFeature.multiPet => productId == AppConfig.multiPetMonthlyProductId,
      ProFeature.ai => productId == AppConfig.aiMonthlyProductId,
    };
  }

  String title(AppLanguage language) => switch (this) {
    ProFeature.health => 'pettogether Pro',
    ProFeature.multiPet => L10n.text(
      language,
      'More pets',
      '複数のペット',
      '更多宠物',
      '여러 반려동물',
    ),
    ProFeature.ai => L10n.text(
      language,
      'AI care entry',
      'AIケア入力',
      'AI 护理录入',
      'AI 케어 입력',
    ),
  };

  String summary(AppLanguage language) => switch (this) {
    ProFeature.health => L10n.text(
      language,
      'Health tools for clearer shared care.',
      '共有ケアをより明確にする健康管理ツール。',
      '让共同照护更清晰的健康工具。',
      '공동 돌봄을 더 명확하게 만드는 건강 도구.',
    ),
    ProFeature.multiPet => L10n.text(
      language,
      'Your first pet is free. Add a second pet and beyond for ¥300/month.',
      '1匹目は無料。2匹目以降は月額300円です。',
      '第 1 只宠物免费；添加第 2 只及更多宠物为每月 ¥300。',
      '첫 반려동물은 무료이며, 두 번째부터 월 ¥300입니다.',
    ),
    ProFeature.ai => L10n.text(
      language,
      'Turn a sentence into a care schedule for ¥300/month.',
      '月額300円で、文章からケア予定を作成します。',
      '每月 ¥300，用一句话生成宠物护理日程。',
      '월 ¥300으로 한 문장을 돌봄 일정으로 바꿉니다.',
    ),
  };

  String cta(AppLanguage language) => switch (this) {
    ProFeature.health => L10n.text(
      language,
      'Go Pro',
      'Pro にする',
      '升级 Pro',
      'Pro 시작',
    ),
    ProFeature.multiPet => L10n.text(
      language,
      'Unlock more pets',
      '複数のペットを追加',
      '解锁更多宠物',
      '더 많은 반려동물 잠금 해제',
    ),
    ProFeature.ai => L10n.text(
      language,
      'Unlock AI',
      'AIを利用する',
      '解锁 AI',
      'AI 잠금 해제',
    ),
  };

  IconData get icon => switch (this) {
    ProFeature.health => Icons.workspace_premium_rounded,
    ProFeature.multiPet => Icons.pets_rounded,
    ProFeature.ai => Icons.auto_awesome_rounded,
  };
}

/// Marketing + paywall page for pettogether Pro. Plans come from the current
/// RevenueCat offering; the hero CTA buys the selected package and the footer
/// restores previous purchases.
class ProView extends StatefulWidget {
  const ProView({super.key, this.reason, this.feature = ProFeature.health});

  /// Short, already-localized sentence naming the feature that sent the user
  /// here. Null when the page is opened from settings.
  final String? reason;
  final ProFeature feature;

  @override
  State<ProView> createState() => _ProViewState();
}

/// Opens the Pro page from a gated feature.
Future<void> showProPaywall(
  BuildContext context, {
  String? reason,
  ProFeature feature = ProFeature.health,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ProView(reason: reason, feature: feature),
    ),
  );
}

class _ProViewState extends State<ProView> {
  Package? _selected;
  final TextEditingController _couponController = TextEditingController();
  bool _redeemingCoupon = false;

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  Future<void> _redeemCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty || _redeemingCoupon) return;
    setState(() => _redeemingCoupon = true);
    final active = await context.read<ProAccess>().redeemFreeCoupon(code);
    if (!mounted) return;
    setState(() => _redeemingCoupon = false);
    final language = context.read<AppLanguageStore>().language;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          active
              ? L10n.text(
                  language,
                  'Free coupon activated. All features are unlocked until the deadline.',
                  '無料クーポンを適用しました。期限まで全機能を利用できます。',
                  '免费优惠码已激活，截止前可使用全部功能。',
                  '무료 쿠폰이 활성화되었습니다. 기한까지 모든 기능을 사용할 수 있습니다.',
                )
              : L10n.text(
                  language,
                  'Invalid or expired coupon, or unable to connect. Please try again.',
                  'クーポンが無効・期限切れ、または接続できません。再試行してください。',
                  '优惠码无效、已过期或暂时无法连接，请重试。',
                  '쿠폰이 유효하지 않거나 만료되었거나 연결할 수 없습니다. 다시 시도하세요.',
                ),
        ),
      ),
    );
  }

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
      final unlocked = await purchases.purchase(
        package,
        entitlementId: widget.feature.entitlementId,
      );
      if (!mounted) return;
      if (unlocked) {
        unawaited(context.read<ProAccess>().syncUserInfoAfterPurchase());
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              L10n.text(
                language,
                '${widget.feature.title(language)} unlocked.',
                '${widget.feature.title(language)}を利用できます。',
                '已解锁${widget.feature.title(language)}。',
                '${widget.feature.title(language)} 기능이 활성화되었습니다.',
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
      final restored = await purchases.restore(
        entitlementId: widget.feature.entitlementId,
      );
      if (restored && mounted) {
        unawaited(context.read<ProAccess>().syncUserInfoAfterPurchase());
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            restored
                ? L10n.text(
                    language,
                    '${widget.feature.title(language)} restored.',
                    '${widget.feature.title(language)}を復元しました。',
                    '已恢复${widget.feature.title(language)}。',
                    '${widget.feature.title(language)} 기능을 복원했습니다.',
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
    final access = context.watch<ProAccess>();
    final packages = purchases.packages.where(widget.feature.matches).toList();
    final selected = _selectedOrDefault(packages);
    return Scaffold(
      backgroundColor: PawColors.cream,
      appBar: AppBar(title: Text(widget.feature.title(language))),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _heroCard(context, language, purchases, selected),
                const SizedBox(height: 16),
                _couponCard(language, access),
                const SizedBox(height: 22),
                PetSectionTitle(
                  title: L10n.text(
                    language,
                    'What this unlocks',
                    '利用できる機能',
                    '解锁内容',
                    '잠금 해제 기능',
                  ),
                  detail: L10n.text(
                    language,
                    widget.feature == ProFeature.health
                        ? 'Health Pro'
                        : '¥300 / month',
                    widget.feature == ProFeature.health ? '健康 Pro' : '月額 ¥300',
                    widget.feature == ProFeature.health ? '健康 Pro' : '¥300 / 月',
                    widget.feature == ProFeature.health ? '건강 Pro' : '월 ¥300',
                  ),
                ),
                const SizedBox(height: 12),
                ..._featureCards(widget.feature),
                if (widget.feature != ProFeature.health) ...[
                  const SizedBox(height: 12),
                  Text(
                    L10n.text(
                      language,
                      'Subscriptions are independent. Using both costs ¥600/month total.',
                      '2つは別々のサブスクリプションです。両方利用する場合は合計月額600円です。',
                      '两项为独立订阅；同时使用时合计 ¥600/月。',
                      '두 기능은 별도 구독이며, 둘 다 이용하면 월 총 ¥600입니다.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: PawColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (!access.isFreeCouponActive &&
                    !widget.feature.isUnlocked(purchases))
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

  Widget _couponCard(AppLanguage language, ProAccess access) {
    final expiresAt = access.freeCouponExpiresAt;
    if (expiresAt != null) {
      final japanTime = expiresAt.toUtc().add(const Duration(hours: 9));
      return PetCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.text(
                language,
                'Free coupon active',
                '無料クーポン適用中',
                '免费优惠码使用中',
                '무료 쿠폰 사용 중',
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '${L10n.text(language, 'All features free until', '全機能の無料期限', '全部功能免费至', '모든 기능 무료 종료 시각')} '
              '${DateFormat('yyyy/MM/dd HH:mm').format(japanTime)} JST',
            ),
          ],
        ),
      );
    }
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            L10n.text(
              language,
              'Have a Free coupon?',
              '無料クーポンをお持ちですか？',
              '有 Free coupon 吗？',
              '무료 쿠폰이 있나요?',
            ),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _couponController,
            enabled: !_redeemingCoupon,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _redeemCoupon(),
            decoration: InputDecoration(
              labelText: 'Free coupon',
              hintText: L10n.text(
                language,
                'Enter your code',
                'コードを入力',
                '输入优惠码',
                '코드를 입력하세요',
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _redeemingCoupon || _couponController.text.trim().isEmpty
                ? null
                : _redeemCoupon,
            child: _redeemingCoupon
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    L10n.text(
                      language,
                      'Apply coupon',
                      'クーポンを適用',
                      '使用优惠码',
                      '쿠폰 적용',
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _featureCards(ProFeature feature) => switch (feature) {
    ProFeature.health => const [
      _Feature(
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
      SizedBox(height: 12),
      _Feature(
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
      SizedBox(height: 12),
      _Feature(
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
    ],
    ProFeature.multiPet => const [
      _Feature(
        icon: Icons.pets_rounded,
        color: PawColors.blue,
        title: 'Second pet and beyond',
        titleJa: '2匹目以降',
        titleZh: '第 2 只及更多宠物',
        titleKo: '두 번째 이후 반려동물',
        detail: 'The first pet stays free. Add more for ¥300/month.',
        detailJa: '1匹目は無料のまま。月額300円で追加できます。',
        detailZh: '第 1 只永久免费；每月 ¥300 可添加更多宠物。',
        detailKo: '첫 반려동물은 무료이며 월 ¥300으로 더 추가할 수 있습니다.',
      ),
    ],
    ProFeature.ai => const [
      _Feature(
        icon: Icons.auto_awesome_rounded,
        color: PawColors.purple,
        title: 'AI care entry',
        titleJa: 'AIでケア入力',
        titleZh: 'AI 护理录入',
        titleKo: 'AI 케어 입력',
        detail: 'Describe the routine in a sentence and get the schedule.',
        detailJa: '一文で説明すれば、予定ができあがります。',
        detailZh: '一句话描述，自动生成护理日程。',
        detailKo: '한 문장으로 설명하면 돌봄 일정이 만들어집니다.',
      ),
    ],
  };

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
          monthlyOnly: widget.feature != ProFeature.health,
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
    final couponActive = context.watch<ProAccess>().isFreeCouponActive;
    final isUnlocked = couponActive || widget.feature.isUnlocked(purchases);
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
          CircleAvatar(
            radius: 32,
            backgroundColor: const Color(0x33FFFFFF),
            child: Icon(widget.feature.icon, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 12),
          if (widget.reason != null && !isUnlocked) ...[
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
            couponActive
                ? L10n.text(
                    language,
                    'All features unlocked with Free coupon',
                    '無料クーポンですべての機能を利用できます',
                    'Free coupon 已解锁全部功能',
                    '무료 쿠폰으로 모든 기능을 사용할 수 있습니다',
                  )
                : isUnlocked
                ? L10n.text(
                    language,
                    '${widget.feature.title(language)} is active. Thank you!',
                    '${widget.feature.title(language)}をご利用中です。',
                    '已订阅${widget.feature.title(language)}，感谢支持！',
                    '${widget.feature.title(language)} 기능을 이용 중입니다.',
                  )
                : widget.feature.title(language),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.feature.summary(language),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xEFFFFFFF), height: 1.35),
          ),
          if (!isUnlocked) ...[
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
                    ? widget.feature.cta(language)
                    : '${widget.feature.cta(language)} · '
                          '${selected.storeProduct.priceString}',
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
    this.monthlyOnly = false,
    this.onTap,
  });

  final Package package;
  final bool highlighted;
  final bool monthlyOnly;
  final VoidCallback? onTap;

  String _title(AppLanguage language) => monthlyOnly
      ? L10n.text(language, 'Monthly', '月額', '按月', '월간')
      : switch (package.packageType) {
          PackageType.annual => L10n.text(language, 'Yearly', '年額', '按年', '연간'),
          PackageType.monthly => L10n.text(
            language,
            'Monthly',
            '月額',
            '按月',
            '월간',
          ),
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
          PackageType.lifetime => L10n.text(
            language,
            'Lifetime',
            '買い切り',
            '终身',
            '평생',
          ),
          _ => package.storeProduct.title,
        };

  String _period(AppLanguage language) => monthlyOnly
      ? L10n.text(language, ' / month', ' / 月', ' / 月', ' / 월')
      : switch (package.packageType) {
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
