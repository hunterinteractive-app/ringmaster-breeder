import '../widgets/adaptive_layout.dart';
import '../widgets/pedigree_email_dialog.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import '../services/animal_service.dart';
import '../offline/offline_runtime.dart';
import '../offline/offline_store.dart';
import '../offline/sync_engine.dart';
import '../widgets/color_details_fields.dart';
import '../utils/color_details.dart';
import '../widgets/dob_field.dart';
import '../widgets/sex_field.dart';

class EditAnimalScreen extends StatefulWidget {
  final String animalId;
  final Future<Map<String, dynamic>> Function(String)? loader;
  final Future<void> Function(String, Map<String, dynamic>, int)? writer;

  const EditAnimalScreen({
    super.key,
    required this.animalId,
    this.loader,
    this.writer,
  });

  @override
  State<EditAnimalScreen> createState() => _EditAnimalScreenState();
}

class _EditAnimalScreenState extends State<EditAnimalScreen> {
  final nameController = TextEditingController();
  final tattooController = TextEditingController();
  final breedController = TextEditingController();
  final varietyController = TextEditingController();
  final registrationController = TextEditingController();
  final gcController = TextEditingController();
  final legDetailsController = TextEditingController();

  Map<String, String> details = {};
  String dob = '';
  String species = '';
  String sex = 'Buck';
  String status = 'active';
  String originalStatus = 'active';

  int revision = 0;
  Map<String, dynamic>? loadedAnimal;
  bool conflicted = false;
  bool isSaving = false;
  bool isLoaded = false;
  bool loadFailed = false;

  Future<void> loadAnimal() async {
    final animal = await (widget.loader ?? AnimalService.get)(widget.animalId);
    if (!mounted) return;
    loadedAnimal = copyJson(animal);

    nameController.text = animal['name'] ?? '';
    tattooController.text = animal['tattoo'] ?? '';
    breedController.text = animal['breed'] ?? '';
    varietyController.text = animal['variety'] ?? '';
    registrationController.text = animal['registration_number'] ?? '';
    gcController.text = animal['grand_champion_number'] ?? '';
    legDetailsController.text = animal['leg_details'] ?? '';

    details = colorDetails(animal);
    dob = animal['dob']?.toString() ?? '';
    species = animal['species'].toString().toLowerCase(); // rabbit / cavy
    sex = animal['sex']; // Buck/Doe or Boar/Sow
    status = animal['status'];
    originalStatus = status;

    revision = (animal['revision'] as num).toInt();
    setState(() {
      isLoaded = true;
      conflicted = false;
    });
  }

  Future<void> saveChanges() async {
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
      final changes = <String, dynamic>{
        'name': nameController.text.trim(),
        'color_details': details,
        'dob': dob.isEmpty ? null : dob,
        'status': status,
        'tattoo': tattooController.text.trim(),
        'sex': sex,
        'registration_number': registrationController.text.trim(),
        'grand_champion_number': gcController.text.trim(),
        'leg_details': legDetailsController.text,
      };
      if (widget.writer != null) {
        await widget.writer!(widget.animalId, changes, revision);
      } else {
        if (OfflineRuntime.engine != null && loadedAnimal != null) {
          changes.removeWhere(
            (key, value) => const DeepCollectionEquality().equals(
              loadedAnimal![key],
              value,
            ),
          );
        }
        await AnimalService.update(
          widget.animalId,
          changes,
          expectedRevision: revision,
          expectedBase: loadedAnimal,
        );
      }

      if (mounted && OfflineRuntime.engine != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Saved on this device. Open Sync to check upload status.',
            ),
          ),
        );
      }
      if (mounted &&
          OfflineRuntime.engine == null &&
          status == 'sold' &&
          originalStatus != 'sold') {
        await offerBuyerPedigree(context, animalId: widget.animalId);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      if (e is AnimalEditConflict) setState(() => conflicted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  String displaySpecies() {
    if (species == 'rabbit') return 'Rabbit';
    if (species == 'cavy') return 'Cavy';
    return species;
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
      legDetailsController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    loadAnimal().catchError((Object error) {
      if (mounted) setState(() => loadFailed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loadFailed) {
      return RingMasterPageShell(
        title: "Edit Animal",
        body: const Center(child: Text("Unable to load animal.")),
      );
    }
    if (!isLoaded) {
      return const RingMasterPageShell(
        title: 'Edit Animal',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return RingMasterPageShell(
      title: 'Edit Animal',
      bodyMaxWidth: 720,
      body: AdaptivePadding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            if (conflicted)
              Card(
                child: AdaptivePadding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This animal changed since you opened it. Your edits are still shown. Reload the latest record before saving.',
                      ),
                      TextButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                setState(() => isSaving = true);
                                try {
                                  await loadAnimal();
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Unable to reload. Your edits are still here.',
                                        ),
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => isSaving = false);
                                }
                              },
                        child: const Text('Reload latest record'),
                      ),
                    ],
                  ),
                ),
              ),
            // NAME
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),

            const AdaptiveGap(height: 12),

            // STATUS
            DropdownButtonFormField<String>(
              initialValue: status,
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'sold', child: Text('Sold')),
                DropdownMenuItem(value: 'retired', child: Text('Retired')),
                DropdownMenuItem(value: 'archived', child: Text('Archived')),
                DropdownMenuItem(value: 'deceased', child: Text('Deceased')),
              ],
              onChanged: (v) => setState(() => status = v!),
              decoration: const InputDecoration(labelText: 'Status'),
            ),

            const AdaptiveGap(height: 12),

            // SPECIES (LOCKED)
            TextField(
              enabled: false,
              decoration: InputDecoration(
                labelText: 'Species',
                hintText: displaySpecies(),
              ),
            ),

            const AdaptiveGap(height: 12),

            // BREED (LOCKED)
            TextField(
              controller: breedController,
              enabled: false,
              decoration: const InputDecoration(labelText: 'Breed'),
            ),

            // VARIETY (LOCKED)
            TextField(
              controller: varietyController,
              enabled: false,
              decoration: const InputDecoration(labelText: 'Variety'),
            ),

            const AdaptiveGap(height: 12),

            ColorDetailsFields(
              breed: breedController.text,
              variety: varietyController.text,
              value: details,
              onChanged: (v) => setState(() => details = v),
            ),

            SexField(
              species: species,
              value: sex,
              onChanged: (v) => setState(() => sex = v),
            ),
            const AdaptiveGap(height: 12),
            DobField(value: dob, onChanged: (v) => dob = v),
            const AdaptiveGap(height: 12),

            // TATTOO
            TextField(
              controller: tattooController,
              decoration: const InputDecoration(labelText: 'Tattoo'),
            ),

            // REGISTRATION
            TextField(
              controller: registrationController,
              decoration: const InputDecoration(
                labelText: 'Registration Number',
              ),
            ),

            // GRAND CHAMPION
            TextField(
              controller: gcController,
              decoration: const InputDecoration(
                labelText: 'Grand Champion Number',
              ),
            ),
            TextField(
              controller: legDetailsController,
              minLines: BreederLayout.fieldLines(context, 4),
              maxLines: BreederLayout.fieldLines(context, 8),
              maxLength: 4000,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                counterText: BreederLayout.shortViewport(context) ? '' : null,
                labelText: 'Legs / show details',
                hintText: 'Type or paste results, one per line.',
              ),
            ),

            const AdaptiveGap(height: 24),

            ElevatedButton(
              onPressed: isSaving || conflicted ? null : saveChanges,
              child: isSaving
                  ? const CircularProgressIndicator()
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
