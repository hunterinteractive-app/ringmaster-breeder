import '../utils/color_details.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pedigree_tree_screen.dart';
import '../services/pedigree_service.dart';
import '../services/pedigree_pdf_service.dart';
import 'package:printing/printing.dart';
import '../utils/animal_labels.dart';
import 'dart:typed_data';
import 'health_records_screen.dart';
import '../services/animal_service.dart';
import '../widgets/animal_avatar.dart';

class AnimalDetailScreen extends StatefulWidget {
  final String animalId;

  const AnimalDetailScreen({super.key, required this.animalId});

  @override
  State<AnimalDetailScreen> createState() => _AnimalDetailScreenState();
}

class _AnimalDetailScreenState extends State<AnimalDetailScreen> {
  final supabase = Supabase.instance.client;
  bool _uploadingPhoto = false;
  Future<void> _uploadPhoto() async {
    setState(() => _uploadingPhoto = true);
    try {
      await AnimalService.uploadPhoto(widget.animalId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to upload photo. Choose a JPG, PNG or WebP under 5 MB and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  /// --- Helpers ---
  bool isLocked(String status) => animalIsLocked(status);

  String statusLockMessage(String status) {
    if (status == "sold") return "This animal has been sold.";
    if (status == "deceased") return "This animal is marked deceased.";
    return "";
  }

  /// --- Queries ---
  Future<Map<String, dynamic>> fetchAnimal() =>
      AnimalService.get(widget.animalId);
  Future<Map<String, dynamic>?> fetchParent(String? id) =>
      AnimalService.parent(id);

  Future<double?> fetchWeight() => AnimalService.latestWeight(widget.animalId);

  // ------------------------------------------------------------
  // SAVE + SHARE PDF UTILITY
  // ------------------------------------------------------------
  Future<void> saveAndSharePdf({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    try {
      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Sharing failed: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: "Animal Details",
      body: FutureBuilder(
        future: Future.wait([fetchAnimal(), fetchWeight()]),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                "Unable to load records. Please go back and try again.",
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final animal = snapshot.data![0] as Map<String, dynamic>;
          final double? weight = snapshot.data![1] as double?;
          final locked = isLocked(animal["status"]);

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                Center(
                  child: AnimalAvatar(
                    species: animal['species'],
                    photoUrl: animal['photo_url'],
                    size: 112,
                  ),
                ),
                if (!locked)
                  Center(
                    child: TextButton.icon(
                      onPressed: _uploadingPhoto ? null : _uploadPhoto,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        _uploadingPhoto
                            ? 'Uploading…'
                            : animal['photo_path'] == null
                            ? 'Upload photo'
                            : 'Change photo',
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                /// NAME
                Text(
                  animalTitle(animal["name"], animal["tattoo"]),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),

                /// LOCK NOTICE
                if (locked)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusLockMessage(animal["status"]),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),

                /// BASIC DATA
                _row("Tattoo", animal["tattoo"]),
                _row("Species", animal["species"]),
                _row("Breed", animal["breed"]),
                _row("Variety", varietyLabel(animal)),
                _row("Sex", sexLabel(animal["species"], animal["sex"])),
                _row(
                  "Current Weight",
                  weight == null ? "-" : "${weight.toStringAsFixed(2)} lb",
                ),
                _row("Registration #", animal["registration_number"]),
                _row("GC #", animal["grand_champion_number"]),
                _row("Legs", animal["legs"]),
                if ((animal["leg_details"] ?? "").toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: SelectableText(
                      "Legs / show details\n${animal["leg_details"]}",
                    ),
                  ),
                const SizedBox(height: 24),

                /// PARENTS SECTION
                FutureBuilder(
                  future: fetchParent(animal["sire_id"]),
                  builder: (context, snap) {
                    final sire = snap.data;
                    return _row(
                      "Sire",
                      sire == null
                          ? "-"
                          : "${sire['name']} (${sire['tattoo'] ?? ''})",
                    );
                  },
                ),

                FutureBuilder(
                  future: fetchParent(animal["dam_id"]),
                  builder: (context, snap) {
                    final dam = snap.data;
                    return _row(
                      "Dam",
                      dam == null
                          ? "-"
                          : "${dam['name']} (${dam['tattoo'] ?? ''})",
                    );
                  },
                ),

                const SizedBox(height: 24),

                /// Edit Animal
                ElevatedButton(
                  onPressed: locked
                      ? null
                      : () async {
                          final updated = await Navigator.pushNamed(
                            context,
                            "/edit-animal",
                            arguments: widget.animalId,
                          );

                          if (updated == true && mounted) setState(() {});
                        },
                  child: const Text("Edit Animal"),
                ),

                const SizedBox(height: 12),

                /// Weight History
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      "/weight-history",
                      arguments: {
                        'animalId': widget.animalId,
                        'status': animal["status"],
                      },
                    );
                  },
                  child: const Text("View Weight History"),
                ),

                const SizedBox(height: 12),

                /// Health & Vaccine Records
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            HealthRecordsScreen(animalId: widget.animalId),
                      ),
                    );
                  },
                  child: const Text("Health & Vaccine Records"),
                ),

                const SizedBox(height: 12),

                /// View Pedigree Tree
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PedigreeTreeScreen(animalId: widget.animalId),
                      ),
                    );
                  },
                  child: const Text("View Pedigree Tree"),
                ),

                const SizedBox(height: 12),

                /// PDF EXPORT
                OutlinedButton(
                  onPressed: () async {
                    try {
                      final pedigree = await PedigreeService.build(
                        widget.animalId,
                      );
                      final seller = await PedigreeService.seller();

                      final pdfBytes = await PedigreePdfService.generate(
                        pedigree: pedigree,
                        seller: seller,
                      );

                      await saveAndSharePdf(
                        pdfBytes: pdfBytes,
                        fileName: "pedigree-${widget.animalId}.pdf",
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text("PDF failed: $e")));
                    }
                  },
                  child: const Text("Export Pedigree PDF"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String title, Object? value) =>
      AnimalDetailRow(title: title, value: value);
}

class AnimalDetailRow extends StatelessWidget {
  final String title;
  final Object? value;
  const AnimalDetailRow({super.key, required this.title, this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('$title:', style: const TextStyle(fontWeight: FontWeight.bold)),
        Flexible(
          child: Text(value?.toString() ?? '-', textAlign: TextAlign.right),
        ),
      ],
    ),
  );
}
