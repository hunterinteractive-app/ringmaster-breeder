import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../models/pedigree_entry.dart';
import '../utils/animal_labels.dart';
import '../utils/color_details.dart';
import '../utils/pedigree_counts.dart';

class PedigreePreview extends StatefulWidget {
  final PedigreeEntry entry;
  final bool embedded;
  final Set<String> repeatedIds;
  final ValueChanged<String>? onAnimalTap;
  const PedigreePreview({
    super.key,
    required this.entry,
    this.embedded = false,
    this.repeatedIds = const {},
    this.onAnimalTap,
  });

  factory PedigreePreview.snapshot({
    Key? key,
    required Map<String, dynamic> pedigree,
    ValueChanged<String>? onAnimalTap,
  }) {
    const slots = [
      'animal',
      'sire',
      'dam',
      'sire_sire',
      'sire_dam',
      'dam_sire',
      'dam_dam',
      'gg1',
      'gg2',
      'gg3',
      'gg4',
      'gg5',
      'gg6',
      'gg7',
      'gg8',
    ];
    final entry = PedigreeEntry();
    entry.nodes.clear();
    entry.root = 'slot0';
    // Keep each snapshot position independent, including repeated ancestors at
    // different depths, so the snapshot's generation boundary stays intact.
    for (var i = 0; i < slots.length; i++) {
      final animal = pedigree[slots[i]];
      if (animal is! Map) continue;
      entry.nodes['slot$i'] = Map<String, dynamic>.from(animal)
        ..remove('sire')
        ..remove('dam');
    }
    for (var i = 1; i < slots.length; i++) {
      if (entry.nodes.containsKey('slot$i')) {
        entry.nodes['slot${(i - 1) ~/ 2}']?[i.isOdd ? 'sire' : 'dam'] =
            'slot$i';
      }
    }
    return PedigreePreview(
      key: key,
      entry: entry,
      embedded: true,
      repeatedIds: pedigreeCounts(
        pedigree,
      ).entries.where((e) => e.value > 1).map((e) => e.key).toSet(),
      onAnimalTap: onAnimalTap,
    );
  }
  @override
  State<PedigreePreview> createState() => _PedigreePreviewState();
}

class _PedigreePreviewState extends State<PedigreePreview> {
  static const navy = Color(0xFF1E2849), maroon = Color(0xFF42101A);
  static const paper = Color(0xFFF9F8F5), accent = Color(0xFFC7CBCC);
  static const width = 1240.0, columnWidth = 286.0;
  final transform = TransformationController();
  Size? lastViewport;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  Map<String, dynamic>? node(int slot) =>
      widget.entry.nodes[widget.entry.at(slot)];
  String text(Map<String, dynamic>? a, String key) => a?[key]?.toString() ?? '';
  String facts(int slot) {
    final a = node(slot);
    if (a == null) return 'Unknown';
    final rawDate = text(a, 'dob');
    final date = DateTime.tryParse(rawDate);
    return [
      animalTitle(a['name'], a['tattoo']),
      varietyLabel(a),
      if (slot != 0 && widget.repeatedIds.contains(a['id']))
        'Repeated ancestor',
      'Ear #: ${text(a, 'tattoo')}   Reg #: ${text(a, 'registration_number')}',
      'Weight: ${text(a, 'weight')}   GC: ${text(a, 'grand_champion_number')}',
      'Legs: ${text(a, 'legs')}   DOB: ${date == null ? rawDate : DateFormat('MM/dd/yyyy').format(date)}',
    ].join('\n');
  }

  double measure(String value, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: columnWidth - 24);
    return painter.height;
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 13, height: 1.25, color: navy);
    final blockHeights = List.generate(
      15,
      (i) =>
          44 +
          measure(facts(i), style) +
          (text(node(i), 'leg_details').isEmpty
              ? 0
              : 8 + measure(text(node(i), 'leg_details'), style)),
    );
    final rowHeight = blockHeights.reduce(math.max) + 20;
    final chartHeight = rowHeight * 8;
    final height = chartHeight + 140;
    void fit(Size viewport) {
      final scale = math.min(viewport.width / width, viewport.height / height);
      transform.value = Matrix4.identity()
        ..setTranslationRaw(
          (viewport.width - width * scale) / 2,
          (viewport.height - height * scale) / 2,
          0,
        )
        ..scaleByDouble(scale, scale, scale, 1);
    }

    final content = Column(
      children: [
        Material(
          color: maroon,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.embedded ? 'Pedigree Tree' : 'Pedigree preview',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
                IconButton(
                  tooltip: 'Zoom out',
                  icon: const Icon(Icons.remove, color: Colors.white),
                  onPressed: () {
                    transform.value = transform.value.clone()
                      ..scaleByDouble(0.8, 0.8, 0.8, 1);
                  },
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: () {
                    transform.value = transform.value.clone()
                      ..scaleByDouble(1.25, 1.25, 1.25, 1);
                  },
                ),
                TextButton(
                  onPressed: () {
                    if (lastViewport != null) fit(lastViewport!);
                  },
                  child: const Text(
                    'Fit',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                if (!widget.embedded)
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = constraints.biggest;
              if (lastViewport != viewport) {
                lastViewport = viewport;
                fit(viewport);
              }
              return ColoredBox(
                color: accent,
                child: InteractiveViewer(
                  transformationController: transform,
                  constrained: false,
                  minScale: 0.01,
                  maxScale: 5,
                  boundaryMargin: const EdgeInsets.all(600),
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: ColoredBox(
                      color: paper,
                      child: Stack(
                        children: [
                          Positioned(
                            top: 20,
                            left: 20,
                            right: 20,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              color: maroon,
                              child: Text(
                                'RingMaster Breeder  •  ${text(node(0), 'breed')} Pedigree',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          for (var generation = 0; generation < 4; generation++)
                            for (
                              var index = 0;
                              index < (1 << generation);
                              index++
                            )
                              Positioned(
                                left: 24 + generation * 302.0,
                                top:
                                    100 +
                                    chartHeight /
                                        (1 << generation) *
                                        (index + 0.5) -
                                    blockHeights[(1 << generation) -
                                            1 +
                                            index] /
                                        2,
                                width: columnWidth,
                                child: _animal(
                                  (1 << generation) - 1 + index,
                                  style,
                                ),
                              ),
                          Positioned(
                            bottom: 12,
                            left: 24,
                            child: Text(
                              widget.embedded
                                  ? 'RingMaster Breeder • Pedigree'
                                  : 'RingMaster Breeder • Pedigree preview',
                              style: TextStyle(color: navy, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
    return widget.embedded ? content : Dialog.fullscreen(child: content);
  }

  Widget _animal(int slot, TextStyle style) {
    final a = node(slot);
    final male = slot == 0 ? animalIsMale(text(a, 'sex')) : slot.isOdd;
    final border = male ? navy : maroon;
    final results = text(a, 'leg_details');
    return InkWell(
      onTap: a?['id'] is String && widget.onAnimalTap != null
          ? () => widget.onAnimalTap!(a!['id'] as String)
          : null,
      child: Column(
        key: ValueKey('pedigree-slot-$slot'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: male ? const Color(0xFFE8ECF3) : const Color(0xFFF2E6E9),
              border: Border.all(color: border, width: 2),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PedigreeEntry.slots[slot],
                  style: style.copyWith(
                    fontWeight: FontWeight.bold,
                    color: border,
                  ),
                ),
                Text(facts(slot), style: style),
              ],
            ),
          ),
          if (results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
              child: Text(results, style: style),
            ),
        ],
      ),
    );
  }
}
