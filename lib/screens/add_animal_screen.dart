import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/breed_service.dart';
import 'pedigree_entry_screen.dart';
import '../services/variety_service.dart';

class AddAnimalScreen extends StatefulWidget {
  final String ringId;
  final String ringName;

  const AddAnimalScreen({
    super.key,
    required this.ringId,
    required this.ringName,
  });

  @override
  State<AddAnimalScreen> createState() => _AddAnimalScreenState();
}

class _AddAnimalScreenState extends State<AddAnimalScreen> {
  final supabase = Supabase.instance.client;

  final nameController = TextEditingController();
  final tattooController = TextEditingController();
  final breedController = TextEditingController();
  final varietyController = TextEditingController();
  final registrationController = TextEditingController();
  final gcController = TextEditingController();
  final weightController = TextEditingController();

  DateTime? dob;

  String species = 'rabbit';
  String sex = 'Buck';
  String status = 'active';

  String? sireId;
  String? damId;

  bool sireUnknown = false;
  bool damUnknown = false;
  bool isSaving = false;
  String _lastBreedForVariety = '';

  String sexLabel(String value) {
    if (species == 'rabbit') {
      return value == 'M' ? 'Buck' : 'Doe';
    }
    return value == 'M' ? 'Boar' : 'Sow';
  }

  /// 🔹 Fetch potential parents
  Future<List<Map<String, dynamic>>> fetchParents(String sexFilter) async {
    final res = await supabase
        .from('animals')
        .select('id, name, tattoo')
        .eq('ring_id', widget.ringId)
        .eq('species', species)
        .eq('sex', sexLabel(sexFilter))
        .neq('status', 'deceased')
        .order('name');

    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dob ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => dob = picked);
    }
  }

  Future<void> saveAnimal() async {
    if (isSaving) return;
    setState(() => isSaving = true);

    try {
      double? parsedWeight;
      if (weightController.text.trim().isNotEmpty) {
        parsedWeight = double.tryParse(weightController.text.trim());
        if (parsedWeight == null ||
            !parsedWeight.isFinite ||
            parsedWeight <= 0) {
          throw Exception('Weight must be a positive number');
        }
      }

      final response = await supabase.rpc(
        'create_animal_with_weight',
        params: {
          'p_ring_id': widget.ringId,
          'p_name': nameController.text.trim(),
          'p_tattoo': tattooController.text.trim(),
          'p_species': species,
          'p_breed': breedController.text.trim(),
          'p_variety': varietyController.text.trim(),
          'p_sex': sex,
          'p_status': status,
          'p_dob': dob?.toIso8601String(),
          'p_registration': registrationController.text.trim(),
          'p_gc': gcController.text.trim(),
          'p_weight': parsedWeight,
          'p_sire_id': sireId,
          'p_dam_id': damId,
        },
      );

      if (response == null) {
        throw Exception('Insert failed');
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save Failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      nameController,
      tattooController,
      breedController,
      varietyController,
      registrationController,
      gcController,
      weightController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'Add Animal',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Have a full pedigree?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Enter three generations, reuse ancestors, or resume a saved draft.',
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        final saved = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PedigreeEntryScreen(ringId: widget.ringId),
                          ),
                        );
                        if (saved == true && context.mounted) {
                          Navigator.pop(context, true);
                        }
                      },
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('Enter full pedigree'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            /// NAME
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),

            /// EAR / TATTOO
            TextField(
              controller: tattooController,
              decoration: const InputDecoration(labelText: 'Ear / Tattoo #'),
            ),

            const SizedBox(height: 12),

            /// SPECIES
            DropdownButtonFormField<String>(
              initialValue: species,
              items: const [
                DropdownMenuItem(value: 'rabbit', child: Text('Rabbit')),
                DropdownMenuItem(value: 'cavy', child: Text('Cavy')),
              ],
              onChanged: (v) {
                setState(() {
                  final male = sex == 'Buck' || sex == 'Boar';
                  species = v!;
                  sex = species == 'rabbit'
                      ? (male ? 'Buck' : 'Doe')
                      : (male ? 'Boar' : 'Sow');
                  breedController.clear();
                  varietyController.clear();
                  sireId = null;
                  damId = null;
                });
              },
              decoration: const InputDecoration(labelText: 'Species'),
            ),

            const SizedBox(height: 12),

            /// BREED
            FutureBuilder<List<String>>(
              future: BreedService.fetchBreeds(species.toLowerCase()),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      "Unable to load records. Please go back and try again.",
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }

                final breeds = [...snapshot.data!]..sort();

                return Autocomplete<String>(
                  optionsBuilder: (value) {
                    if (value.text.isEmpty) return breeds;
                    return breeds.where(
                      (b) => b.toLowerCase().contains(value.text.toLowerCase()),
                    );
                  },
                  onSelected: (v) {
                    setState(() {
                      breedController.text = v;
                      varietyController.clear();
                      _lastBreedForVariety = v;
                    });
                  },
                  fieldViewBuilder: (context, controller, focusNode, _) {
                    controller.text = breedController.text;
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: (v) {
                        breedController.text = v;
                        if (v != _lastBreedForVariety) {
                          varietyController.clear();
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Breed'),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 12),

            /// VARIETY
            FutureBuilder<List<String>>(
              future: VarietyService.fetchVarieties(
                breedName: breedController.text,
                species: species,
              ),
              builder: (context, snapshot) {
                final varieties = snapshot.data ?? [];

                return Autocomplete<String>(
                  optionsBuilder: (value) {
                    if (value.text.isEmpty) return varieties;
                    return varieties.where(
                      (v) => v.toLowerCase().contains(value.text.toLowerCase()),
                    );
                  },
                  onSelected: (v) => varietyController.text = v,
                  fieldViewBuilder: (context, controller, focusNode, _) {
                    controller.text = varietyController.text;
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: (v) => varietyController.text = v,
                      decoration: const InputDecoration(labelText: 'Variety'),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 12),

            /// SEX
            DropdownButtonFormField<String>(
              key: ValueKey(species),
              initialValue: sex,
              items: [
                DropdownMenuItem(
                  value: sexLabel('M'),
                  child: Text(sexLabel('M')),
                ),
                DropdownMenuItem(
                  value: sexLabel('F'),
                  child: Text(sexLabel('F')),
                ),
              ],
              onChanged: (v) => setState(() => sex = v!),
              decoration: const InputDecoration(labelText: 'Sex'),
            ),

            const SizedBox(height: 12),

            /// DOB
            ListTile(
              title: const Text('Date of Birth'),
              subtitle: Text(
                dob == null
                    ? 'Not set'
                    : '${dob!.month}/${dob!.day}/${dob!.year}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: pickDob,
            ),

            const Divider(),

            /// 🔹 SIRE (AUTOCOMPLETE)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  title: const Text('Unknown'),
                  value: sireUnknown,
                  onChanged: (v) {
                    setState(() {
                      sireUnknown = v!;
                      if (sireUnknown) sireId = null;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),

                if (!sireUnknown)
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: fetchParents('M'),
                    builder: (context, snapshot) {
                      final list = snapshot.data ?? [];

                      return DropdownButtonFormField<String>(
                        initialValue: sireId,
                        items: list
                            .map<DropdownMenuItem<String>>(
                              (a) => DropdownMenuItem<String>(
                                value: a['id'],
                                child: Text('${a['name']} (${a['tattoo']})'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => sireId = v),
                        decoration: const InputDecoration(labelText: 'Sire'),
                      );
                    },
                  ),
              ],
            ),

            /// 🔹 DAM (AUTOCOMPLETE)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  title: const Text('Unknown'),
                  value: damUnknown,
                  onChanged: (v) {
                    setState(() {
                      damUnknown = v!;
                      if (damUnknown) damId = null;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),

                if (!damUnknown)
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: fetchParents('F'),
                    builder: (context, snapshot) {
                      final list = snapshot.data ?? [];

                      return DropdownButtonFormField<String>(
                        initialValue: damId,
                        items: list
                            .map<DropdownMenuItem<String>>(
                              (a) => DropdownMenuItem<String>(
                                value: a['id'],
                                child: Text('${a['name']} (${a['tattoo']})'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => damId = v),
                        decoration: const InputDecoration(labelText: 'Dam'),
                      );
                    },
                  ),
              ],
            ),

            const SizedBox(height: 12),

            TextField(
              controller: registrationController,
              decoration: const InputDecoration(
                labelText: 'Registration Number',
              ),
            ),

            TextField(
              controller: gcController,
              decoration: const InputDecoration(
                labelText: 'Grand Champion Number',
              ),
            ),

            TextField(
              controller: weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Current Weight'),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: isSaving ? null : saveAnimal,
              child: isSaving
                  ? const CircularProgressIndicator()
                  : const Text('Save Animal'),
            ),
          ],
        ),
      ),
    );
  }
}
