import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/animal_service.dart';
import '../utils/animal_labels.dart';
import '../theme/app_theme.dart';
import '../widgets/animal_avatar.dart';

class AnimalListScreen extends StatefulWidget {
  final String ringId;
  final String ringName;
  const AnimalListScreen({
    super.key,
    required this.ringId,
    required this.ringName,
  });
  @override
  State<AnimalListScreen> createState() => _AnimalListScreenState();
}

class _AnimalListScreenState extends State<AnimalListScreen> {
  late Future<List<Map<String, dynamic>>> _animals;
  @override
  void initState() {
    super.initState();
    _animals = AnimalService.list(widget.ringId);
  }

  void _refresh() =>
      setState(() => _animals = AnimalService.list(widget.ringId));
  Future<void> _add() async {
    final added = await Navigator.pushNamed(
      context,
      '/add-animal',
      arguments: {'ringId': widget.ringId, 'ringName': widget.ringName},
    );
    if (added == true && mounted) _refresh();
  }

  Future<void> _open(Map<String, dynamic> animal) async {
    await Navigator.pushNamed(
      context,
      '/animal-detail',
      arguments: animal['id'],
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: widget.ringName,
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _animals,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Unable to load records. Please go back and try again.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return AnimalBrowser(
          animals: snapshot.data!,
          onAdd: _add,
          onRefresh: _refresh,
          onOpen: _open,
        );
      },
    ),
  );
}

class AnimalBrowser extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  final VoidCallback onAdd, onRefresh;
  final ValueChanged<Map<String, dynamic>> onOpen;
  const AnimalBrowser({
    super.key,
    required this.animals,
    required this.onAdd,
    required this.onRefresh,
    required this.onOpen,
  });
  @override
  State<AnimalBrowser> createState() => _AnimalBrowserState();
}

class _AnimalBrowserState extends State<AnimalBrowser> {
  String _searchBy = 'All', _query = '', _status = 'Active';
  String? _breed;
  bool _cards = true;
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Map<String, dynamic> a) {
    final status = a['status'] ?? 'active';
    if (_status == 'Active' && status != 'active') return false;
    if (_status == 'Archived' &&
        !['sold', 'retired', 'deceased', 'archived'].contains(status)) {
      return false;
    }
    if (_breed != null && (a['breed'] as String? ?? '').trim() != _breed) {
      return false;
    }
    final dob = DateTime.tryParse(a['dob']?.toString() ?? '');
    final dates = [
      a['dob'] ?? '',
      if (dob != null) ...[
        DateFormat('M/d/yyyy').format(dob),
        DateFormat('MM/dd/yyyy').format(dob),
        DateFormat('MMM d, yyyy').format(dob),
      ],
    ];
    final values = switch (_searchBy) {
      'Breed' => [a['breed']],
      'DOB' => dates,
      'Ear number' => [a['tattoo']],
      _ => [a['name'], a['breed'], a['tattoo'], ...dates],
    };
    return values.any(
      (v) => (v?.toString() ?? '').toLowerCase().contains(
        _query.trim().toLowerCase(),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> items,
    ValueChanged<String?> change,
    double width,
  ) => SizedBox(
    width: width,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: items
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Text(v, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: change,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final breeds =
        widget.animals
            .map((a) => (a['breed'] as String? ?? '').trim())
            .where((b) => b.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final selectedBreed = breeds.contains(_breed) ? _breed : null;
    if (_breed != selectedBreed) _breed = selectedBreed;
    final animals = widget.animals.where(_matches).toList();
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, size) => Wrap(
              spacing: 12,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _dropdown(
                  'Search by',
                  _searchBy,
                  ['All', 'Breed', 'DOB', 'Ear number'],
                  (v) => setState(() => _searchBy = v!),
                  150,
                ),
                SizedBox(
                  width: size.maxWidth < 500 ? size.maxWidth : 240,
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      labelText: 'Search animals',
                      hintText: _searchBy == 'DOB'
                          ? 'MM/DD/YYYY or YYYY-MM-DD'
                          : 'Breed, DOB or ear number',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _search.clear();
                                _query = '';
                              }),
                            ),
                    ),
                  ),
                ),
                _dropdown(
                  'Status',
                  _status,
                  ['Active', 'Archived', 'All'],
                  (v) => setState(() => _status = v!),
                  150,
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(selectedBreed),
                    initialValue: selectedBreed,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Breed'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('All breeds'),
                      ),
                      ...breeds.map(
                        (b) => DropdownMenuItem(
                          value: b,
                          child: Text(b, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _breed = v),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Actions',
                  onSelected: (v) {
                    if (v == 'add') widget.onAdd();
                    if (v == 'refresh') widget.onRefresh();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'add',
                      child: ListTile(
                        leading: Icon(Icons.add),
                        title: Text('Add animal'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        leading: Icon(Icons.refresh),
                        title: Text('Refresh records'),
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: BreederColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Actions',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.expand_more, color: Colors.white),
                      ],
                    ),
                  ),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.view_list_outlined),
                      tooltip: 'List view',
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.grid_view_outlined),
                      tooltip: 'Card view',
                    ),
                  ],
                  selected: {_cards},
                  onSelectionChanged: (v) => setState(() => _cards = v.single),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${animals.length} of ${widget.animals.length} animals',
              style: const TextStyle(color: BreederColors.text),
            ),
          ),
        ),
        Expanded(
          child: animals.isEmpty
              ? Center(
                  child: Text(
                    widget.animals.isEmpty
                        ? 'No animals yet. Use Actions to add an animal.'
                        : 'No animals match your filters.',
                  ),
                )
              : LayoutBuilder(
                  builder: (context, size) {
                    if (!_cards) {
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: animals.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final a = animals[i];
                          return ListTile(
                            title: Text(animalTitle(a['name'], a['tattoo'])),
                            subtitle: Text(
                              [
                                a['species'] == 'cavy' ? 'Cavy' : 'Rabbit',
                                a['breed'] ?? 'Breed not recorded',
                                a['variety'] ?? 'Variety not recorded',
                                sexLabel(a['species'], a['sex']),
                              ].join(' • '),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => widget.onOpen(a),
                          );
                        },
                      );
                    }
                    final columns = size.maxWidth >= 1000
                        ? 4
                        : size.maxWidth >= 750
                        ? 3
                        : size.maxWidth >= 500
                        ? 2
                        : 1;
                    final width =
                        (size.maxWidth - 40 - (columns - 1) * 16) / columns;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: animals
                            .map(
                              (a) => SizedBox(
                                width: width,
                                child: AnimalRecordCard(
                                  animal: a,
                                  onTap: () => widget.onOpen(a),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class AnimalRecordCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final VoidCallback onTap;
  const AnimalRecordCard({
    super.key,
    required this.animal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final species = animal['species'] == 'cavy' ? 'Cavy' : 'Rabbit';
    final status = (animal['status'] as String? ?? 'active');
    final title = animalTitle(animal['name'], animal['tattoo']);
    String recorded(String key) =>
        (animal[key] as String?)?.trim().isNotEmpty == true
        ? animal[key]
        : 'Not recorded';
    Widget detail(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 65,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF677085), fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: BreederColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shadowColor: BreederColors.text.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFDDE0E3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: AnimalAvatar(
                  species: animal['species'] ?? 'rabbit',
                  photoUrl: animal['photo_url'],
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: status == 'active'
                        ? const Color(0xFFE1F2E8)
                        : const Color(0xFFEEF0F3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.isEmpty
                        ? 'Unknown'
                        : '${status[0].toUpperCase()}${status.substring(1)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: status == 'active'
                          ? const Color(0xFF246345)
                          : BreederColors.text,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: BreederColors.text,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              detail('Species', species),
              detail('Breed', recorded('breed')),
              detail('Variety', recorded('variety')),
              detail(
                'Sex',
                sexLabel(animal['species'] ?? 'rabbit', animal['sex'] ?? ''),
              ),
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'View details',
                    style: TextStyle(
                      color: BreederColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: BreederColors.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
