import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pedigree_tree_screen.dart';
import '../services/pedigree_service.dart';
import '../services/pedigree_pdf_service.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'health_records_screen.dart';

class AnimalDetailScreen extends StatefulWidget {
  final String animalId;

  const AnimalDetailScreen({
    super.key,
    required this.animalId,
  });

  @override
  State<AnimalDetailScreen> createState() => _AnimalDetailScreenState();
}

class _AnimalDetailScreenState extends State<AnimalDetailScreen> {
  final supabase = Supabase.instance.client;

  /// --- Helpers ---
  bool isLocked(String status) =>
      status == "sold" || status == "deceased";

  String statusLockMessage(String status) {
    if (status == "sold") return "This animal has been sold.";
    if (status == "deceased") return "This animal is marked deceased.";
    return "";
  }

  /// --- Queries ---
  Future<Map<String, dynamic>> fetchAnimal() async {
    return await supabase
        .from("animals")
        .select()
        .eq("id", widget.animalId)
        .single();
  }

  Future<Map<String, dynamic>?> fetchParent(String? id) async {
    if (id == null) return null;

    final result = await supabase
        .from("animals")
        .select("name, tattoo")
        .eq("id", id)
        .maybeSingle();

    return result;
  }

  Future<Map<String, dynamic>> fetchSellerProfile() async {
  final user = supabase.auth.currentUser;

  if (user == null) {
    throw Exception("Not logged in");
  }

  return await supabase
      .from('profiles')
      .select()
      .eq('id', user.id)
      .single();
}

  Future<double?> fetchWeight() async {
    final res = await supabase
        .from("animal_weights")
        .select("weight")
        .eq("animal_id", widget.animalId)
        .order("recorded_at", ascending: false)
        .limit(1);

    if (res.isEmpty) return null;
    return (res.first["weight"] as num).toDouble();
  }

  // ------------------------------------------------------------
  // SAVE + SHARE PDF UTILITY
  // ------------------------------------------------------------
  Future<void> saveAndSharePdf({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File("${directory.path}/$fileName");

      await file.writeAsBytes(pdfBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: "Rabbit pedigree PDF",
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Sharing failed: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Animal Details")),
      body: FutureBuilder(
        future: Future.wait([
          fetchAnimal(),
          fetchWeight(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final animal = snapshot.data![0] as Map<String, dynamic>;
          final double? weight = snapshot.data![1] as double?;
          final locked = isLocked(animal["status"]);

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                /// NAME
                Text(
                  animal["name"] ?? "Unnamed",
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),

                /// LOCK NOTICE
                if (locked)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusLockMessage(animal["status"]),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),

                /// BASIC DATA
                _row("Tattoo", animal["tattoo"]),
                _row("Species", animal["species"]),
                _row("Breed", animal["breed"]),
                _row("Variety", animal["variety"]),
                _row(
                  "Sex",
                  animal["sex"] == "M" ? "Buck" : "Doe",
                ),
                _row(
                  "Current Weight",
                  weight == null
                      ? "-"
                      : "${weight.toStringAsFixed(2)} lb",
                ),
                _row("Registration #", animal["registration_number"]),
                _row("GC #", animal["grand_champion_number"]),
                const SizedBox(height: 24),

                /// PARENTS SECTION
                FutureBuilder(
                  future: fetchParent(animal["sire_id"]),
                  builder: (context, snap) {
                    final sire = snap.data;
                    return _row(
                      "Sire",
                      sire == null
                          ? "-"
                          : "${sire['name']} (${sire['tattoo'] ?? ''})",
                    );
                  },
                ),

                FutureBuilder(
                  future: fetchParent(animal["dam_id"]),
                  builder: (context, snap) {
                    final dam = snap.data;
                    return _row(
                      "Dam",
                      dam == null
                          ? "-"
                          : "${dam['name']} (${dam['tattoo'] ?? ''})",
                    );
                  },
                ),

                const SizedBox(height: 24),

                /// Edit Animal
                ElevatedButton(
                  onPressed: locked
                      ? null
                      : () async {
                          final updated = await Navigator.pushNamed(
                            context,
                            "/edit-animal",
                            arguments: widget.animalId,
                          );

                          if (updated == true) setState(() {});
                        },
                  child: const Text("Edit Animal"),
                ),

                const SizedBox(height: 12),

                /// Weight History
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      "/weight-history",
                      arguments: widget.animalId,
                    );
                  },
                  child: const Text("View Weight History"),
                ),

                const SizedBox(height: 12),

                /// Health & Vaccine Records
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HealthRecordsScreen(
                          animalId: widget.animalId,
                        ),
                      ),
                    );
                  },
                  child: const Text("Health & Vaccine Records"),
                ),

                const SizedBox(height: 12),

                /// View Pedigree Tree
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PedigreeTreeScreen(
                          animalId: widget.animalId,
                        ),
                      ),
                    );
                  },
                  child: const Text("View Pedigree Tree"),
                ),

                const SizedBox(height: 12),

                /// PDF EXPORT 
                OutlinedButton(
                  onPressed: () async {
                    try {
                      final pedigree = await PedigreeService.build(widget.animalId);
                      final seller = await fetchSellerProfile();

                      final pdfBytes = await PedigreePdfService.generate(
                        pedigree: pedigree,
                        seller: {
                          'name': seller['full_name'],
                          'address': seller['address'],
                          'city': seller['city'],
                          'state': seller['state'],
                          'zip': seller['zip'],
                          'phone': seller['phone'],
                          'email': seller['email'],
                          'dateSold': DateTime.now().toString().split(' ').first,
                        },
                      );

                      await saveAndSharePdf(
                        pdfBytes: pdfBytes,
                        fileName: "${pedigree['animal']['name'] ?? 'pedigree'}.pdf",
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("PDF failed: $e")),
                      );
                    }
                  },
                  child: const Text("Export Pedigree PDF"),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String title, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("$title:",
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Flexible(
            child: Text(
              value ?? "-",
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}