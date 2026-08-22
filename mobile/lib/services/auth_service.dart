import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  const AuthSession({required this.name, required this.email});
  final String name;
  final String email;
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Offline authentication for the local-first RiseUP app.
///
/// It keeps a salted password hash and the active session only on this device.
/// Replace this boundary with a backend identity provider before offering
/// cross-device accounts or password recovery.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  static const _accountKey = 'riseup.auth.account.v1';
  static const _sessionKey = 'riseup.auth.session.v1';

  Future<AuthSession?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_sessionKey);
    final account = _account(prefs);
    if (email == null || account == null || account['email'] != email)
      return null;
    return AuthSession(name: account['name'] as String, email: email);
  }

  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final normalizedName = name.trim();
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedName.isEmpty) throw const AuthException('Enter your name.');
    if (!normalizedEmail.contains('@'))
      throw const AuthException('Enter a valid email address.');
    if (password.length < 6)
      throw const AuthException('Use at least 6 characters for your password.');

    final prefs = await SharedPreferences.getInstance();
    if (_account(prefs) != null) {
      throw const AuthException(
          'An account already exists on this device. Please sign in.');
    }
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final account = <String, dynamic>{
      'name': normalizedName,
      'email': normalizedEmail,
      'salt': base64UrlEncode(salt),
      'passwordHash': _hash(password, salt),
    };
    await prefs.setString(_accountKey, jsonEncode(account));
    await prefs.setString(_sessionKey, normalizedEmail);
    return AuthSession(name: normalizedName, email: normalizedEmail);
  }

  Future<AuthSession> signIn(
      {required String email, required String password}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final account = _account(prefs);
    if (account == null)
      throw const AuthException('Create an account on this device first.');
    if (account['email'] != normalizedEmail)
      throw const AuthException('Email or password is incorrect.');
    final salt = base64Url.decode(account['salt'] as String);
    if (account['passwordHash'] != _hash(password, salt)) {
      throw const AuthException('Email or password is incorrect.');
    }
    await prefs.setString(_sessionKey, normalizedEmail);
    return AuthSession(name: account['name'] as String, email: normalizedEmail);
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  Map<String, dynamic>? _account(SharedPreferences prefs) {
    final raw = prefs.getString(_accountKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String _hash(String password, List<int> salt) =>
      sha256.convert([...salt, ...utf8.encode(password)]).toString();
}
