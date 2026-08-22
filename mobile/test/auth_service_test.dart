import 'package:flutter_test/flutter_test.dart';
import 'package:riseup/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('registers, restores, signs out, and signs in a local account', () async {
    final registered = await AuthService.instance.register(
      name: 'Aisha Khan',
      email: 'AISHA@example.com ',
      password: 'secure-pass',
    );
    expect(registered.email, 'aisha@example.com');

    final restored = await AuthService.instance.restoreSession();
    expect(restored?.name, 'Aisha Khan');

    await AuthService.instance.signOut();
    expect(await AuthService.instance.restoreSession(), isNull);

    final signedIn = await AuthService.instance.signIn(
      email: 'aisha@example.com',
      password: 'secure-pass',
    );
    expect(signedIn.name, 'Aisha Khan');
  });

  test('rejects an incorrect password', () async {
    await AuthService.instance.register(
      name: 'Aisha Khan',
      email: 'aisha@example.com',
      password: 'secure-pass',
    );

    expect(
      () => AuthService.instance.signIn(
        email: 'aisha@example.com',
        password: 'not-the-password',
      ),
      throwsA(isA<AuthException>()),
    );
  });
}