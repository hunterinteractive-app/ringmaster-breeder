

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final supabase = Supabase.instance.client;

  Future<List> fetchAnimals() async {
    return await supabase
        .from('animals')
        .select()
        .eq('ring_id', widget.ringId)
        .order('created_at');
  }

String sexAbbreviation(String species, String sex) {
  final s = species.toLowerCase();
  final x = sex.toUpperCase();

  if (s == 'rabbit') {
    return x == 'M' ? 'B' : 'D'; // Buck / Doe
  }

  if (s == 'cavy') {
    return x == 'M' ? 'B' : 'S'; // Boar / Sow
  }

  return x; // fallback
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.ringName)),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final added = await Navigator.pushNamed(
            context,
            '/add-animal',
            arguments: {
              'ringId': widget.ringId,
              'ringName': widget.ringName,
            },
          );

          if (added == true) {
            setState(() {});
          }
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder(
        future: fetchAnimals(),
        builder: (context, snapshot) {
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
                title: Text(animal['name'] ?? 'Unnamed'),
                subtitle: Text(
                  '${animal['species']} • ${sexAbbreviation(
                    animal['species'],
                    animal['sex'],
                  )} • ${animal['status']}',
                ),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/animal-detail',
                    arguments: animal['id'],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}