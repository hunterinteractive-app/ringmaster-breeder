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
          child: PdfPreview(
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
