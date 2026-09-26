import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../l10n/l10n.dart';
import '../../services/web_auth_bridge_policy.dart';
import '../../store/pro_access.dart';
import '../../theme/app_theme.dart';

class ProMenuWebView extends StatefulWidget {
  const ProMenuWebView({
    super.key,
    required this.title,
    required this.url,
    required this.householdId,
    required this.petId,
  });

  final String title;
  final Uri url;
  final String householdId;
  final String petId;

  @override
  State<ProMenuWebView> createState() => _ProMenuWebViewState();
}

class _ProMenuWebViewState extends State<ProMenuWebView> {
  late final WebViewController _controller;
  late final String? _openedUid;
  StreamSubscription<User?>? _authSubscription;
  ProAccess? _access;
  Uri? _currentPage;
  int _progress = 0;
  bool _failed = false;
  bool _exchangeInFlight = false;
  bool _readyWhileBusy = false;
  int _pageGeneration = 0;
  int _providedGeneration = -1;

  @override
  void initState() {
    super.initState();
    _openedUid = FirebaseAuth.instance.currentUser?.uid;
    _controller = WebViewController();
    if (_openedUid == null) {
      _failed = true;
      return;
    }
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid != _openedUid && mounted) _returnHome();
    });
    unawaited(_configureAndLoad());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final access = context.read<ProAccess>();
    if (_access != access) {
      _access?.removeListener(_onAccessChanged);
      _access = access;
      access.addListener(_onAccessChanged);
    }
  }

  void _onAccessChanged() {
    if (_access?.isPro != false || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _access?.isPro == false) _returnHome();
    });
  }

  void _returnHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _configureAndLoad() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setBackgroundColor(Colors.white);
      await _controller.addJavaScriptChannel(
        'PetTogetherBridge',
        onMessageReceived: (message) {
          if (message.message == 'auth-failed') {
            _providedGeneration = -1;
            return;
          }
          if (message.message != 'ready') return;
          if (_exchangeInFlight) {
            _readyWhileBusy = true;
          } else {
            unawaited(_provideWebSignIn());
          }
        },
      );
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _currentPage = Uri.tryParse(url);
              _pageGeneration += 1;
              _progress = 0;
              _failed = false;
            });
          },
          onHttpError: (error) {
            final failedPage = error.request?.uri ?? error.response?.uri;
            if (failedPage != null && failedPage == _currentPage && mounted) {
              setState(() => _failed = true);
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _failed = true);
            }
          },
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final destination = Uri.tryParse(request.url);
            return destination?.scheme == 'https' &&
                    destination?.origin == widget.url.origin
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
      await _controller.loadRequest(widget.url);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _provideWebSignIn() async {
    if (_exchangeInFlight ||
        _providedGeneration == _pageGeneration ||
        !mounted ||
        !isTrustedWebAuthPage(widget.url, _currentPage) ||
        _openedUid == null ||
        FirebaseAuth.instance.currentUser?.uid != _openedUid ||
        _access?.isPro != true) {
      return;
    }
    _exchangeInFlight = true;
    final page = _currentPage;
    final generation = _pageGeneration;
    try {
      // Callable automatically sends and verifies the current user's ID token.
      final response = await FirebaseFunctions.instanceFor(
        region: 'asia-northeast1',
      ).httpsCallable('issueWebSignInToken').call<Map<String, dynamic>>();
      final token = response.data['customToken'];
      if (token is! String || token.isEmpty) throw StateError('Empty token');
      if (!mounted ||
          _pageGeneration != generation ||
          _currentPage != page ||
          FirebaseAuth.instance.currentUser?.uid != _openedUid ||
          _access?.isPro != true) {
        return;
      }
      final payload = jsonEncode({
        'token': token,
        'uid': _openedUid,
        'householdId': widget.householdId,
        'petId': widget.petId,
        'language': context.read<AppLanguageStore>().language.rawValue,
      });
      await _controller.runJavaScript(
        'window.pettogetherReceiveAuth?.($payload);',
      );
      _providedGeneration = generation;
    } catch (_) {
      if (mounted && _currentPage == page) {
        try {
          await _controller.runJavaScript('window.pettogetherAuthError?.();');
        } catch (_) {
          // The page may have closed while the callable was in flight.
        }
      }
    } finally {
      _exchangeInFlight = false;
      if (_readyWhileBusy) {
        _readyWhileBusy = false;
        unawaited(_provideWebSignIn());
      }
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _access?.removeListener(_onAccessChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          tooltip: L10n.text(language, 'Home', 'ホーム', '返回主页', '홈'),
          onPressed: _returnHome,
        ),
        title: Text(widget.title),
        bottom: _progress < 100 && !_failed
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.text(
                      language,
                      'Page could not be loaded',
                      'ページを読み込めませんでした',
                      '页面加载失败',
                      '페이지를 불러올 수 없습니다',
                    ),
                    style: const TextStyle(color: PawColors.muted),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _failed = false);
                      unawaited(_controller.loadRequest(widget.url));
                    },
                    icon: const Icon(Icons.refresh),
                    label: Text(
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
