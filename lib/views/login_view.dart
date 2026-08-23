import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

/// Email/password + Google sign-in, shown when no user is authenticated.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await AuthService.instance.registerWithEmail(email, password);
      } else {
        await AuthService.instance.signInWithEmail(email, password);
      }
      // The AuthGate observes the auth stream and navigates automatically.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _messageFor(e));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _messageFor(e));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found for this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'email-already-in-use':
        return 'An account already exists for this email.';
      default:
        return e.message ?? 'Sign-in failed.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: PawColors.purple.withValues(alpha: 0.16),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.pets,
                            size: 34, color: PawColors.purple),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'pettogetter',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                            color: PawColors.ink,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L10n.text(
                        language,
                        _register ? 'Create your account' : 'Welcome back',
                        _register ? 'アカウントを作成' : 'おかえりなさい',
                        _register ? '创建你的账户' : '欢迎回来',
                        _register ? '계정 만들기' : '다시 오신 것을 환영합니다',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: PawColors.muted),
                    ),
                    const SizedBox(height: 28),
                    PetCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: petFieldDecoration(
                              hintText: L10n.text(language, 'Email', 'メール',
                                  '邮箱', '이메일'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            obscureText: true,
                            decoration: petFieldDecoration(
                              hintText: L10n.text(language, 'Password',
                                  'パスワード', '密码', '비밀번호'),
                            ),
                            onSubmitted: (_) => _submitEmail(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: pawPrimaryButtonStyle(),
                            onPressed: _busy ? null : _submitEmail,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(L10n.text(
                                    language,
                                    _register ? 'Create account' : 'Sign in',
                                    _register ? 'アカウント作成' : 'ログイン',
                                    _register ? '创建账户' : '登录',
                                    _register ? '계정 만들기' : '로그인',
                                  )),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: PawColors.ink,
                              minimumSize: const Size(double.infinity, 52),
                              side: BorderSide(
                                  color: PawColors.purple.withValues(alpha: 0.3)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18)),
                            ),
                            onPressed: _busy ? null : _submitGoogle,
                            icon: const Icon(Icons.g_mobiledata, size: 24),
                            label: Text(L10n.text(
                              language,
                              'Continue with Google',
                              'Googleで続ける',
                              '使用 Google 继续',
                              'Google로 계속하기',
                            )),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _register = !_register;
                                      _error = null;
                                    }),
                            child: Text(L10n.text(
                              language,
                              _register
                                  ? 'Already have an account? Sign in'
                                  : 'No account? Create one',
                              _register
                                  ? 'すでにアカウントをお持ちですか？ログイン'
                                  : 'アカウントがありませんか？作成',
                              _register ? '已有账户？登录' : '没有账户？创建一个',
                              _register ? '이미 계정이 있나요? 로그인' : '계정이 없나요? 만들기',
                            )),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
