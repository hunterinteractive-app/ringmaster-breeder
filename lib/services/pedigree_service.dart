import 'package:supabase_flutter/supabase_flutter.dart';
import 'family_service.dart';

class PedigreeService {
  static Future<Map<String, dynamic>> seller() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Not logged in');
    final profile = await client
        .from('users')
        .select()
        .eq('id', FamilyService.ownerId ?? user.id)
        .single();
    return {
      'name': profile['display_name'],
      'address': profile['address'],
      'city': profile['city'],
      'state': profile['state'],
      'zip': profile['zip'],
      'contact': [
        profile['phone'],
        profile['email'],
      ].whereType<String>().where((v) => v.isNotEmpty).join(' • '),
    };
  }

  static Future<Map<String, dynamic>> build(String animalId) async =>
      Map<String, dynamic>.from(
        await Supabase.instance.client.rpc(
              'breeder_pedigree_snapshot',
              params: {'p_animal_id': animalId},
            )
            as Map,
      );
}
