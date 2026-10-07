import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class PedigreeTreeScreen extends StatefulWidget {
  final String animalId;

  const PedigreeTreeScreen({super.key, required this.animalId});

  @override
  State<PedigreeTreeScreen> createState() => _PedigreeTreeScreenState();
}

class _PedigreeTreeScreenState extends State<PedigreeTreeScreen> {
  final supabase = Supabase.instance.client;

  /// Store appearance count of each ancestor
  final Map<String, int> _ancestorCounts = {};

  /// Fetch animal safely
  Future<Map<String, dynamic>?> fetchAnimal(String? id) async {
    if (id == null) return null;

    final res = await supabase
        .from('animals')
        .select(
          'id, name, tattoo, sex, sire_id, dam_id, registration_number',
        )
        .eq('id', id)
        .maybeSingle();

    if (res != null) {
      _ancestorCounts[id] = (_ancestorCounts[id] ?? 0) + 1;
    }

    return res;
  }

  bool isLineBred(String id) {
    return (_ancestorCounts[id] ?? 0) > 1;
  }

  /// Animal card with line-breeding highlight
  Widget animalCard(Map<String, dynamic>? animal, String label) {
    if (animal == null) {
      return Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '$label\nUnknown',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final bool lineBred = isLineBred(animal['id']);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        Navigator.pushNamed(
          context,
          '/animal-detail',
          arguments: animal['id'],
        );
      },
      child: Card(
        elevation: lineBred ? 4 : 2,
        color: lineBred ? Colors.red.shade50 : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                animal['name'] ?? 'Unnamed',
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              if ((animal['tattoo'] ?? '').toString().isNotEmpty)
                Text(
                  animal['tattoo'],
                  style: const TextStyle(fontSize: 12),
                ),
              if ((animal['registration_number'] ?? '')
                  .toString()
                  .isNotEmpty)
                Text(
                  'Reg: ${animal['registration_number']}',
                  style: const TextStyle(fontSize: 11),
                ),
              if (lineBred)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Chip(
                    label: Text(
                      'Line-bred',
                      style: TextStyle(fontSize: 11),
                    ),
                    backgroundColor: Color(0xFFFFCDD2),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget connector({double height = 24}) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _ConnectorPainter(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ancestorCounts.clear(); // reset per render

    return Scaffold(
      appBar: AppBar(title: const Text('Pedigree')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: fetchAnimal(widget.animalId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final animal = snapshot.data!;
          final sireId = animal['sire_id'];
          final damId = animal['dam_id'];

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                Center(child: animalCard(animal, 'Animal')),
                connector(),

                /// Parents
                Row(
                  children: [
                    Expanded(
                      child: FutureBuilder(
                        future: fetchAnimal(sireId),
                        builder: (c, s) =>
                            animalCard(s.data, 'Sire'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FutureBuilder(
                        future: fetchAnimal(damId),
                        builder: (c, s) =>
                            animalCard(s.data, 'Dam'),
                      ),
                    ),
                  ],
                ),

                connector(height: 32),

                /// Grandparents
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          FutureBuilder(
                            future: fetchAnimal(sireId),
                            builder: (c, s) {
                              final sire = s.data;
                              return Column(
                                children: [
                                  FutureBuilder(
                                    future:
                                        fetchAnimal(sire?['sire_id']),
                                    builder: (c, g) =>
                                        animalCard(
                                            g.data, 'Sire’s Sire'),
                                  ),
                                  const SizedBox(height: 12),
                                  FutureBuilder(
                                    future:
                                        fetchAnimal(sire?['dam_id']),
                                    builder: (c, g) =>
                                        animalCard(
                                            g.data, 'Sire’s Dam'),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          FutureBuilder(
                            future: fetchAnimal(damId),
                            builder: (c, s) {
                              final dam = s.data;
                              return Column(
                                children: [
                                  FutureBuilder(
                                    future:
                                        fetchAnimal(dam?['sire_id']),
                                    builder: (c, g) =>
                                        animalCard(
                                            g.data, 'Dam’s Sire'),
                                  ),
                                  const SizedBox(height: 12),
                                  FutureBuilder(
                                    future:
                                        fetchAnimal(dam?['dam_id']),
                                    builder: (c, g) =>
                                        animalCard(
                                            g.data, 'Dam’s Dam'),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Connector painter
class _ConnectorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}