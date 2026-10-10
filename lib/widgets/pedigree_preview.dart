import '../models/pedigree_layout.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../models/pedigree_entry.dart';
import '../services/pedigree_pdf_service.dart';
import '../services/pedigree_service.dart';
import '../utils/animal_labels.dart';

/// Both on-screen views render the export itself, keeping all pages identical.
class PedigreePreview extends StatefulWidget {
  final PedigreeEntry? entry;
  final Map<String, dynamic>? pedigree;
  final bool embedded;
  final ValueChanged<String>? onAnimalTap;
  const PedigreePreview({super.key, required PedigreeEntry this.entry})
    : pedigree = null,
      embedded = false,
      onAnimalTap = null;
  const PedigreePreview.snapshot({
    super.key,
    required Map<String, dynamic> this.pedigree,
    this.onAnimalTap,
  }) : entry = null,
       embedded = true;

  @override
  State<PedigreePreview> createState() => _PedigreePreviewState();
}

class _PedigreePreviewState extends State<PedigreePreview> {
  late final Map<String, dynamic> pedigree;
  late final Future<Uint8List> document;
  @override
  void initState() {
    super.initState();
    pedigree = widget.pedigree ?? widget.entry!.snapshot();
    document = _generate();
  }

  Future<Uint8List> _generate() async => PedigreePdfService.generate(
    pedigree: pedigree,
    seller: await PedigreeService.seller(),
  );

  @override
  Widget build(BuildContext context) {
    final animals = <String, Map>{};
    for (final animal in pedigree.values) {
      if (animal is Map && animal['id'] is String) {
        animals[animal['id']] = animal;
      }
    }
    final content = Column(
      children: [
        Material(
          color: const Color(0xFF42101A),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.embedded ? 'Pedigree Tree' : 'Pedigree preview',
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
              if (widget.onAnimalTap != null && animals.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'Open animal record',
                  icon: const Icon(Icons.open_in_new, color: Colors.white),
                  onSelected: widget.onAnimalTap,
                  itemBuilder: (_) => animals.entries
                      .map(
                        (e) => PopupMenuItem(
                          value: e.key,
                          child: Text(
                            animalTitle(e.value['name'], e.value['tattoo']),
                          ),
                        ),
                      )
                      .toList(),
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
        Expanded(
          child: PdfPreview.builder(
            pagesBuilder: (context, pages) => LayoutBuilder(
              builder: (context, constraints) {
                final layout = PedigreeLayout(pedigree);
                final pageWidth = constraints.maxWidth;
                final scale = pageWidth / PedigreeLayout.width;
                return InteractiveViewer(
                  maxScale: 5,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final page in pages)
                          SizedBox(
                            width: pageWidth,
                            height: layout.height * scale,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Image(
                                    image: page.image,
                                    fit: BoxFit.fill,
                                  ),
                                ),
                                if (widget.onAnimalTap != null)
                                  for (
                                    var slot = 0;
                                    slot < PedigreeEntry.snapshotSlots.length;
                                    slot++
                                  )
                                    if (pedigree[PedigreeEntry
                                            .snapshotSlots[slot]]?['id']
                                        is String)
                                      Positioned(
                                        left: layout.left(slot) * scale,
                                        top: layout.top(slot) * scale,
                                        width: PedigreeLayout.boxWidth * scale,
                                        height:
                                            PedigreeLayout.boxHeight * scale,
                                        child: Tooltip(
                                          message: 'Open animal record',
                                          child: InkWell(
                                            key: ValueKey(
                                              'pedigree-link-$slot',
                                            ),
                                            onTap: () => widget.onAnimalTap!(
                                              pedigree[PedigreeEntry
                                                  .snapshotSlots[slot]]['id'],
                                            ),
                                            child: const SizedBox.expand(),
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            build: (_) => document,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowPrinting: false,
            allowSharing: false,
            pdfFileName: 'pedigree.pdf',
            onError: (_, error) => const Center(
              child: Text(
                'Unable to load pedigree. Please close and try again.',
              ),
            ),
          ),
        ),
      ],
    );
    return widget.embedded ? content : Dialog.fullscreen(child: content);
  }
}
