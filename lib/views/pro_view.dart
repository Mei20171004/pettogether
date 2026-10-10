import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/app_config.dart';
import '../l10n/l10n.dart';
import '../store/purchase_store.dart';
import '../store/pro_access.dart';
import '../theme/app_theme.dart';
import 'legal_page.dart';
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
    final productId = package.storeProduct.identifier.split(':').first;
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
      'Your first pet is free. Subscribe to add a second pet and beyond.',
      '1匹目は無料。複数ペットプランで2匹目以降を追加できます。',
      '第 1 只宠物免费；订阅多宠物功能可添加第 2 只及更多宠物。',
      '첫 반려동물은 무료이며, 구독으로 두 번째부터 추가할 수 있습니다.',
    ),
    ProFeature.ai => L10n.text(
      language,
      'Turn a sentence into a care schedule.',
      '文章からケア予定を作成します。',
      '用一句话生成宠物护理日程。',
      '한 문장을 돌봄 일정으로 바꿉니다.',
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
  String? _purchaseMessage;
  String? _buyingProduct;
  bool _accessPending = false;
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

  Future<void> _buy(Package package) async {
    final purchases = context.read<PurchaseStore>();
    if (purchases.isPurchasing) return;
    final language = context.read<AppLanguageStore>().language;
    setState(() {
      _purchaseMessage = null;
      _buyingProduct = package.storeProduct.identifier;
    });
    try {
      final unlocked = await purchases.purchase(
        package,
        entitlementId: widget.feature.entitlementId,
      );
      if (!mounted) return;
      if (unlocked) {
        unawaited(context.read<ProAccess>().syncUserInfoAfterPurchase());
      }
      setState(
        () => _purchaseMessage = unlocked
            ? L10n.text(
                language,
                '${widget.feature.title(language)} unlocked.',
                '${widget.feature.title(language)}を利用できます。',
                '已解锁${widget.feature.title(language)}。',
                '${widget.feature.title(language)} 기능이 활성화되었습니다.',
              )
            : L10n.text(
                language,
                'Purchase cancelled. You can try again.',
                '購入をキャンセルしました。再試行できます。',
                '已取消购买，可以重新订阅。',
                '구매를 취소했습니다. 다시 시도할 수 있습니다.',
              ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _purchaseMessage = _purchaseFailure(language, error);
        _accessPending =
            error is PurchaseAccessPending ||
            error is PlatformException &&
                PurchasesErrorHelper.getErrorCode(error) ==
                    PurchasesErrorCode.paymentPendingError;
      });
    } finally {
      if (mounted) setState(() => _buyingProduct = null);
    }
  }

  String _purchaseFailure(AppLanguage language, Object error) {
    if (error is PurchaseAccessPending) {
      return L10n.text(
        language,
        'Purchase received, but access is still syncing. Use Restore purchases; do not buy again.',
        '購入を受け付けましたが、利用権を同期中です。再購入せず「購入を復元」をお試しください。',
        '购买已完成，权限仍在同步。请点击“恢复购买”，不要重复购买。',
        '구매가 완료되었지만 권한을 동기화 중입니다. 다시 구매하지 말고 구매 복원을 이용해 주세요.',
      );
    }
    final code = error is PlatformException
        ? PurchasesErrorHelper.getErrorCode(error)
        : null;
    if (code == PurchasesErrorCode.paymentPendingError) {
      return L10n.text(
        language,
        'Payment is awaiting approval. Do not buy again.',
        'お支払いは承認待ちです。再購入しないでください。',
        '付款正在等待批准，请勿重复购买。',
        '결제 승인 대기 중입니다. 다시 구매하지 마세요.',
      );
    }
    if (code == PurchasesErrorCode.networkError ||
        code == PurchasesErrorCode.offlineConnectionError) {
      return L10n.text(
        language,
        'Could not connect to the store. Check your connection and try again.',
        'ストアに接続できません。通信状況を確認して再試行してください。',
        '无法连接商店，请检查网络后重试。',
        '스토어에 연결할 수 없습니다. 연결을 확인하고 다시 시도하세요.',
      );
    }
    if (code == PurchasesErrorCode.purchaseNotAllowedError ||
        code == PurchasesErrorCode.insufficientPermissionsError) {
      return L10n.text(
        language,
        'Purchases are restricted on this device or store account. Check your purchase settings.',
        '端末またはストアアカウントの購入が制限されています。購入設定を確認してください。',
        '此设备或商店账号限制了购买，请检查购买设置。',
        '기기 또는 스토어 계정에서 구매가 제한됩니다. 구매 설정을 확인하세요.',
      );
    }
    return L10n.text(
      language,
      'The purchase could not be completed. Try again or use Restore purchases if you were charged.',
      '購入を完了できませんでした。再試行するか、請求済みの場合は「購入を復元」をお試しください。',
      '未能完成购买。请重试；若已扣款，请使用“恢复购买”。',
      '구매를 완료할 수 없습니다. 다시 시도하거나 결제되었다면 구매 복원을 이용하세요.',
    );
  }

  Future<void> _restore() async {
    final purchases = context.read<PurchaseStore>();
    final language = context.read<AppLanguageStore>().language;
    if (purchases.isPurchasing) return;
    setState(() => _purchaseMessage = null);
    try {
      final restored = await purchases.restore(
        entitlementId: widget.feature.entitlementId,
      );
      if (!mounted) return;
      if (restored) {
        _accessPending = false;
        unawaited(context.read<ProAccess>().syncUserInfoAfterPurchase());
      }
      setState(
        () => _purchaseMessage = restored
            ? L10n.text(
                language,
                '${widget.feature.title(language)} restored.',
                '${widget.feature.title(language)}を復元しました。',
                '已恢复${widget.feature.title(language)}。',
                '${widget.feature.title(language)} 기능을 복원했습니다.',
              )
            : _accessPending
            ? _purchaseFailure(language, const PurchaseAccessPending())
            : L10n.text(
                language,
                'No active purchase found for this feature.',
                'この機能の有効な購入が見つかりませんでした。',
                '未找到此功能的有效订阅。',
                '이 기능의 활성 구매가 없습니다.',
              ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _purchaseMessage = _purchaseFailure(language, error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    final purchases = context.watch<PurchaseStore>();
    final access = context.watch<ProAccess>();
    final packages = purchases.packages.where(widget.feature.matches).toList();
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
                _heroCard(context, language, purchases),
                const SizedBox(height: 22),
                if (!access.isFreeCouponActive &&
                    !widget.feature.isUnlocked(purchases))
                  ..._plans(language, purchases, packages),
                if (_purchaseMessage != null) ...[
                  const SizedBox(height: 12),
                  _notice(_purchaseMessage!),
                ],
                const SizedBox(height: 16),
                if (purchases.isAvailable)
                  Center(
                    child: TextButton(
                      onPressed: purchases.isPurchasing ? null : _restore,
                      child: Text(
                        L10n.text(
                          language,
                          purchases.isRestoring
                              ? 'Restoring…'
                              : 'Restore purchases',
                          purchases.isRestoring ? '復元中…' : '購入を復元',
                          purchases.isRestoring ? '正在恢复…' : '恢复购买',
                          purchases.isRestoring ? '복원 중…' : '구매 복원',
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (AppConfig.customCouponEnabled) ...[
                  _couponCard(language, access),
                  const SizedBox(height: 22),
                ],
                PetSectionTitle(
                  title: L10n.text(
                    language,
                    'What this unlocks',
                    '利用できる機能',
                    '解锁内容',
                    '잠금 해제 기능',
                  ),
                  detail: widget.feature.title(language),
                ),
                const SizedBox(height: 12),
                ..._featureCards(widget.feature),
                if (widget.feature != ProFeature.health) ...[
                  const SizedBox(height: 12),
                  Text(
                    L10n.text(
                      language,
                      'AI care entry and additional pets are separate subscriptions.',
                      'AIケア入力と複数ペットは別々のサブスクリプションです。',
                      'AI 护理录入和多宠物功能为独立订阅。',
                      'AI 케어 입력과 여러 반려동물 기능은 별도 구독입니다.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: PawColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  L10n.text(
                    language,
                    'Payment is charged to your store account. Subscriptions renew automatically until cancelled. Manage or cancel in your store subscription settings.',
                    'お支払いはストアアカウントに請求されます。解約するまで自動更新されます。管理・解約はストアのサブスクリプション設定から行えます。',
                    '费用将从商店账号扣除。订阅会自动续费，直到你取消。请在商店的订阅设置中管理或取消。',
                    '결제는 스토어 계정에 청구됩니다. 취소할 때까지 자동 갱신되며 스토어 구독 설정에서 관리하거나 취소할 수 있습니다.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PawColors.muted, fontSize: 12),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _openLegalPage(
                        L10n.text(
                          language,
                          'Privacy Policy',
                          'プライバシーポリシー',
                          '隐私政策',
                          '개인정보 처리방침',
                        ),
                        'https://pettogether-76452.web.app/privacy-policy.html',
                      ),
                      child: Text(
                        L10n.text(
                          language,
                          'Privacy Policy',
                          'プライバシーポリシー',
                          '隐私政策',
                          '개인정보 처리방침',
                        ),
                      ),
                    ),
                    if (defaultTargetPlatform == TargetPlatform.iOS)
                      TextButton(
                        onPressed: () => _openLegalPage(
                          L10n.text(
                            language,
                            'Terms of Use',
                            '利用規約',
                            '使用条款',
                            '이용 약관',
                          ),
                          'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
                        ),
                        child: Text(
                          L10n.text(
                            language,
                            'Terms of Use',
                            '利用規約',
                            '使用条款',
                            '이용 약관',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openLegalPage(String title, String url) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LegalPage(title: title, url: Uri.parse(url)),
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
        detail: 'The first pet stays free. Subscribe to add more.',
        detailJa: '1匹目は無料のまま。複数ペットプランで追加できます。',
        detailZh: '第 1 只永久免费；订阅多宠物功能可添加更多宠物。',
        detailKo: '첫 반려동물은 무료이며 구독으로 더 추가할 수 있습니다.',
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
  ) {
    if (purchases.isInitializing ||
        purchases.isLoadingOfferings && packages.isEmpty) {
      return [
        const Center(child: CircularProgressIndicator()),
        _notice(
          L10n.text(
            language,
            'Loading subscription prices…',
            'サブスクリプションの価格を読み込み中…',
            '正在加载订阅价格…',
            '구독 가격을 불러오는 중…',
          ),
        ),
      ];
    }
    if (!purchases.isAvailable) {
      return [
        _notice(
          L10n.text(
            language,
            'Purchases could not be initialized. Retry or update the app.',
            '購入を準備できませんでした。再試行するかアプリを更新してください。',
            '未能准备购买，请重试或更新应用。',
            '구매를 준비할 수 없습니다. 다시 시도하거나 앱을 업데이트하세요.',
          ),
        ),
        Center(
          child: OutlinedButton(
            onPressed: purchases.initialize,
            child: Text(L10n.text(language, 'Retry', '再試行', '重试', '다시 시도')),
          ),
        ),
      ];
    }
    if (packages.isEmpty) {
      return [
        _notice(
          L10n.text(
            language,
            'Subscription prices are unavailable. Please retry.',
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
          highlighted: packages[i].packageType == PackageType.annual,
          isPurchasing: _buyingProduct == packages[i].storeProduct.identifier,
          monthlyOnly: widget.feature != ProFeature.health,
          onTap: purchases.isPurchasing || _accessPending
              ? null
              : () => _buy(packages[i]),
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
  ) {
    final couponActive = context.watch<ProAccess>().isFreeCouponActive;
    final isUnlocked = couponActive || widget.feature.isUnlocked(purchases);
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
    required this.isPurchasing,
    this.monthlyOnly = false,
    this.onTap,
  });

  final Package package;
  final bool highlighted;
  final bool isPurchasing;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _title(language),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: PawColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _detail(language),
              style: const TextStyle(color: PawColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: ValueKey('subscribe_${package.storeProduct.identifier}'),
              onPressed: onTap,
              icon: isPurchasing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_open_rounded),
              label: Text(
                isPurchasing
                    ? L10n.text(
                        language,
                        'Waiting for the store…',
                        'ストアの確認待ち…',
                        '正在等待商店确认…',
                        '스토어 확인 대기 중…',
                      )
                    : '${L10n.text(language, 'Subscribe', '購読する', '订阅', '구독하기')} · '
                          '${package.storeProduct.priceString}${_period(language)}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
