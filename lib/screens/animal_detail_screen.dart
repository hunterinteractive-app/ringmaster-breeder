import 'kintraks_history_screen.dart';
import 'rabbit_register_history_screen.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/pedigree_email_dialog.dart';
import 'global_pedigree_history_screen.dart';
import '../utils/color_details.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';

import 'pedigree_tree_screen.dart';
import '../services/pedigree_service.dart';
import '../services/pedigree_pdf_service.dart';
import 'package:printing/printing.dart';
import '../utils/animal_labels.dart';
import 'dart:typed_data';
import 'health_records_screen.dart';
import 'show_reports_screen.dart';
import '../services/animal_service.dart';
import '../widgets/animal_avatar.dart';
import '../offline/offline_runtime.dart';

class _AnimalDetails {
  final Map<String, dynamic> animal;
  final double? weight;
  final bool weightDownloaded;
  const _AnimalDetails(this.animal, this.weight, this.weightDownloaded);
}

class AnimalDetailScreen extends StatefulWidget {
  final String animalId;

  const AnimalDetailScreen({super.key, required this.animalId});

  @override
  State<AnimalDetailScreen> createState() => _AnimalDetailScreenState();
}

class _AnimalDetailScreenState extends State<AnimalDetailScreen> {
  final supabase = OfflineRuntime.client;
  bool _uploadingPhoto = false;
  late Future<_AnimalDetails> _details = _load();

  Future<_AnimalDetails> _load() async {
    final animal = await fetchAnimal();
    try {
      return _AnimalDetails(animal, await fetchWeight(), true);
    } on OfflineDataUnavailable {
      // Missing optional history must not hide an animal already downloaded
      // with the herd list. Permission and other server errors still surface.
      return _AnimalDetails(animal, null, false);
    }
  }

  void _reload() => setState(() => _details = _load());
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
      if (mounted) {
        setState(() {
          _uploadingPhoto = false;
          _details = _load();
        });
      }
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
      onRefresh: _reload,
      title: "Animal Details",
      body: FutureBuilder<_AnimalDetails>(
        future: _details,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                snapshot.error is OfflineDataUnavailable
                    ? snapshot.error.toString()
                    : "Unable to load records. Please go back and try again.",
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final animal = snapshot.data!.animal;
          final weight = snapshot.data!.weight;
          final locked = isLocked(animal["status"]);

          return AnimalDetailContent(
            animal: animal,
            weightText: !snapshot.data!.weightDownloaded
                ? 'Not downloaded'
                : weight == null
                ? '-'
                : '${weight.toStringAsFixed(2)} lb',
            lockMessage: locked ? statusLockMessage(animal['status']) : null,
            uploadingPhoto: _uploadingPhoto,
            onPhoto: locked ? null : _uploadPhoto,
            parents: [
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
            ],
            actions: [
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

                        if (updated == true && mounted) _reload();
                      },
                child: const Text("Edit Animal"),
              ),

              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        GlobalPedigreeHistoryScreen(animalId: widget.animalId),
                  ),
                ),
                child: const Text('Global Pedigree history'),
              ),

              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RabbitRegisterHistoryScreen(animalId: widget.animalId),
                  ),
                ),
                child: const Text('Rabbit Register history'),
              ),

              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        KintraksHistoryScreen(animalId: widget.animalId),
                  ),
                ),
                child: const Text('Kintraks history'),
              ),

              if (animal['status'] == 'sold') ...[
                ElevatedButton.icon(
                  onPressed: () =>
                      offerBuyerPedigree(context, animalId: widget.animalId),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Email pedigree to buyer'),
                ),
              ],

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

              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ShowReportsScreen(animalId: widget.animalId),
                  ),
                ),
                child: const Text('Show history & reports'),
              ),

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
        Flexible(
          child: Text(
            '$title:',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(value?.toString() ?? '-', textAlign: TextAlign.right),
        ),
      ],
    ),
  );
}

/// Presentation only: service calls and action permissions stay in the screen.
class AnimalDetailContent extends StatelessWidget {
  final Map<String, dynamic> animal;
  final String weightText;
  final String? lockMessage;
  final bool uploadingPhoto;
  final VoidCallback? onPhoto;
  final List<Widget> parents;
  final List<Widget> actions;

  const AnimalDetailContent({
    super.key,
    required this.animal,
    required this.weightText,
    this.lockMessage,
    this.uploadingPhoto = false,
    this.onPhoto,
    this.parents = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final compact = BreederLayout.compact(context);
    final title = animalTitle(animal['name'], animal['tattoo']);
    final photoLabel = uploadingPhoto
        ? 'Uploading…'
        : animal['photo_path'] == null
        ? 'Upload photo'
        : 'Change photo';
    final basic = <(String, Object?)>[
      ('Tattoo', animal['tattoo']),
      ('Species', animal['species']),
      ('Breed', animal['breed']),
      ('Variety', varietyLabel(animal)),
      ('Sex', sexLabel(animal['species'], animal['sex'])),
      ('Current Weight', weightText),
    ];
    final registration = <Widget>[
      AnimalDetailRow(
        title: 'Registration #',
        value: animal['registration_number'],
      ),
      AnimalDetailRow(title: 'GC #', value: animal['grand_champion_number']),
      AnimalDetailRow(title: 'Legs', value: animal['legs']),
      if ((animal['leg_details'] ?? '').toString().isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SelectableText(
            'Legs / show details\n${animal['leg_details']}',
            key: const PageStorageKey('animal-leg-text'),
          ),
        ),
    ];
    return ListView(
      padding: BreederLayout.pagePadding(context, normal: 16),
      children: [
        if (compact)
          Row(
            children: [
              AnimalAvatar(
                species: animal['species'],
                photoUrl: animal['photo_url'],
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (onPhoto != null)
                IconButton(
                  tooltip: photoLabel,
                  onPressed: uploadingPhoto ? null : onPhoto,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
            ],
          )
        else ...[
          Center(
            child: AnimalAvatar(
              species: animal['species'],
              photoUrl: animal['photo_url'],
              size: 112,
            ),
          ),
          if (onPhoto != null)
            Center(
              child: TextButton.icon(
                onPressed: uploadingPhoto ? null : onPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(photoLabel),
              ),
            ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ],
        const AdaptiveGap(height: 16),
        if (lockMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              lockMessage!,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (compact && actions.isNotEmpty) ...[
          actions.first,
          const SizedBox(height: 12),
        ],
        if (compact)
          LayoutBuilder(
            builder: (context, constraints) {
              // Large accessibility text gets a single column rather than clipping.
              final columns =
                  constraints.maxWidth >= 280 &&
                      MediaQuery.textScalerOf(context).scale(14) <= 20
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  for (final (label, value) in basic)
                    SizedBox(
                      width: width,
                      child: Semantics(
                        label: '$label: ${value ?? '-'}',
                        excludeSemantics: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              '${value ?? '-'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          )
        else
          for (final (label, value) in basic)
            AnimalDetailRow(title: label, value: value),
        const AdaptiveGap(height: 16),
        if (compact) ...[
          ExpansionTile(
            key: const PageStorageKey('animal-registration'),
            title: const Text('Registration & show details'),
            children: registration,
          ),
          ExpansionTile(
            key: const PageStorageKey('animal-parents'),
            title: const Text('Parents'),
            children: parents,
          ),
        ] else ...[
          ...registration,
          const SizedBox(height: 24),
          ...parents,
        ],
        const AdaptiveGap(height: 24),
        // One column lets action labels grow with system text settings. It also
        // keeps every action discoverable without another menu on this page.
        for (final action in compact ? actions.skip(1) : actions) ...[
          action,
          const AdaptiveGap(height: 12),
        ],
      ],
    );
  }
}
