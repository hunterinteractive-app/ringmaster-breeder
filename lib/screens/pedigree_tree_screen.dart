import '../widgets/pedigree_preview.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import '../services/pedigree_service.dart';

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
        return PedigreePreview.snapshot(
          pedigree: snapshot.data!,
          onAnimalTap: (id) =>
              Navigator.pushNamed(context, '/animal-detail', arguments: id),
        );
      },
    ),
  );
}
