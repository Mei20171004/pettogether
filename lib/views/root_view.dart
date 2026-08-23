import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import 'activity_view.dart';
import 'ai_result_view.dart';
import 'create_join_view.dart';
import 'manage_household_view.dart';
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
          title: Text(L10n.text(language, 'Something went wrong',
              'エラーが発生しました', '出了点问题', '문제가 발생했습니다')),
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
              const _LoadingView()
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

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: PawColors.purple.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.pets, size: 30, color: PawColors.purple),
          ),
          const SizedBox(height: 16),
          const Text(
            'Loading your household…',
            style: TextStyle(color: PawColors.muted),
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
          ActivityView(),
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
                icon: const Icon(Icons.history),
                label: L10n.text(language, 'Activity', 'アクティビティ', '活动', '활동'),
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
        onTap: () => _showAiDialog(context),
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

  Future<void> _showAiDialog(BuildContext context) async {
    final language = context.read<AppLanguageStore>().language;
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.text(language, 'AI assistant', 'AIアシスタント', 'AI 助手',
            'AI 어시스턴트')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          minLines: 4,
          decoration: petFieldDecoration(
            hintText: L10n.text(
              language,
              'Describe your pet care plan…',
              'ペットのケアを入力…',
              '输入宠物护理计划…',
              '반려동물 케어 계획을 입력…',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
                L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(L10n.text(
                language, 'Parse', '解析', '解析', '분석')),
          ),
        ],
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
      if (!context.mounted) return;
      Navigator.of(context).pop(); // close loading
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AiResultView(result: result),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${L10n.text(language, 'Failed to parse', '解析に失敗', '解析失败', '분석 실패')}: $error')),
      );
    }
  }
}
