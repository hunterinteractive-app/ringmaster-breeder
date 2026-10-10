import '../utils/animal_labels.dart';

class PedigreeEntry {
  String species = 'rabbit';
  String root = 'new0';
  int next = 1;
  final Map<String, Map<String, dynamic>> nodes = {
    'new0': {'sex': 'Buck'},
  };
  static const slots = [
    'Animal',
    'Sire',
    'Dam',
    "Sire’s sire",
    "Sire’s dam",
    "Dam’s sire",
    "Dam’s dam",
    "Sire’s sire’s sire",
    "Sire’s sire’s dam",
    "Sire’s dam’s sire",
    "Sire’s dam’s dam",
    "Dam’s sire’s sire",
    "Dam’s sire’s dam",
    "Dam’s dam’s sire",
    "Dam’s dam’s dam",
  ];
  static const order = [0, 1, 3, 7, 8, 4, 9, 10, 2, 5, 11, 12, 6, 13, 14];
  String? at(int slot) {
    if (slot == 0) return root;
    final parent = at((slot - 1) ~/ 2);
    return parent == null ? null : nodes[parent]?[slot.isOdd ? 'sire' : 'dam'];
  }

  String expectedSex(int slot) => sexLabel(species, slot.isOdd ? 'M' : 'F');
  String ensure(int slot) {
    final present = at(slot);
    if (present != null) return present;
    final parent = at((slot - 1) ~/ 2);
    if (parent == null) throw StateError('Enter the parent first.');
    if (nodes[parent]!['existing_id'] != null) {
      throw StateError('Edit this existing animal from its own record.');
    }
    final key = 'new${next++}';
    nodes[key] = {
      'sex': expectedSex(slot),
      'breed': nodes[root]?['breed'] ?? '',
    };
    nodes[parent]![slot.isOdd ? 'sire' : 'dam'] = key;
    return key;
  }

  bool reaches(String from, String target, [Set<String>? visited]) {
    if (from == target) return true;
    final seen = visited ?? <String>{};
    if (!seen.add(from)) return false;
    return ['sire', 'dam'].any(
      (side) =>
          nodes[from]?[side] != null &&
          reaches(nodes[from]![side], target, seen),
    );
  }

  void link(int slot, String key) {
    final parent = at((slot - 1) ~/ 2);
    if (slot == 0 || parent == null || nodes[parent]?['existing_id'] != null) {
      throw StateError('This position cannot be changed here.');
    }
    if (nodes[key]?['sex'] != expectedSex(slot)) {
      throw StateError('Choose the correct sex for this position.');
    }
    if (reaches(key, parent)) {
      throw StateError('An animal cannot be its own ancestor.');
    }
    nodes[parent]![slot.isOdd ? 'sire' : 'dam'] = key;
  }

  void unlink(int slot) {
    final parent = at((slot - 1) ~/ 2);
    if (parent != null && nodes[parent]?['existing_id'] == null) {
      nodes[parent]!.remove(slot.isOdd ? 'sire' : 'dam');
    }
  }

  bool identified(String key) => [
    'name',
    'tattoo',
  ].any((f) => (nodes[key]?[f]?.toString().trim() ?? '').isNotEmpty);
  Map<String, dynamic> data() {
    final used = <String, Map<String, dynamic>>{};
    void visit(String key) {
      if (used.containsKey(key)) return;
      final n = Map<String, dynamic>.from(nodes[key]!);
      used[key] = n;
      for (final side in ['sire', 'dam']) {
        final ref = n[side] as String?;
        if (ref == null) continue;
        visit(ref);
      }
    }

    visit(root);
    return {'species': species, 'root': root, 'next': next, 'nodes': used};
  }

  void restore(Map<String, dynamic> data) {
    species = data['species'];
    root = data['root'];
    next = data['next'] ?? 100;
    nodes.clear();
    (data['nodes'] as Map).forEach(
      (k, v) => nodes[k] = Map<String, dynamic>.from(v),
    );
  }
}
