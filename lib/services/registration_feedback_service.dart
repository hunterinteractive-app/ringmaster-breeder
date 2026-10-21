import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../offline/offline_runtime.dart';

typedef RegistrationFeedbackRequest =
    Future<Map<String, dynamic>> Function(
      String action,
      Map<String, dynamic> answers,
    );

class RegistrationFeedbackService {
  static Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> answers,
  ) async {
    final token = OfflineRuntime.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Sign in to save your answers.');
    final response = await http
        .post(
          Uri.parse(
            '${AppConfig.supabaseUrl}/rest/v1/rpc/breeder_registration_feedback?__breeder_network=1',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'apikey': AppConfig.supabaseKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'p_action': action,
            'p_answers': action == 'admin-list' ? <String, dynamic>{} : answers,
            'p_offset': action == 'admin-list' ? answers['offset'] ?? 0 : 0,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception(
        'Unable to save or load answers. Please try again online.',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }
}
