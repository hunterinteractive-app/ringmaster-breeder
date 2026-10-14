import 'package:supabase_flutter/supabase_flutter.dart';
import 'record_import_service.dart';

abstract interface class GlobalPedigreeImportGateway {
  Future<List<Map<String, dynamic>>> ownedHerds();
  Future<Map<String, dynamic>?> pendingDraft();
  Future<void> discardDraft();
  Future<Map<String, dynamic>> collect(String username, String password);
  Future<Map<String, dynamic>> review(String herd, Map<String, dynamic> data);
  Future<Map<String, dynamic>> save(String herd, Map<String, dynamic> data);
}

class GlobalPedigreeImportService implements GlobalPedigreeImportGateway {
  final SupabaseClient client;
  GlobalPedigreeImportService(this.client);

  @override
  Future<List<Map<String, dynamic>>> ownedHerds() =>
      RecordImportService(client).ownedRings();

  @override
  Future<Map<String, dynamic>?> pendingDraft() async {
    final draft = await client
        .from('global_pedigree_import_drafts')
        .select(
          'ring_id,account,animals,history,history_complete,sales_complete',
        )
        .eq('auth_user_id', client.auth.currentUser!.id)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .maybeSingle();
    return draft;
  }

  @override
  Future<void> discardDraft() async {
    await client
        .from('global_pedigree_import_drafts')
        .delete()
        .eq('auth_user_id', client.auth.currentUser!.id);
  }

  @override
  Future<Map<String, dynamic>> collect(String username, String password) async {
    try {
      final animals = <Map<String, dynamic>>[];
      final history = <Map<String, dynamic>>[];
      Map<String, dynamic> body = {'username': username, 'password': password};
      String? account;
      for (var batch = 0; batch < 850; batch++) {
        final response = await client.functions.invoke(
          'global-pedigree',
          body: body,
        );
        final data = Map<String, dynamic>.from(response.data as Map);
        if (data['account'] is! String ||
            (account != null && account != data['account'])) {
          throw const FormatException(
            'The Global Pedigree account changed during collection.',
          );
        }
        account = data['account'] as String;
        animals.addAll(
          (data['animals'] as List).map(
            (a) => Map<String, dynamic>.from(a as Map),
          ),
        );
        history.addAll(
          (data['history'] as List? ?? []).map(
            (r) => Map<String, dynamic>.from(r as Map),
          ),
        );
        if (history.length > 20000) {
          throw const FormatException(
            'This importer supports up to 20,000 history records.',
          );
        }
        if (animals.length > 2000) {
          throw const FormatException(
            'This importer supports up to 2,000 rabbits and ancestors.',
          );
        }
        if (data['status'] == 'collected') {
          if (animals.map((a) => a['source_id']).toSet().length !=
              animals.length) {
            throw const FormatException(
              'Duplicate Global Pedigree records were returned.',
            );
          }
          return {
            'status': 'collected',
            'account': account,
            'animals': animals,
            'history': history,
            'history_complete': data['history_complete'] == true,
            'sales_complete': data['sales_complete'] == true,
          };
        }
        if (data['status'] != 'collecting' || data['token'] is! String) {
          throw const FormatException(
            'Unable to read the complete Global Pedigree pedigree.',
          );
        }
        body = {'token': data['token']};
      }
      throw const FormatException(
        'The collection did not finish. Please reconnect.',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      throw FormatException(
        details is Map && details['message'] is String
            ? details['message'] as String
            : 'Unable to connect to Global Pedigree. Please try again.',
      );
    }
  }

  Future<Map<String, dynamic>> _run(
    String herd,
    Map<String, dynamic> data,
    bool commit,
  ) async {
    final result = await client.rpc(
      'import_global_pedigree_with_sales',
      params: {
        'p_ring': herd,
        'p_account': data['account'],
        'p_animals': data['animals'],
        'p_commit': commit,
        'p_history': data['history'] ?? [],
        'p_history_complete': data['history_complete'] == true,
        'p_sales_complete': data['sales_complete'] == true,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<Map<String, dynamic>> review(String herd, Map<String, dynamic> data) =>
      _run(herd, data, false);

  @override
  Future<Map<String, dynamic>> save(String herd, Map<String, dynamic> data) =>
      _run(herd, data, true);
}
