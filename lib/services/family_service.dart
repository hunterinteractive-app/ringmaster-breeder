import 'package:flutter/foundation.dart';
import '../offline/offline_runtime.dart';

class FamilyService {
  static String? selectedHerd;
  static final selectedOwner = ValueNotifier<String?>(null);
  static List<Map<String, dynamic>> households = [];
  static List<Map<String, dynamic>> invitations = [];
  static String? _actor;
  static String? get ownerId =>
      _actor == OfflineRuntime.client.auth.currentUser?.id
      ? selectedOwner.value ??
            (households.isEmpty
                ? _actor
                : households.first['owner_user_id'] as String)
      : OfflineRuntime.client.auth.currentUser?.id;
  static void clear() {
    selectedHerd = null;
    _actor = null;
    households = [];
    invitations = [];
    selectedOwner.value = null;
  }

  static Future<void> refresh({
    String action = 'list',
    String? id,
    String? email,
  }) async {
    final client = OfflineRuntime.client;
    final actor = client.auth.currentUser?.id;
    if (_actor != actor) {
      clear();
      _actor = actor;
    }
    if (actor == null) return;
    Future<Map<String, dynamic>> fetch() async => Map<String, dynamic>.from(
      await client.rpc(
            'breeder_family_access',
            params: {
              'p_action': action,
              'p_invitation_id': id,
              'p_email': email,
            },
          )
          as Map,
    );
    final data = action == 'list'
        ? await OfflineRuntime.readThrough('family', fetch)
        : await fetch();
    if (client.auth.currentUser?.id != actor) return;
    households = (data['households'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    invitations = (data['invitations'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (!households.any((h) => h['owner_user_id'] == selectedOwner.value)) {
      selectedOwner.value = null;
    }
  }

  static void select(String owner) {
    if (!households.any((h) => h['owner_user_id'] == owner)) {
      throw StateError('Family access is no longer available.');
    }
    selectedHerd = null;
    selectedOwner.value = owner;
  }
}
