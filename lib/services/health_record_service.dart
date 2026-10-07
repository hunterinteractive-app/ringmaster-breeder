import 'package:supabase_flutter/supabase_flutter.dart';

class HealthRecordService {
  static final supabase = Supabase.instance.client;

  // =====================================================
  // FETCH ALL HEALTH RECORDS FOR AN ANIMAL
  // =====================================================
  static Future<List<Map<String, dynamic>>> fetchRecords(
    String animalId,
  ) async {
    final data = await supabase
        .from('animal_health_records')
        .select()
        .eq('animal_id', animalId)
        .order('record_date', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  // =====================================================
  // ADD A HEALTH / VACCINE RECORD
  // =====================================================
  static Future<void> addRecord({
    required String animalId,
    required String type,          // vaccine | deworm | vet | note
    required String title,          // e.g. "RHDV2 Vaccine"
    String? description,
    DateTime? recordDate,
    String? administeredBy,
    DateTime? nextDueDate,
  }) async {
    await supabase.from('animal_health_records').insert({
      'animal_id': animalId,
      'record_type': type,
      'title': title,
      'description': description,
      'record_date': recordDate?.toIso8601String() ??
          DateTime.now().toIso8601String(),
      'administered_by': administeredBy,
      'next_due_date': nextDueDate?.toIso8601String(),
    });
  }

  // =====================================================
  // DELETE RECORD (ADMIN / OWNER ONLY)
  // =====================================================
  static Future<void> deleteRecord(String recordId) async {
    await supabase
        .from('animal_health_records')
        .delete()
        .eq('id', recordId);
  }
}