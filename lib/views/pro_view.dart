import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

/// Static marketing page for copaw Pro (port of the Kate build). Purchases are
/// intentionally not connected yet — the CTA shows a "Coming soon" snackbar.
class ProView extends StatelessWidget {
  const ProView({super.key});

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(L10n.text(language, 'copaw Pro', 'copaw Pro', 'copaw Pro',
            'copaw Pro')),
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _heroCard(context, language),
                const SizedBox(height: 22),
                PetSectionTitle(
                  title: L10n.text(language, 'Made for shared care',
                      'シェアケアのために', '为共同照护而生', '함께하는 케어를 위해'),
                  detail: L10n.text(language, 'Pro preview', 'Pro プレビュー',
                      'Pro 预览', 'Pro 미리보기'),
                ),
                const SizedBox(height: 12),
                const _Feature(
                  icon: Icons.notifications_active_rounded,
                  color: PawColors.rose,
                  title: 'Smart reminders',
                  titleJa: 'スマートリマインダー',
                  titleZh: '智能提醒',
                  titleKo: '스마트 알림',
                  detail: 'Nudge the right person at the right time.',
                  detailJa: '適切なタイミングで適切な人に通知。',
                  detailZh: '在合适的时间提醒合适的人。',
                  detailKo: '적절한 시간에 적절한 사람에게 알립니다.',
                ),
                const SizedBox(height: 12),
                const _Feature(
                  icon: Icons.insights_rounded,
                  color: PawColors.blue,
                  title: 'Care insights',
                  titleJa: 'ケアの洞察',
                  titleZh: '护理洞察',
                  titleKo: '케어 인사이트',
                  detail: 'Spot routines that keep your pet happiest.',
                  detailJa: 'ペットが最も幸せになる習慣を見つけます。',
                  detailZh: '发现让宠物最开心的日常习惯。',
                  detailKo: '반려동물이 가장 행복해하는 습관을 찾아냅니다.',
                ),
                const SizedBox(height: 12),
                const _Feature(
                  icon: Icons.groups_rounded,
                  color: PawColors.green,
                  title: 'More caregivers',
                  titleJa: 'もっと多くのケアギバー',
                  titleZh: '更多照护者',
                  titleKo: '더 많은 케어기버',
                  detail: 'Keep the whole pet village in the loop.',
                  detailJa: 'ペットの村全体をループに。',
                  detailZh: '让整个宠物圈都参与进来。',
                  detailKo: '반려동물 공동체 모두가 함께합니다.',
                ),
                const SizedBox(height: 22),
                const _PriceCard(
                  title: 'Monthly',
                  titleJa: '月額',
                  titleZh: '按月',
                  titleKo: '월간',
                  price: '¥480',
                  detail: 'Cancel anytime',
                  detailJa: 'いつでも解約可能',
                  detailZh: '随时取消',
                  detailKo: '언제든 해지 가능',
                ),
                const SizedBox(height: 12),
                const _PriceCard(
                  title: 'Yearly',
                  titleJa: '年額',
                  titleZh: '按年',
                  titleKo: '연간',
                  price: '¥3,800',
                  detail: 'Save 34% · best value',
                  detailJa: '34% お得 · おすすめ',
                  detailZh: '节省 34% · 最划算',
                  detailKo: '34% 절약 · 최고의 가치',
                  highlighted: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCard(BuildContext context, AppLanguage language) {
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
            child: Icon(Icons.workspace_premium_rounded,
                color: Colors.white, size: 34),
          ),
          const SizedBox(height: 12),
          Text(
            L10n.text(language, 'More calm, more care.', 'もっと穏やかに、もっとケアを。',
                '更从容，更用心。', '더 차분하게, 더 세심하게.'),
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
              'copaw Pro gives every caregiver a clearer shared routine.',
              'copaw Pro はすべてのケアギバーに、より明確な共有ルーティンを。',
              'copaw Pro 让每位照护者的共享日常更清晰。',
              'copaw Pro는 모든 케어기버에게 더 명확한 공유 루틴을 제공합니다.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xEFFFFFFF), height: 1.35),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(L10n.text(
                  language,
                  'Purchases are not connected in this build yet.',
                  'このビルドでは購入はまだ接続されていません。',
                  '此版本尚未接入购买功能。',
                  '이 빌드에서는 구매 기능이 아직 연결되지 않았습니다.',
                )),
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: PawColors.purpleDark,
            ),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(L10n.text(
                language, 'Coming soon', '近日公開', '即将推出', '곧 출시')),
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
    required this.title,
    required this.titleJa,
    required this.titleZh,
    required this.titleKo,
    required this.price,
    required this.detail,
    required this.detailJa,
    required this.detailZh,
    required this.detailKo,
    this.highlighted = false,
  });

  final String title;
  final String titleJa;
  final String titleZh;
  final String titleKo;
  final String price;
  final String detail;
  final String detailJa;
  final String detailZh;
  final String detailKo;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted ? PawColors.lavender : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlighted ? PawColors.purple : PawColors.purple.withValues(alpha: 0.1),
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
                  L10n.text(language, title, titleJa, titleZh, titleKo),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: PawColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  L10n.text(language, detail, detailJa, detailZh, detailKo),
                  style: TextStyle(
                    color: highlighted ? PawColors.purpleDark : PawColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            price,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: PawColors.ink,
            ),
          ),
          Text(
            L10n.text(language, ' / year', ' / 年', ' / 年', ' / 년'),
            style: const TextStyle(color: PawColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
