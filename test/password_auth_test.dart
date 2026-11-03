import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_first_app/services/password_auth_service.dart';

void main() {
  test(
    'missing account invites signup and wrong credentials stay privacy safe',
    () {
      expect(
        PasswordAuthService.message(
          FirebaseAuthException(code: 'user-not-found'),
        ),
        "You don't have an account. Please sign up first.",
      );
      expect(
        PasswordAuthService.message(
          FirebaseAuthException(code: 'invalid-credential'),
        ),
        contains('Login ID or password is incorrect'),
      );
      expect(
        PasswordAuthService.message(
          FirebaseAuthException(code: 'invalid-credential'),
        ),
        contains('please sign up first'),
      );
      expect(
        PasswordAuthService.message(
          FirebaseAuthException(code: 'email-already-in-use'),
        ),
        contains('Please log in'),
      );
    },
  );
}
