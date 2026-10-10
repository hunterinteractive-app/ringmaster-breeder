import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import '../services/animal_service.dart';
import '../widgets/color_details_fields.dart';
import '../utils/color_details.dart';

class EditAnimalScreen extends StatefulWidget {
  final String animalId;

  const EditAnimalScreen({super.key, required this.animalId});

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

  Map<String, String> details = {};
  String species = '';
  String sex = 'Buck';
  String status = 'active';

  bool isSaving = false;
  bool isLoaded = false;
  bool loadFailed = false;

  Future<void> loadAnimal() async {
    final animal = await AnimalService.get(widget.animalId);
    if (!mounted) return;

    nameController.text = animal['name'] ?? '';
    tattooController.text = animal['tattoo'] ?? '';
    breedController.text = animal['breed'] ?? '';
    varietyController.text = animal['variety'] ?? '';
    registrationController.text = animal['registration_number'] ?? '';
    gcController.text = animal['grand_champion_number'] ?? '';

    details = colorDetails(animal);
    species = animal['species'].toString().toLowerCase(); // rabbit / cavy
    sex = animal['sex']; // Buck/Doe or Boar/Sow
    status = animal['status'];

    setState(() => isLoaded = true);
  }

  Future<void> saveChanges() async {
    if (isSaving) return;
    setState(() => isSaving = true);

    try {
      final detailError = codDetailsError(
        breedController.text,
        varietyController.text,
        details,
      );
      if (detailError != null) throw Exception(detailError);
      await AnimalService.update(widget.animalId, {
        'name': nameController.text.trim(),
        'color_details': details,
        'status': status,
        'tattoo': tattooController.text.trim(),
        'sex': sex,
        'registration_number': registrationController.text.trim(),
        'grand_champion_number': gcController.text.trim(),
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
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

  List<DropdownMenuItem<String>> getSexItems() {
    if (species == 'cavy') {
      return const [
        DropdownMenuItem(value: 'Boar', child: Text('Boar')),
        DropdownMenuItem(value: 'Sow', child: Text('Sow')),
      ];
    }
    return const [
      DropdownMenuItem(value: 'Buck', child: Text('Buck')),
      DropdownMenuItem(value: 'Doe', child: Text('Doe')),
    ];
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // NAME
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),

            const SizedBox(height: 12),

            // STATUS
            DropdownButtonFormField<String>(
              initialValue: status,
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'sold', child: Text('Sold')),
                DropdownMenuItem(value: 'retired', child: Text('Retired')),
                DropdownMenuItem(value: 'deceased', child: Text('Deceased')),
              ],
              onChanged: (v) => setState(() => status = v!),
              decoration: const InputDecoration(labelText: 'Status'),
            ),

            const SizedBox(height: 12),

            // SPECIES (LOCKED)
            TextField(
              enabled: false,
              decoration: InputDecoration(
                labelText: 'Species',
                hintText: displaySpecies(),
              ),
            ),

            const SizedBox(height: 12),

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

            const SizedBox(height: 12),

            ColorDetailsFields(
              breed: breedController.text,
              variety: varietyController.text,
              value: details,
              onChanged: (v) => setState(() => details = v),
            ),

            // SEX
            DropdownButtonFormField<String>(
              initialValue: sex,
              items: getSexItems(),
              onChanged: (v) => setState(() => sex = v!),
              decoration: const InputDecoration(labelText: 'Sex'),
            ),

            const SizedBox(height: 12),

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

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: isSaving ? null : saveChanges,
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
