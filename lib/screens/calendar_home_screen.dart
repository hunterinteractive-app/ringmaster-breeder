import '../widgets/adaptive_layout.dart';
import '../offline/offline_runtime.dart';
import 'package:flutter/material.dart';
import '../services/family_service.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'herd_calendar_screen.dart';

class CalendarHomeScreen extends StatefulWidget {
  const CalendarHomeScreen({super.key});
  @override
  State<CalendarHomeScreen> createState() => _CalendarHomeScreenState();
}

class _CalendarHomeScreenState extends State<CalendarHomeScreen> {
  List<Map<String, dynamic>>? herds;
  String? selected, error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      error = null;
      herds = null;
    });
    try {
      await FamilyService.refresh();
      final rows = await OfflineRuntime.client
          .from('farms')
          .select('id,name')
          .eq('owner_id', FamilyService.ownerId!)
          .order('name');
      if (!mounted) return;
      setState(() {
        herds = List<Map<String, dynamic>>.from(rows);
        selected = rows.any((r) => r['id'] == FamilyService.selectedHerd)
            ? FamilyService.selectedHerd
            : rows.length == 1
            ? rows.first['id']
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to load herds. Please try again.');
      }
    }
  }

  Widget picker() => AdaptivePadding(
    padding: const EdgeInsets.only(bottom: 20),
    child: DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Herd'),
      items: [
        for (final h in herds!)
          DropdownMenuItem(value: h['id'] as String, child: Text(h['name'])),
      ],
      onChanged: (value) => setState(() {
        selected = value;
        FamilyService.selectedHerd = value;
      }),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (selected != null && herds != null) {
      return HerdCalendarScreen(
        key: ValueKey(selected),
        ringId: selected!,
        herdPicker: herds!.length > 1 ? picker() : null,
      );
    }
    return RingMasterPageShell(
      title: 'Herd calendar',
      isCalendarPage: true,
      onRefresh: load,
      body: AdaptivePadding(
        padding: const EdgeInsets.all(24),
        child: error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!),
                  TextButton(onPressed: load, child: const Text('Retry')),
                ],
              )
            : herds == null
            ? const Center(child: CircularProgressIndicator())
            : herds!.isEmpty
            ? const Text(
                'Create a herd from Home to start using your calendar.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Choose a herd to view its calendar.'),
                  const AdaptiveGap(height: 20),
                  picker(),
                ],
              ),
      ),
    );
  }
}
