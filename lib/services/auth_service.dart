import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class AuthGateway {
  Future<void> requestCode(String email);
  Future<void> verifyCode(String email, String code);
}

class AuthService implements AuthGateway {
  final SupabaseClient client;
  AuthService(this.client);
  @override
  Future<void> requestCode(String email) => client.auth.signInWithOtp(
    email: email.trim().toLowerCase(),
    shouldCreateUser: true,
  );
  @override
  Future<void> verifyCode(String email, String code) async {
    await client.auth.verifyOTP(
      email: email.trim().toLowerCase(),
      token: code.trim(),
      type: OtpType.email,
    );
  }
}
