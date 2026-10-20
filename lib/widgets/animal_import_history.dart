import 'package:flutter/material.dart';
import '../offline/offline_runtime.dart';
import '../screens/global_pedigree_history_screen.dart';
import '../screens/kintraks_history_screen.dart';
import '../screens/rabbit_register_history_screen.dart';
import '../services/animal_history_service.dart';

/// Import-only histories are useful only when this animal has source records.
class AnimalImportHistory extends StatefulWidget {
  final String animalId;
  final Future<Set<AnimalHistorySource>> Function(String)? loader;
  const AnimalImportHistory({super.key, required this.animalId, this.loader});

  @override
  State<AnimalImportHistory> createState() => _AnimalImportHistoryState();
}

class _AnimalImportHistoryState extends State<AnimalImportHistory> {
  late Future<Set<AnimalHistorySource>> _sources = _load();
  Future<Set<AnimalHistorySource>> _load() =>
      (widget.loader ?? AnimalHistoryService.sources)(widget.animalId);

  @override
  void didUpdateWidget(covariant AnimalImportHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animalId != widget.animalId ||
        oldWidget.loader != widget.loader) {
      _sources = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Set<AnimalHistorySource>>(
    future: _sources,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox.shrink();
      }
      if (snapshot.hasError) {
        return TextButton.icon(
          onPressed: () => setState(() {
            _sources = _load();
          }),
          icon: const Icon(Icons.refresh),
          label: Text(
            snapshot.error is OfflineDataUnavailable
                ? 'Import history not downloaded. Reconnect and retry.'
                : 'Unable to check import history. Retry',
          ),
        );
      }
      final sources = AnimalHistorySource.values
          .where((source) => snapshot.data?.contains(source) ?? false)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final source in sources) ...[
            if (source != sources.first) const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => switch (source) {
                    AnimalHistorySource.globalPedigree =>
                      GlobalPedigreeHistoryScreen(animalId: widget.animalId),
                    AnimalHistorySource.rabbitRegister =>
                      RabbitRegisterHistoryScreen(animalId: widget.animalId),
                    AnimalHistorySource.kintraks => KintraksHistoryScreen(
                      animalId: widget.animalId,
                    ),
                  },
                ),
              ),
              child: Text(switch (source) {
                AnimalHistorySource.globalPedigree => 'Global Pedigree history',
                AnimalHistorySource.rabbitRegister => 'Rabbit Register history',
                AnimalHistorySource.kintraks => 'Kintraks history',
              }),
            ),
          ],
        ],
      );
    },
  );
}
