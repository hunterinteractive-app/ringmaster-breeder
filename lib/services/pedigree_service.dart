import 'package:supabase_flutter/supabase_flutter.dart';

class PedigreeService {
  static final supabase = Supabase.instance.client;

  /// ---------------------------------------------------------
  /// BUILD FULL PEDIGREE SNAPSHOT (WITH WEIGHT)
  /// ---------------------------------------------------------
  static Future<Map<String, dynamic>> build(String animalId) async {
    final animal = await _getWithWeight(animalId);
    if (animal == null) return {};

    final sire = await _getWithWeight(animal["sire_id"]);
    final dam  = await _getWithWeight(animal["dam_id"]);

    final sireSire = await _getWithWeight(sire?["sire_id"]);
    final sireDam  = await _getWithWeight(sire?["dam_id"]);

    final damSire  = await _getWithWeight(dam?["sire_id"]);
    final damDam   = await _getWithWeight(dam?["dam_id"]);

    final gg1 = await _getWithWeight(sireSire?["sire_id"]);
    final gg2 = await _getWithWeight(sireSire?["dam_id"]);
    final gg3 = await _getWithWeight(sireDam?["sire_id"]);
    final gg4 = await _getWithWeight(sireDam?["dam_id"]);

    final gg5 = await _getWithWeight(damSire?["sire_id"]);
    final gg6 = await _getWithWeight(damSire?["dam_id"]);
    final gg7 = await _getWithWeight(damDam?["sire_id"]);
    final gg8 = await _getWithWeight(damDam?["dam_id"]);

    return {
      "animal": animal,

      "sire": sire,
      "dam": dam,

      "sire_sire": sireSire,
      "sire_dam": sireDam,

      "dam_sire": damSire,
      "dam_dam": damDam,

      "gg1": gg1,
      "gg2": gg2,
      "gg3": gg3,
      "gg4": gg4,
      "gg5": gg5,
      "gg6": gg6,
      "gg7": gg7,
      "gg8": gg8,
    };
  }

  /// ---------------------------------------------------------
  /// GET ANIMAL + SNAPSHOT LATEST WEIGHT
  /// ---------------------------------------------------------
  static Future<Map<String, dynamic>?> _getWithWeight(String? id) async {
    if (id == null || id.isEmpty) return null;

    final animal = await supabase
        .from("animals")
        .select("""
          id,
          name,
          tattoo,
          breed,
          variety,
          dob,
          registration_number,
          grand_champion_number,
          sire_id,
          dam_id
        """)
        .eq("id", id)
        .maybeSingle();

    if (animal == null) return null;

    final weight = await _getLatestWeight(id);

    final map = Map<String, dynamic>.from(animal);
    map["weight"] = weight; // ← snapshot injected here

    return map;
  }

  /// ---------------------------------------------------------
  /// GET MOST RECENT WEIGHT (SNAPSHOT)
  /// ---------------------------------------------------------
  static Future<double?> _getLatestWeight(String animalId) async {
    final res = await supabase
        .from("animal_weights")
        .select("weight")
        .eq("animal_id", animalId)
        .order("recorded_at", ascending: false)
        .limit(1);

    if (res.isEmpty) return null;
    return (res.first["weight"] as num).toDouble();
  }
}