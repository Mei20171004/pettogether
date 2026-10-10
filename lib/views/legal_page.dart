import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/l10n.dart';

class LegalPage extends StatefulWidget {
  const LegalPage({super.key, required this.title, required this.url});

  final String title;
  final Uri url;

  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage> {
  late final WebViewController _controller;
  Uri? _currentPage;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_failed) setState(() => _failed = false);
    try {
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => _currentPage = Uri.tryParse(url),
          onNavigationRequest: (request) =>
              Uri.tryParse(request.url)?.scheme == 'https'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onHttpError: (error) {
            final failedPage = error.request?.uri ?? error.response?.uri;
            if (failedPage != null && failedPage == _currentPage && mounted) {
              debugPrint(
                'Legal page HTTP error ${error.response?.statusCode}: $_currentPage',
              );
              setState(() => _failed = true);
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              debugPrint(
                'Legal page resource error ${error.errorCode}: ${error.description}',
              );
              setState(() => _failed = true);
            }
          },
        ),
      );
      await _controller.loadRequest(widget.url);
    } catch (error) {
      debugPrint('Legal page load failed: $error');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.text(
                      language,
                      'Page could not be loaded.',
                      'ページを読み込めませんでした。',
                      '页面加载失败。',
                      '페이지를 불러올 수 없습니다.',
                    ),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: Text(
                      L10n.text(language, 'Retry', '再試行', '重试', '다시 시도'),
                    ),
                  ),
                ],
              ),
            )
          : WebViewWidget(controller: _controller),
    );
  }
}
