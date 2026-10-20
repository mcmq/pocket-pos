import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

/// Thin wrapper over Firebase Auth (email + password). The session is
/// cached by Firebase, so the app stays signed in while offline.
class AuthService {
  AuthService(this._auth);

  /// Null when Firebase isn't configured.
  final FirebaseAuth? _auth;

  bool get available => _auth != null;

  User? get currentUser => _auth?.currentUser;

  Stream<User?> authStateChanges() => _auth?.authStateChanges() ?? Stream.value(null);

  Future<User> signIn(String email, String password) async {
    final cred = await _require.signInWithEmailAndPassword(email: email.trim(), password: password);
    return cred.user!;
  }

  Future<User> signUp(String email, String password) async {
    final cred =
        await _require.createUserWithEmailAndPassword(email: email.trim(), password: password);
    return cred.user!;
  }

  Future<void> sendPasswordReset(String email) =>
      _require.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() async => _auth?.signOut();

  FirebaseAuth get _require {
    final auth = _auth;
    if (auth == null) {
      throw StateError('Cloud sync is not configured (see docs/setup.md).');
    }
    return auth;
  }

  /// Human-readable message for an auth error.
  static String describe(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-email' => 'That email address looks invalid.',
        'user-disabled' => 'This account has been disabled.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'Email or password is incorrect.',
        'email-already-in-use' => 'An account already exists for that email.',
        'weak-password' => 'Use a password with at least 6 characters.',
        'network-request-failed' => 'No internet connection. Try again when online.',
        'too-many-requests' => 'Too many attempts. Wait a moment and try again.',
        _ => error.message ?? 'Sign-in failed (${error.code}).',
      };
    }
    return error.toString().replaceFirst('Bad state: ', '');
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  final ready = ref.watch(firebaseReadyProvider);
  return AuthService(ready ? FirebaseAuth.instance : null);
});

final authUserProvider = StreamProvider<User?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);
