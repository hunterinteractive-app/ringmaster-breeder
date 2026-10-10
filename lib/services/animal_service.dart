import 'catalog_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

class AnimalService {
  static SupabaseClient get _client => Supabase.instance.client;
  static Future<Map<String, dynamic>> get(String id) =>
      _client.from('animals').select().eq('id', id).single().then(_withPhoto);
  static Future<Map<String, dynamic>?> parent(String? id) async {
    if (id == null) return null;
    return _client
        .from('animals')
        .select('name, tattoo')
        .eq('id', id)
        .maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> list(String ringId) async =>
      Future.wait(
        List<Map<String, dynamic>>.from(
          await _client
              .from('animals')
              .select()
              .eq('ring_id', ringId)
              .eq('pedigree_only', false)
              .order('created_at'),
        ).map(_withPhoto),
      );
  static Future<Map<String, dynamic>> _withPhoto(
    Map<String, dynamic> animal,
  ) async {
    try {
      final species = animal['species']?.toString() ?? 'rabbit';
      final breeds = await CatalogService.options(species, null);
      final varieties = await CatalogService.options(
        species,
        animal['breed']?.toString() ?? '',
      );
      for (final field in ['breed', 'variety']) {
        final rows = field == 'breed' ? breeds : varieties;
        final matching = rows.where(
          (r) => CatalogService.matches(r, animal[field]?.toString() ?? ''),
        );
        if (matching.isNotEmpty && matching.first['is_recognized'] == true) {
          animal[field] = matching.first['name'];
        }
        animal['${field}_unrecognized'] =
            (animal[field]?.toString().trim().isNotEmpty ?? false) &&
            !rows.any(
              (r) =>
                  CatalogService.matches(r, animal[field].toString()) &&
                  r['is_recognized'] == true,
            );
      }
    } catch (_) {
      /* Animal records remain available during catalog outages. */
    }
    final path = animal['photo_path'] as String?;
    if (path != null) {
      try {
        animal['photo_url'] = await _client.storage
            .from('animal_photos')
            .createSignedUrl(path, 3600);
      } catch (_) {
        animal['photo_url'] = null;
      }
    }
    return animal;
  }

  static Future<bool> uploadPhoto(String animalId) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (picked == null) return false;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw Exception('Choose a photo smaller than 5 MB.');
    }
    final ext = file.extension?.toLowerCase();
    final mime = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw Exception('Choose a JPG, PNG or WebP photo.'),
    };
    final path = '$animalId/${DateTime.now().microsecondsSinceEpoch}.$ext';
    final old = await _client
        .from('animals')
        .select('photo_path')
        .eq('id', animalId)
        .single();
    await _client.storage
        .from('animal_photos')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    try {
      await update(animalId, {'photo_path': path});
    } catch (_) {
      await _client.storage.from('animal_photos').remove([path]);
      rethrow;
    }
    if (old['photo_path'] != null) {
      try {
        await _client.storage.from('animal_photos').remove([
          old['photo_path'] as String,
        ]);
      } catch (_) {}
    }
    return true;
  }

  static Future<List<Map<String, dynamic>>> weights(String animalId) async =>
      List<Map<String, dynamic>>.from(
        await _client
            .from('animal_weights')
            .select()
            .eq('animal_id', animalId)
            .order('recorded_at', ascending: false),
      );
  static Future<double?> latestWeight(String animalId) async {
    final rows = await _client
        .from('animal_weights')
        .select('weight')
        .eq('animal_id', animalId)
        .order('recorded_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : (rows.first['weight'] as num).toDouble();
  }

  static Future<void> addWeight(String animalId, double weight) async {
    if (!weight.isFinite || weight <= 0) {
      throw ArgumentError('Weight must be positive');
    }
    await _client.from('animal_weights').insert({
      'animal_id': animalId,
      'weight': weight,
    });
  }

  static Future<void> editLatestWeight(
    String animalId,
    String recordId,
    double weight,
  ) async {
    if (!weight.isFinite || weight <= 0) {
      throw ArgumentError('Weight must be positive');
    }
    final updated = await _client
        .from('animal_weights')
        .update({'weight': weight})
        .eq('animal_id', animalId)
        .eq('id', recordId)
        .select('id');
    if (updated.isEmpty) {
      throw StateError(
        'Only the latest weight can be edited. Refresh and try again.',
      );
    }
  }

  static Future<void> update(String id, Map<String, dynamic> changes) async {
    await _client.from('animals').update(changes).eq('id', id);
  }
}
