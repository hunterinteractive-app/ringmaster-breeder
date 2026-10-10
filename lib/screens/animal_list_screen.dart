import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import '../services/animal_service.dart';
import '../utils/animal_labels.dart';

class AnimalListScreen extends StatefulWidget {
  final String ringId;
  final String ringName;

  const AnimalListScreen({
    super.key,
    required this.ringId,
    required this.ringName,
  });

  @override
  State<AnimalListScreen> createState() => _AnimalListScreenState();
}

class _AnimalListScreenState extends State<AnimalListScreen> {
  late Future<List<Map<String, dynamic>>> _animals;
  @override
  void initState() {
    super.initState();
    _animals = AnimalService.list(widget.ringId);
  }

  void _refresh() {
    setState(() => _animals = AnimalService.list(widget.ringId));
  }

  String sexAbbreviation(String species, String sex) {
    final s = species.toLowerCase();
    final x = sex.toUpperCase();

    if (s == 'rabbit') {
      return animalIsMale(sex) ? 'B' : 'D'; // Buck / Doe
    }

    if (s == 'cavy') {
      return animalIsMale(sex) ? 'B' : 'S'; // Boar / Sow
    }

    return x; // fallback
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: widget.ringName,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final added = await Navigator.pushNamed(
            context,
            '/add-animal',
            arguments: {'ringId': widget.ringId, 'ringName': widget.ringName},
          );

          if (added == true && mounted) {
            _refresh();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder(
        future: _animals,
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

          final animals = snapshot.data as List;

          if (animals.isEmpty) {
            return const Center(child: Text('No animals yet'));
          }

          return ListView.builder(
            itemCount: animals.length,
            itemBuilder: (context, index) {
              final animal = animals[index];

              return ListTile(
                title: Text(animalTitle(animal['name'], animal['tattoo'])),
                subtitle: Text(
                  '${animal['species']} • ${sexLabel(animal['species'], animal['sex'])} • ${animal['status']}',
                ),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () async {
                  await Navigator.pushNamed(
                    context,
                    '/animal-detail',
                    arguments: animal['id'],
                  );
                  if (mounted) _refresh();
                },
              );
            },
          );
        },
      ),
    );
  }
}
