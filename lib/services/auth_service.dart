import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper over Firebase Auth for email/password, Google, and Apple.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  bool get deletionNeedsPassword {
    try {
      return currentUser?.providerData.any(
            (info) => info.providerId == 'password',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<User?> signInWithEmail(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return result.user;
  }

  Future<User?> registerWithEmail(String email, String password) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return result.user;
  }

  bool _googleInitialized = false;

  Future<GoogleSignIn> _googleSignIn() async {
    final google = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await google.initialize();
      _googleInitialized = true;
    }
    return google;
  }

  Future<User?> signInWithGoogle() async {
    final google = await _googleSignIn();
    final GoogleSignInAccount googleUser;
    try {
      googleUser = await google.authenticate();
    } on GoogleSignInException catch (e) {
      // User dismissed the sign-in sheet.
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
    final credential = GoogleAuthProvider.credential(
      idToken: googleUser.authentication.idToken,
    );
    final result = await _auth.signInWithCredential(credential);
    return result.user;
  }

  Future<User?> signInWithApple() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    final result = await _auth.signInWithProvider(provider);
    return result.user;
  }

  Future<void> deleteAccount({String? newOwnerUid, String? password}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Sign in before deleting your account.',
      );
    }

    final providers = user.providerData.map((info) => info.providerId).toSet();
    if (providers.contains('apple.com')) {
      final apple = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      final credential = await user.reauthenticateWithProvider(apple);
      final authorizationCode =
          credential.additionalUserInfo?.authorizationCode;
      if (authorizationCode == null || authorizationCode.isEmpty) {
        throw FirebaseAuthException(
          code: 'apple-token-revocation-failed',
          message: 'Apple did not return an authorization code.',
        );
      }
      await _auth.revokeTokenWithAuthorizationCode(authorizationCode);
    } else if (providers.contains('google.com')) {
      final google = await _googleSignIn();
      final googleUser = await google.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: googleUser.authentication.idToken,
      );
      await user.reauthenticateWithCredential(credential);
    } else if (providers.contains('password')) {
      final email = user.email;
      if (email == null || password == null || password.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-password',
          message: 'Enter your password to delete this account.',
        );
      }
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    }

    await FirebaseFunctions.instanceFor(region: 'asia-northeast1')
        .httpsCallable('deleteAccount')
        .call<Map<String, dynamic>>({
          if (newOwnerUid != null) 'newOwnerUid': newOwnerUid,
        });

    try {
      final google = await _googleSignIn();
      await google.signOut();
    } catch (_) {
      // The backend has already deleted the account. Local Firebase sign-out
      // below is sufficient when Google was never used or is unavailable.
    }
    await _auth.signOut();
  }

  Future<void> signOut() async {
    final google = await _googleSignIn();
    await google.signOut();
    await _auth.signOut();
  }
}
