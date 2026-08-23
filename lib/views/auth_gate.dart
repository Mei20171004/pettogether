import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import 'login_view.dart';
import 'root_view.dart';

/// Decides between the login screen and the household experience based on the
/// Firebase Auth state. When Firebase isn't initialized (e.g. the widget test)
/// or the app is configured to run offline, it skips login entirely.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty || !AppConfig.useFirebase) {
      return const RootView();
    }
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }
        if (snapshot.data == null) {
          return const LoginView();
        }
        return const RootView();
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
