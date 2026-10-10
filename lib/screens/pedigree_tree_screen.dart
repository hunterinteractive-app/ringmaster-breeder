import '../utils/color_details.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import '../services/pedigree_service.dart';
import '../utils/pedigree_counts.dart';

class PedigreeTreeScreen extends StatefulWidget {
  final String animalId;
  const PedigreeTreeScreen({super.key, required this.animalId});
  @override
  State<PedigreeTreeScreen> createState() => _PedigreeTreeScreenState();
}

class _PedigreeTreeScreenState extends State<PedigreeTreeScreen> {
  late final Future<Map<String, dynamic>> _pedigree;
  @override
  void initState() {
    super.initState();
    _pedigree = PedigreeService.build(widget.animalId);
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Pedigree',
    body: FutureBuilder<Map<String, dynamic>>(
      future: _pedigree,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Unable to load pedigree.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final pedigree = snapshot.data!;
        final counts = pedigreeCounts(pedigree);
        const generations = [
          ['animal'],
          ['sire', 'dam'],
          ['sire_sire', 'sire_dam', 'dam_sire', 'dam_dam'],
          ['gg1', 'gg2', 'gg3', 'gg4', 'gg5', 'gg6', 'gg7', 'gg8'],
        ];
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: generations
                    .asMap()
                    .entries
                    .map(
                      (generation) => SizedBox(
                        width: 250,
                        child: Column(
                          children: [
                            Text(
                              generation.key == 0
                                  ? 'Animal'
                                  : 'Generation ${generation.key}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            ...generation.value.map((slot) {
                              final animal =
                                  pedigree[slot] as Map<String, dynamic>?;
                              final repeated =
                                  animal != null &&
                                  (counts[animal['id']] ?? 0) > 1;
                              return Card(
                                child: ListTile(
                                  title: Text(animal?['name'] ?? 'Unknown'),
                                  subtitle: Text(
                                    [
                                          animal?['tattoo'],
                                          animal?['breed'],
                                          if (animal != null)
                                            varietyLabel(animal),
                                          if (repeated) 'Repeated ancestor',
                                        ]
                                        .whereType<String>()
                                        .where((v) => v.isNotEmpty)
                                        .join(' • '),
                                  ),
                                  onTap: animal == null
                                      ? null
                                      : () => Navigator.pushNamed(
                                          context,
                                          '/animal-detail',
                                          arguments: animal['id'],
                                        ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        );
      },
    ),
  );
}
