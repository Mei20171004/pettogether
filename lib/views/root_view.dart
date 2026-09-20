import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../store/care_store.dart';
import '../store/pro_access.dart';
import '../theme/app_theme.dart';
import 'ai_input_dialog.dart';
import 'ai_result_view.dart';
import 'health/health_view.dart';
import 'create_join_view.dart';
import 'manage_household_view.dart';
import 'pro_view.dart';
import 'schedule_view.dart';
import 'today_view.dart';
import 'widgets/common.dart';

/// Root screen: loading, welcome, or the four-tab household experience.
class RootView extends StatefulWidget {
  const RootView({super.key});

  @override
  State<RootView> createState() => _RootViewState();
}

class _RootViewState extends State<RootView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CareStore>().restoreSession();
    });
  }

  void _showError(BuildContext context, CareStore store) {
    final message = store.errorMessage;
    if (message == null) return;
    store.errorMessage = null;
    showDialog<void>(
      context: context,
      builder: (context) {
        final language = context.read<AppLanguageStore>().language;
        return AlertDialog(
          title: Text(
            L10n.text(
              language,
              'Something went wrong',
              'エラーが発生しました',
              '出了点问题',
              '문제가 발생했습니다',
            ),
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CareStore>(
      builder: (context, store, _) {
        // Present the error once per message.
        if (store.errorMessage != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showError(context, store),
          );
        }

        return Stack(
          children: [
            const PetScreenBackground(),
            if (store.isRestoringSession)
              const StartupBrandView()
            else if (store.household == null)
              const CreateJoinView()
            else
              const _HouseholdTabs(),
          ],
        );
      },
    );
  }
}

class StartupBrandView extends StatelessWidget {
  const StartupBrandView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x267D6BE8),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Image.asset(
                'assets/images/app_icon.png',
                key: const ValueKey('startup_brand_icon'),
                width: 104,
                height: 104,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'PetTogether',
            style: TextStyle(
              color: PawColors.ink,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HouseholdTabs extends StatefulWidget {
  const _HouseholdTabs();

  @override
  State<_HouseholdTabs> createState() => _HouseholdTabsState();
}

class _HouseholdTabsState extends State<_HouseholdTabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: IndexedStack(
        index: _index,
        children: const [
          TodayView(),
          ScheduleView(),
          HealthView(),
          ManageHouseholdView(),
        ],
      ),
      bottomNavigationBar: Stack(
        clipBehavior: Clip.none,
        children: [
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            backgroundColor: Colors.white,
            indicatorColor: PawColors.lavender,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.checklist),
                label: L10n.text(language, 'Today', '今日', '今天', '오늘'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.calendar_month),
                label: L10n.text(language, 'Calendar', 'カレンダー', '日历', '캘린더'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.favorite_border),
                label: L10n.text(language, 'Health', '健康', '健康', '건강'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.group),
                label: L10n.text(language, 'Family', '家族', '家庭', '가족'),
              ),
            ],
          ),
          Positioned(
            top: -28,
            left: 0,
            right: 0,
            child: Center(child: _aiButton(context)),
          ),
        ],
      ),
    );
  }

  Widget _aiButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _startAi(context),
        customBorder: const CircleBorder(),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [PawColors.purple, PawColors.blue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: PawColors.purple.withValues(alpha: 0.4),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  /// AI entry has its own subscription and a monthly fair-use ceiling. The
  /// check runs before the dialog opens so nobody types out a plan only to be
  /// told it costs money.
  Future<void> _startAi(BuildContext context) async {
    final access = context.read<ProAccess>();
    final language = context.read<AppLanguageStore>().language;
    if (!access.hasAi) {
      await showProPaywall(
        context,
        reason: L10n.text(
          language,
          'AI care entry requires the ¥300/month AI plan.',
          'AIケア入力には月額300円のAIプランが必要です。',
          '使用 AI 护理录入需要订阅每月 ¥300 的 AI 功能。',
          'AI 케어 입력에는 월 ¥300 AI 구독이 필요합니다.',
        ),
        feature: ProFeature.ai,
      );
      return;
    }
    if (!access.canUseAi) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.text(
              language,
              'The monthly AI usage limit has been reached. Please try again next month.',
              '今月のAI利用上限に達しました。来月もう一度お試しください。',
              '本月 AI 使用次数已达上限，请下个月再试。',
              '이번 달 AI 사용 한도에 도달했습니다. 다음 달에 다시 시도해 주세요.',
            ),
          ),
        ),
      );
      return;
    }
    await _showAiDialog(context);
  }

  Future<void> _showAiDialog(BuildContext context) async {
    final access = context.read<ProAccess>();
    final language = context.read<AppLanguageStore>().language;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AiInputDialog(
        language: language,
        aiParsesLeft: access.aiParsesLeft,
        aiParseLimit: access.aiParseLimit,
        showBalance: access.hasAi,
      ),
    );

    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final pets = context.read<CareStore>().household?.pets ?? const <Pet>[];
    try {
      final result = await AiService.instance.parseInstruction(trimmed, pets);
      // Count the parse only once the model actually answered, so a failed
      // call does not eat the user's quota.
      unawaited(access.recordAiParse());
      if (!context.mounted) return;
      Navigator.of(context).pop(); // close loading
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AiResultView(result: result),
        ),
      );
    } catch (error, stackTrace) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // close loading
      debugPrint('AI parse failed: $error\n$stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_aiFailureMessage(language, error))),
      );
    }
  }

  String _aiFailureMessage(AppLanguage language, Object error) {
    final kind = error is AiFailure ? error.kind : AiFailureKind.server;
    return switch (kind) {
      AiFailureKind.configuration => L10n.text(
        language,
        'AI setup is incomplete. Update the app, then contact support if it still fails.',
        'AIの設定が完了していません。アプリを更新し、解決しない場合はサポートへご連絡ください。',
        'AI 配置尚未完成。请先更新应用；若仍失败，请联系支持人员。',
        'AI 설정이 완료되지 않았습니다. 앱을 업데이트한 뒤 계속 실패하면 지원팀에 문의해 주세요.',
      ),
      AiFailureKind.network => L10n.text(
        language,
        'Could not reach AI. Check your connection and try again.',
        'AIに接続できませんでした。通信状況を確認してもう一度お試しください。',
        '无法连接 AI。请检查网络后重试。',
        'AI에 연결할 수 없습니다. 네트워크를 확인한 뒤 다시 시도해 주세요.',
      ),
      AiFailureKind.authorization => L10n.text(
        language,
        'This app build could not be verified for AI. Reopen or update the app, then try again.',
        'このアプリをAI用に確認できませんでした。アプリを再起動または更新して、もう一度お試しください。',
        '当前应用版本未能通过 AI 验证。请重启或更新应用后重试。',
        '이 앱 빌드의 AI 사용을 확인할 수 없습니다. 앱을 다시 열거나 업데이트한 뒤 시도해 주세요.',
      ),
      AiFailureKind.quota => L10n.text(
        language,
        'The AI usage limit has been reached. Please try again later.',
        'AIの利用上限に達しました。しばらくしてからもう一度お試しください。',
        'AI 使用量已达上限，请稍后重试。',
        'AI 사용 한도에 도달했습니다. 잠시 후 다시 시도해 주세요.',
      ),
      AiFailureKind.unsupportedRegion => L10n.text(
        language,
        'AI entry is not available in your region.',
        'お住まいの地域ではAI入力を利用できません。',
        '你所在的地区暂不支持 AI 录入。',
        '현재 지역에서는 AI 입력을 사용할 수 없습니다.',
      ),
      AiFailureKind.invalidResponse => L10n.text(
        language,
        'AI returned an unusable result. Try again or describe the plan another way.',
        'AIから利用できる結果が返りませんでした。再試行するか、別の表現で入力してください。',
        'AI 返回的结果无法使用。请重试，或换一种方式描述计划。',
        'AI가 사용할 수 없는 결과를 반환했습니다. 다시 시도하거나 다른 방식으로 설명해 주세요.',
      ),
      AiFailureKind.server => L10n.text(
        language,
        'AI is temporarily unavailable. Please try again later.',
        'AIを一時的に利用できません。しばらくしてからもう一度お試しください。',
        'AI 暂时不可用，请稍后重试。',
        'AI를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.',
      ),
    };
  }
}
