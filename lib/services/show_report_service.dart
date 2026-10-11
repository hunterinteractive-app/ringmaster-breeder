import 'package:supabase_flutter/supabase_flutter.dart';

class ShowReportService {
  static Future<Map<String, dynamic>> request(
    String action, {
    String? ownerId,
    String? reportId,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'show-reports',
      body: {
        'action': action,
        if (ownerId != null) 'owner_id': ownerId,
        if (reportId != null) 'report_id': reportId,
      },
    );
    final result = Map<String, dynamic>.from(response.data as Map);
    if (result['error'] != null) throw Exception(result['error']);
    return result;
  }
}
