import 'dart:convert';
import 'package:http/http.dart' as http;
import '../offline/offline_runtime.dart';
import '../config/app_config.dart';

class BillingService {
  static Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> values = const {},
  ]) async {
    final token = OfflineRuntime.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Sign in again to manage billing.');
    final response = await http
        .post(
          Uri.parse(
            '${AppConfig.supabaseUrl}/functions/v1/billing?__breeder_network=1',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'apikey': AppConfig.supabaseKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'action': action, ...values}),
        )
        .timeout(const Duration(seconds: 90));
    final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (response.statusCode != 200 || data['error'] != null) {
      throw Exception(
        data['error'] ?? 'Billing is unavailable. Please retry online.',
      );
    }
    return data;
  }
}

String billingTier(String code) =>
    const {
      'HOBBY': 'Hobby Breeder',
      'PRO': 'Professional Breeder',
      'TOP': 'Top Tier',
    }[code] ??
    code;
String billingPrice(Map price) =>
    '\$${((price['amount_cents'] as num) / 100).toStringAsFixed(2)}/${price['interval']}';
