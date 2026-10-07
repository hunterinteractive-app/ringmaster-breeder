import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditAnimalScreen extends StatefulWidget {
  final String animalId;

  const EditAnimalScreen({super.key, required this.animalId});

  @override
  State<EditAnimalScreen> createState() => _EditAnimalScreenState();
}

class _EditAnimalScreenState extends State<EditAnimalScreen> {
  final supabase = Supabase.instance.client;

  final nameController = TextEditingController();
  final tattooController = TextEditingController();
  final breedController = TextEditingController();
  final varietyController = TextEditingController();
  final registrationController = TextEditingController();
  final gcController = TextEditingController();

  String species = '';
  String sex = 'M';
  String status = 'active';

  bool isSaving = false;
  bool isLoaded = false;

  Future<void> loadAnimal() async {
    final animal = await supabase
        .from('animals')
        .select()
        .eq('id', widget.animalId)
        .single();

    nameController.text = animal['name'] ?? '';
    tattooController.text = animal['tattoo'] ?? '';
    breedController.text = animal['breed'] ?? '';
    varietyController.text = animal['variety'] ?? '';
    registrationController.text = animal['registration_number'] ?? '';
    gcController.text = animal['grand_champion_number'] ?? '';

    species = animal['species']; // rabbit / cavy
    sex = animal['sex'];         // M / F
    status = animal['status'];

    setState(() => isLoaded = true);
  }

  Future<void> saveChanges() async {
    if (isSaving) return;
    setState(() => isSaving = true);

    try {
      await supabase.from('animals').update({
        'name': nameController.text.trim(),
        'status': status,
        'tattoo': tattooController.text.trim(),
        'sex': sex,
        'registration_number': registrationController.text.trim(),
        'grand_champion_number': gcController.text.trim(),
      }).eq('id', widget.animalId);

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => isSaving = false);
    }
  }

  List<DropdownMenuItem<String>> getSexItems() {
    if (species == 'cavy') {
      return const [
        DropdownMenuItem(value: 'M', child: Text('Boar')),
        DropdownMenuItem(value: 'F', child: Text('Sow')),
      ];
    }
    return const [
      DropdownMenuItem(value: 'M', child: Text('Buck')),
      DropdownMenuItem(value: 'F', child: Text('Doe')),
    ];
  }

  String displaySpecies() {
    if (species == 'rabbit') return 'Rabbit';
    if (species == 'cavy') return 'Cavy';
    return species;
  }

  @override
  void initState() {
    super.initState();
    loadAnimal();
  }

  @override
  Widget build(BuildContext context) {
    if (!isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Animal')),
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
              value: status,
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

            // SEX
            DropdownButtonFormField<String>(
              value: sex,
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
              decoration:
                  const InputDecoration(labelText: 'Registration Number'),
            ),

            // GRAND CHAMPION
            TextField(
              controller: gcController,
              decoration:
                  const InputDecoration(labelText: 'Grand Champion Number'),
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