import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper over Firebase Auth, supporting email/password and Google.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

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

  Future<void> signOut() async {
    final google = await _googleSignIn();
    await google.signOut();
    await _auth.signOut();
  }
}
