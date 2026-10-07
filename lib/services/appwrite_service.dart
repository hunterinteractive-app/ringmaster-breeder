import 'package:appwrite/appwrite.dart';

class AppwriteService {
  static late Client client;
  static late Account account;

  static void init() {
    client = Client()
      ..setEndpoint('https://sfo.cloud.appwrite.io/v1')
      ..setProject('690694870030987a84e5');
      ..setSelfSigned(status: false);

    account = Account(client);
  }

  static Future<Session> login(String email, String password) async {
    return await account.createEmailPasswordSession(
      email: email,
      password: password,
    );
  }

  static Future<void> logout() async {
    await account.deleteSession(sessionId: 'current');
  }

  static Future<User?> getCurrentUser() async {
    try {
      return await account.get();
    } catch (_) {
      return null;
    }
  }
}