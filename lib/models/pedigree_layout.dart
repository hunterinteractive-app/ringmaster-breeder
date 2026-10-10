import 'dart:math' as math;
import 'pedigree_entry.dart';

/// PDF points shared by the printed layout and the screen's clickable overlay.
class PedigreeLayout {
  static const width = 792.0, boxWidth = 170.0, boxHeight = 55.0;
  final Map<String, dynamic> pedigree;
  late final List<List<String>> details;
  late final double rowHeight;
  late final double height;
  PedigreeLayout(this.pedigree) {
    details = [
      for (final key in PedigreeEntry.snapshotSlots)
        wrap((pedigree[key]?['leg_details'] ?? '').toString()),
    ];
    rowHeight = math.max(
      61.0,
      [
        for (var i = 0; i < details.length; i++)
          (61.0 + (details[i].isEmpty ? 0 : 4 + details[i].length * 10)) /
              (8 / (1 << generation(i))),
      ].reduce(math.max),
    );
    height = math.max(612.0, 92 + rowHeight * 8 + 32);
  }
  static List<String> wrap(String text) {
    if (text.trim().isEmpty) return [];
    final lines = <String>[];
    for (var line in text.split('\n')) {
      while (line.length > 34) {
        var split = line.lastIndexOf(' ', 34);
        if (split < 1) split = 34;
        lines.add(line.substring(0, split));
        line = line.substring(split).trimLeft();
      }
      lines.add(line);
    }
    return lines;
  }

  int generation(int slot) => ((slot + 1).bitLength - 1);
  double left(int slot) => 36 + generation(slot) * 180.0;
  double top(int slot) {
    final g = generation(slot);
    final index = slot - ((1 << g) - 1);
    final blockHeight =
        boxHeight + (details[slot].isEmpty ? 0 : 4 + details[slot].length * 10);
    return 92 + rowHeight * 8 / (1 << g) * (index + .5) - blockHeight / 2;
  }
}
