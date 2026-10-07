

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/license_service.dart';

class RingDashboard extends StatefulWidget {
  final String userId;

  const RingDashboard({super.key, required this.userId});

  @override
  State<RingDashboard> createState() => _RingDashboardState();
}

class _RingDashboardState extends State<RingDashboard> {
  late Future<LicenseStatus> licenseFuture;
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    licenseFuture = fetchLicenseStatus(widget.userId);
  }

  Future<List> fetchRings(LicenseStatus license) async {
    if (license.hasActiveLicense) {
        // ✅ Paid users: ONLY show their real Rings
        return await supabase
            .from('farms')
            .select()
            .eq('owner_id', widget.userId);
    } else {
        // ✅ Unpaid users: ONLY show the Demo Ring
        return await supabase
            .from('farms')
            .select()
            .eq('is_demo', true);
    }
    }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: licenseFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final license = snapshot.data!;

        return Scaffold(
          appBar: AppBar(title: const Text('My Rings')),
          floatingActionButton: license.hasActiveLicense &&
                  license.currentRings < license.maxRings
              ? FloatingActionButton(
                  onPressed: () => _showCreateRingDialog(),
                  child: const Icon(Icons.add),
                )
              : null,
          body: FutureBuilder(
            future: fetchRings(license),
            builder: (context, ringSnap) {
              if (!ringSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final rings = ringSnap.data as List;

              if (rings.isEmpty) {
                return const Center(child: Text('No Rings Found'));
              }

              return ListView.builder(
                itemCount: rings.length,
                itemBuilder: (context, index) {
                  final ring = rings[index];
                  return ListTile(
                    title: Text(ring['name']),
                    subtitle: ring['is_demo']
                        ? const Text('Demo Ring (Read Only)')
                        : const Text('Your Ring'),
                    trailing: ring['is_demo']
                        ? const Icon(Icons.lock)
                        : const Icon(Icons.arrow_forward_ios),
                    onTap: ring['is_demo']
                        ? null
                        : () {
                            Navigator.pushNamed(
                                context,
                                '/animals',
                                arguments: {
                                'ringId': ring['id'],
                                'ringName': ring['name'],
                                },
                            );
                            },
                    );
                },
              );
            },
          ),
        );
      },
    );
  }

  void _showCreateRingDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create New Ring'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Ring Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              await supabase.from('farms').insert({
                'name': name,
                'owner_id': widget.userId,
                'is_demo': false,
              });

              Navigator.pop(context);
              setState(() {
                licenseFuture = fetchLicenseStatus(widget.userId);
              });
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}