import '../widgets/parent_picker.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/catalog_field.dart';
import '../widgets/color_details_fields.dart';
import '../utils/color_details.dart';
import 'pedigree_entry_screen.dart';
import '../widgets/dob_field.dart';
import '../widgets/sex_field.dart';

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

  String dob = '';
  Map<String, String> details = {};

  String species = 'rabbit';
  String sex = 'Buck';
  String status = 'active';

  Map<String, dynamic>? sire, dam;
  String? quickDraftId;
  bool isSaving = false;

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
        .select('id, name, tattoo, status, pedigree_only')
        .eq('ring_id', widget.ringId)
        .eq('species', species)
        .eq('sex', sexLabel(sexFilter))
        .order('name');

    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> saveAnimal() async {
    if (isSaving) return;
    setState(() => isSaving = true);

    try {
      final dateError = dobError(dob);
      if (dateError != null) throw Exception(dateError);
      final detailError = codDetailsError(
        breedController.text,
        varietyController.text,
        details,
      );
      if (detailError != null) throw Exception(detailError);
      double? parsedWeight;
      if (weightController.text.trim().isNotEmpty) {
        parsedWeight = double.tryParse(weightController.text.trim());
        if (parsedWeight == null ||
            !parsedWeight.isFinite ||
            parsedWeight <= 0) {
          throw Exception('Weight must be a positive number');
        }
      }

      dynamic response;
      if (sire != null && sire!['existing_id'] == null ||
          dam != null && dam!['existing_id'] == null ||
          quickDraftId != null) {
        final data = {
          'species': species,
          'root': 'animal',
          'nodes': {
            'animal': {
              'name': nameController.text.trim(),
              'tattoo': tattooController.text.trim(),
              'breed': breedController.text.trim(),
              'variety': varietyController.text.trim(),
              'color_details': details,
              'sex': sex,
              'dob': dob,
              'registration_number': registrationController.text.trim(),
              'grand_champion_number': gcController.text.trim(),
              'weight': parsedWeight,
              if (sire != null) 'sire': 'sire',
              if (dam != null) 'dam': 'dam',
            },
            if (sire != null) 'sire': sire,
            if (dam != null) 'dam': dam,
          },
        };
        if (quickDraftId == null) {
          final row = await supabase
              .from('pedigree_drafts')
              .insert({'ring_id': widget.ringId, 'data': data})
              .select('id')
              .single();
          quickDraftId = row['id'];
        } else {
          await supabase
              .from('pedigree_drafts')
              .update({'data': data})
              .eq('id', quickDraftId!);
        }
        response = await supabase.rpc(
          'save_pedigree_draft',
          params: {'p_draft': quickDraftId},
        );
      } else {
        response = await supabase.rpc(
          'create_animal_with_color_details',
          params: {
            'p_ring_id': widget.ringId,
            'p_name': nameController.text.trim(),
            'p_tattoo': tattooController.text.trim(),
            'p_species': species,
            'p_breed': breedController.text.trim(),
            'p_variety': varietyController.text.trim(),
            'p_color_details': details,
            'p_sex': sex,
            'p_status': status,
            'p_dob': dob.isEmpty ? null : dob,
            'p_registration': registrationController.text.trim(),
            'p_gc': gcController.text.trim(),
            'p_weight': parsedWeight,
            'p_sire_id': sire?['existing_id'],
            'p_dam_id': dam?['existing_id'],
          },
        );
      }

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
                  details = {};
                  sire = null;
                  dam = null;
                });
              },
              decoration: const InputDecoration(labelText: 'Species'),
            ),

            const SizedBox(height: 12),

            CatalogField(
              key: ValueKey('breed:$species'),
              species: species,
              value: breedController.text,
              onChanged: (v) => setState(() {
                breedController.text = v;
                varietyController.clear();
                details = {};
              }),
            ),
            const SizedBox(height: 12),
            CatalogField(
              key: ValueKey('variety:$species:${breedController.text}'),
              species: species,
              breed: breedController.text,
              value: varietyController.text,
              onChanged: (v) => setState(() {
                varietyController.text = v;
                details = {};
              }),
            ),
            const SizedBox(height: 12),

            ColorDetailsFields(
              key: ValueKey(
                'details:$species:${breedController.text}:${varietyController.text}',
              ),
              breed: breedController.text,
              variety: varietyController.text,
              value: details,
              onChanged: (v) => setState(() => details = v),
            ),

            SexField(
              key: ValueKey('sex:$species'),
              species: species,
              value: sex,
              onChanged: (v) => setState(() => sex = v),
            ),
            const SizedBox(height: 12),
            DobField(value: dob, onChanged: (v) => dob = v),

            const Divider(),

            ParentPicker(
              key: ValueKey('sire:$species'),
              label: 'Sire',
              species: species,
              sex: sexLabel('M'),
              breed: breedController.text,
              loadParents: () => fetchParents('M'),
              onChanged: (v) => setState(() => sire = v),
            ),
            ParentPicker(
              key: ValueKey('dam:$species'),
              label: 'Dam',
              species: species,
              sex: sexLabel('F'),
              breed: breedController.text,
              loadParents: () => fetchParents('F'),
              onChanged: (v) => setState(() => dam = v),
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
