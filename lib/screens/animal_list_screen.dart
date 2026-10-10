import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import '../services/animal_service.dart';
import '../utils/animal_labels.dart';
import '../theme/app_theme.dart';

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

          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 4
                  : constraints.maxWidth >= 750
                  ? 3
                  : constraints.maxWidth >= 500
                  ? 2
                  : 1;
              final cardWidth =
                  (constraints.maxWidth - 40 - (columns - 1) * 16) / columns;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: animals
                      .map<Widget>(
                        (animal) => SizedBox(
                          width: cardWidth,
                          child: AnimalRecordCard(
                            animal: Map<String, dynamic>.from(animal),
                            onTap: () async {
                              await Navigator.pushNamed(
                                context,
                                '/animal-detail',
                                arguments: animal['id'],
                              );
                              if (mounted) _refresh();
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AnimalRecordCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final VoidCallback onTap;
  const AnimalRecordCard({
    super.key,
    required this.animal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final species = animal['species'] == 'cavy' ? 'Cavy' : 'Rabbit';
    final status = (animal['status'] as String? ?? 'active');
    final title = animalTitle(animal['name'], animal['tattoo']);
    String recorded(String key) =>
        (animal[key] as String?)?.trim().isNotEmpty == true
        ? animal[key]
        : 'Not recorded';
    Widget detail(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 65,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF677085), fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: BreederColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shadowColor: BreederColors.text.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFDDE0E3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: BreederColors.primary,
                  child: const Icon(
                    Icons.pets_outlined,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: status == 'active'
                        ? const Color(0xFFE1F2E8)
                        : const Color(0xFFEEF0F3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.isEmpty
                        ? 'Unknown'
                        : '${status[0].toUpperCase()}${status.substring(1)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: status == 'active'
                          ? const Color(0xFF246345)
                          : BreederColors.text,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: BreederColors.text,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              detail('Species', species),
              detail('Breed', recorded('breed')),
              detail('Variety', recorded('variety')),
              detail(
                'Sex',
                sexLabel(animal['species'] ?? 'rabbit', animal['sex'] ?? ''),
              ),
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'View details',
                    style: TextStyle(
                      color: BreederColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: BreederColors.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
