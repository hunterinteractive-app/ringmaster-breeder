import '../widgets/bulk_sale_dialog.dart';
import 'sales_dashboard_screen.dart';
import '../services/family_service.dart';
import 'herd_calendar_screen.dart';
import 'breeding_tracker_screen.dart';
import '../widgets/record_breeding_dialog.dart';
import '../widgets/bulk_records_dialog.dart';
import '../utils/color_details.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/animal_service.dart';
import '../utils/animal_labels.dart';
import '../theme/app_theme.dart';
import '../widgets/animal_avatar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/genetics_preview.dart';
import '../offline/offline_runtime.dart';
import 'genetics_screen.dart';
import 'what_if_screen.dart';

String _displayDob(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? 'Not recorded' : DateFormat('MM/dd/yyyy').format(date);
}

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
    FamilyService.selectedHerd = widget.ringId;
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
    onRefresh: _refresh,
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
        return StreamBuilder<AuthState>(
          stream: OfflineRuntime.client.auth.onAuthStateChange,
          builder: (context, _) => AnimalBrowser(
            animals: snapshot.data!,
            ringId: widget.ringId,
            onAdd: _add,
            onRefresh: _refresh,
            onOpen: _open,
            onWhatIfs:
                GeneticsPreview.allowsEmail(
                  OfflineRuntime.client.auth.currentUser?.email,
                )
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WhatIfScreen(),
                    ),
                  )
                : null,
            onGenetics:
                GeneticsPreview.allowsEmail(
                  OfflineRuntime.client.auth.currentUser?.email,
                )
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GeneticsScreen(animals: snapshot.data!),
                    ),
                  )
                : null,
          ),
        );
      },
    ),
  );
}

class AnimalBrowser extends StatefulWidget {
  final String? ringId;
  final List<Map<String, dynamic>> animals;
  final VoidCallback onAdd, onRefresh;
  final VoidCallback? onGenetics, onWhatIfs;
  final ValueChanged<Map<String, dynamic>> onOpen;
  const AnimalBrowser({
    super.key,
    required this.animals,
    required this.onAdd,
    required this.onRefresh,
    required this.onOpen,
    this.ringId,
    this.onGenetics,
    this.onWhatIfs,
  });
  @override
  State<AnimalBrowser> createState() => _AnimalBrowserState();
}

class _AnimalBrowserState extends State<AnimalBrowser> {
  String _searchBy = 'All', _query = '', _status = 'Active';
  String? _breed;
  bool _cards = true, _filtersExpanded = false;
  final _searchFieldKey = GlobalKey();
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _calendar() async {
    final ring = widget.ringId ?? widget.animals.firstOrNull?['ring_id'];
    if (ring == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => HerdCalendarScreen(ringId: ring)),
    );
    if (mounted) widget.onRefresh();
  }

  Future<void> _tracking() async {
    final ring = widget.ringId ?? widget.animals.firstOrNull?['ring_id'];
    if (ring == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BreedingTrackerScreen(ringId: ring),
      ),
    );
    if (mounted) widget.onRefresh();
  }

  Future<void> _growOut() async {
    final ring = widget.ringId ?? widget.animals.firstOrNull?['ring_id'];
    if (ring == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BreedingTrackerScreen(ringId: ring, growOut: true),
      ),
    );
    if (mounted) widget.onRefresh();
  }

  Future<void> _recordBreeding() async {
    final count = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RecordBreedingDialog(animals: widget.animals),
    );
    if (count != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Breeding recorded'),
          content: Text(
            'Saved $count breeding ${count == 1 ? 'record' : 'records'}, linked to the sire and each selected dam.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _bulk(bool weights) async {
    final count = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BulkRecordsDialog(
        animals: widget.animals.where(_matches).toList(),
        weights: weights,
      ),
    );
    if (count != null && mounted) {
      widget.onRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added $count ${weights ? 'weight' : 'health'} records.',
          ),
        ),
      );
    }
  }

  Future<void> _sales() async {
    final owner = FamilyService.ownerId;
    if (owner == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            SalesDashboardScreen(ownerId: owner, ringId: widget.ringId),
      ),
    );
    if (mounted) widget.onRefresh();
  }

  Future<void> _forSale() async {
    final count = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          BulkSaleDialog(animals: widget.animals.where(_matches).toList()),
    );
    if (count != null && mounted) {
      widget.onRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count animals marked For Sale.')),
      );
    }
  }

  bool _matches(Map<String, dynamic> a) {
    final status = a['status'] ?? 'active';
    if (_status == 'Active' && status != 'active') return false;
    if (_status == 'Sold' && status != 'sold') return false;
    if (_status == 'For Sale' && a['sale_status'] != 'for_sale') return false;
    if (_status == 'Archived' &&
        !['retired', 'deceased', 'archived'].contains(status)) {
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
  Widget _searchField(double width) => SizedBox(
    width: width,
    child: TextField(
      key: _searchFieldKey,
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        labelText: 'Search animals',
        hintText: _searchBy == 'DOB'
            ? 'MM/DD/YYYY or YYYY-MM-DD'
            : 'Name, breed, DOB or ear number',
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
  );

  Widget _breedFilter(double width, List<String> breeds, String? selected) =>
      SizedBox(
        width: width,
        child: DropdownButtonFormField<String>(
          key: ValueKey(selected),
          initialValue: selected,
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
      );

  Widget _viewToggle() => SegmentedButton<bool>(
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
  );

  Widget _actionGroup(
    String label,
    IconData icon,
    List<({String label, IconData icon, VoidCallback onPressed})> actions,
  ) => MenuAnchor(
    menuChildren: [
      for (final action in actions)
        MenuItemButton(
          leadingIcon: Icon(action.icon),
          onPressed: action.onPressed,
          child: Text(action.label),
        ),
    ],
    builder: (context, controller, child) => OutlinedButton(
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 20),
        ],
      ),
    ),
  );

  Widget _actionButtons({bool compact = false}) {
    final buttons = <Widget>[
      FilledButton.icon(
        onPressed: widget.onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add animal'),
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      _actionGroup('Breeding', Icons.favorite_outline, [
        (
          label: 'Breedings & litters',
          icon: Icons.child_care,
          onPressed: _tracking,
        ),
        (
          label: 'Grow-out dashboard',
          icon: Icons.grass_outlined,
          onPressed: _growOut,
        ),
        (
          label: 'Record breeding',
          icon: Icons.favorite_outline,
          onPressed: _recordBreeding,
        ),
      ]),
      if (widget.onGenetics != null || widget.onWhatIfs != null)
        _actionGroup('Genetics', Icons.science_outlined, [
          if (widget.onGenetics != null)
            (
              label: 'Genetics',
              icon: Icons.science_outlined,
              onPressed: widget.onGenetics!,
            ),
          if (widget.onWhatIfs != null)
            (
              label: 'What Ifs',
              icon: Icons.shuffle,
              onPressed: widget.onWhatIfs!,
            ),
        ]),
      _actionGroup('Sales', Icons.sell_outlined, [
        (
          label: 'Sales dashboard',
          icon: Icons.sell_outlined,
          onPressed: _sales,
        ),
        (
          label: 'Bulk mark For Sale',
          icon: Icons.checklist,
          onPressed: _forSale,
        ),
      ]),
      _actionGroup('Herd care', Icons.medical_services_outlined, [
        (
          label: 'Herd calendar',
          icon: Icons.calendar_month,
          onPressed: _calendar,
        ),
        (
          label: 'Bulk add weights',
          icon: Icons.monitor_weight_outlined,
          onPressed: () => _bulk(true),
        ),
        (
          label: 'Bulk add health / vaccine records',
          icon: Icons.medical_services_outlined,
          onPressed: () => _bulk(false),
        ),
      ]),
      IconButton(
        tooltip: 'Refresh records',
        onPressed: widget.onRefresh,
        icon: const Icon(Icons.refresh),
      ),
      _viewToggle(),
    ];
    if (compact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(spacing: 8, children: buttons),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: buttons,
    );
  }

  Widget _toolbar(
    bool compact,
    List<String> breeds,
    String? selectedBreed,
    int count,
  ) => Container(
    width: double.infinity,
    color: Colors.white,
    padding: compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (context, size) {
        final filterWidth = compact
            ? (size.maxWidth < 280 ? size.maxWidth : (size.maxWidth - 12) / 2)
            : 150.0;
        final filters = [
          _dropdown(
            'Search by',
            _searchBy,
            ['All', 'Breed', 'DOB', 'Ear number'],
            (v) => setState(() => _searchBy = v!),
            filterWidth,
          ),
          _dropdown(
            'Status',
            _status,
            ['Active', 'For Sale', 'Sold', 'Archived', 'All'],
            (v) => setState(() => _status = v!),
            filterWidth,
          ),
          _breedFilter(compact ? size.maxWidth : 190, breeds, selectedBreed),
        ];
        if (!compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [filters[0], _searchField(240), ...filters.skip(1)],
              ),
              const SizedBox(height: 16),
              _actionButtons(),
            ],
          );
        }
        final filterCount =
            (_searchBy != 'All' ? 1 : 0) +
            (_status != 'Active' ? 1 : 0) +
            (selectedBreed != null ? 1 : 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _searchField(double.infinity)),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: _filtersExpanded ? 'Hide filters' : 'Filters',
                  isSelected: _filtersExpanded,
                  onPressed: () =>
                      setState(() => _filtersExpanded = !_filtersExpanded),
                  icon: Badge(
                    isLabelVisible: filterCount > 0,
                    label: Text('$filterCount'),
                    child: const Icon(Icons.tune),
                  ),
                ),
              ],
            ),
            if (_filtersExpanded) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 16, children: filters),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() {
                    _searchBy = 'All';
                    _status = 'Active';
                    _breed = null;
                  }),
                  child: const Text('Reset filters'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _actionButtons(compact: true),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$count of ${widget.animals.length} animals',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BreederColors.text,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    [
                      _status,
                      if (selectedBreed != null) selectedBreed,
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BreederColors.text,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
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
    // Keep controls and lazy records in one scrollable at every screen size.
    return LayoutBuilder(
      builder: (context, viewport) {
        final compact = viewport.maxWidth < 600 || viewport.maxHeight < 400;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _toolbar(compact, breeds, selectedBreed, animals.length),
            ),
            if (!compact)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${animals.length} of ${widget.animals.length} animals',
                      style: const TextStyle(color: BreederColors.text),
                    ),
                  ),
                ),
              ),
            if (animals.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    widget.animals.isEmpty
                        ? 'No animals yet. Select Add animal to get started.'
                        : 'No animals match your filters.',
                  ),
                ),
              )
            else
              SliverLayoutBuilder(
                builder: (context, constraints) {
                  final sidePadding = compact ? 12.0 : 20.0;
                  final spacing = compact ? 12.0 : 16.0;
                  if (!_cards) {
                    return SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        sidePadding,
                        compact ? 8 : 0,
                        sidePadding,
                        24,
                      ),
                      sliver: SliverList.separated(
                        itemCount: animals.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final a = animals[i];
                          return ListTile(
                            title: Text(animalTitle(a['name'], a['tattoo'])),
                            subtitle: Text(
                              [
                                if (a['sale_status'] != null)
                                  a['sale_status'] == 'reserved'
                                      ? 'Reserved'
                                      : 'For Sale',
                                a['species'] == 'cavy' ? 'Cavy' : 'Rabbit',
                                '${a['breed'] ?? 'Breed not recorded'}${a['breed_unrecognized'] == true ? ' (Unrecognized)' : ''}',
                                '${varietyLabel(a).isEmpty ? 'Variety not recorded' : varietyLabel(a)}${a['variety_unrecognized'] == true ? ' (Unrecognized)' : ''}',
                                sexLabel(a['species'], a['sex']),
                                'DOB: ${_displayDob(a['dob'])}',
                              ].join(' • '),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => widget.onOpen(a),
                          );
                        },
                      ),
                    );
                  }
                  final columns = constraints.crossAxisExtent >= 1000
                      ? 4
                      : constraints.crossAxisExtent >= 750
                      ? 3
                      : constraints.crossAxisExtent >= 500
                      ? 2
                      : 1;
                  final width =
                      (constraints.crossAxisExtent -
                          sidePadding * 2 -
                          (columns - 1) * spacing) /
                      columns;
                  // Build a viewport of rows while letting each card keep its
                  // natural height for wrapped details and larger text sizes.
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      sidePadding,
                      compact ? 8 : 0,
                      sidePadding,
                      24,
                    ),
                    sliver: SliverList.builder(
                      key: ValueKey('animal-cards-$columns'),
                      itemCount: (animals.length / columns).ceil(),
                      itemBuilder: (context, row) => Padding(
                        padding: EdgeInsets.only(bottom: spacing),
                        child: Wrap(
                          spacing: spacing,
                          children: [
                            for (var column = 0; column < columns; column++)
                              if (row * columns + column < animals.length)
                                SizedBox(
                                  width: width,
                                  child: AnimalRecordCard(
                                    animal: animals[row * columns + column],
                                    compact: compact,
                                    onTap: () => widget.onOpen(
                                      animals[row * columns + column],
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class AnimalRecordCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final VoidCallback onTap;
  final bool compact;
  const AnimalRecordCard({
    super.key,
    required this.animal,
    required this.onTap,
    this.compact = false,
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
    Widget tag(String label, {bool active = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE1F2E8) : const Color(0xFFEEF0F3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: active ? const Color(0xFF246345) : BreederColors.text,
        ),
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
        child: compact
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimalAvatar(
                          species: animal['species'] ?? 'rabbit',
                          photoUrl: animal['photo_url'],
                          size: 40,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: BreederColors.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  species,
                                  '${recorded('breed')}${animal['breed_unrecognized'] == true ? ' (Unrecognized)' : ''}',
                                  '${varietyLabel(animal).isEmpty ? 'Variety not recorded' : varietyLabel(animal)}${animal['variety_unrecognized'] == true ? ' (Unrecognized)' : ''}',
                                  sexLabel(
                                    animal['species'] ?? 'rabbit',
                                    animal['sex'] ?? '',
                                  ),
                                ].join(' • '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: BreederColors.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Tooltip(
                          message: 'View details',
                          child: Icon(Icons.chevron_right, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        tag(
                          status.isEmpty
                              ? 'Unknown'
                              : '${status[0].toUpperCase()}${status.substring(1)}',
                          active: status == 'active',
                        ),
                        if (animal['sale_status'] != null)
                          tag(
                            animal['sale_status'] == 'reserved'
                                ? 'Reserved'
                                : 'For Sale',
                          ),
                        Text(
                          'DOB: ${_displayDob(animal['dob'])}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: BreederColors.text,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            : Padding(
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
                    if (animal['sale_status'] != null)
                      Center(
                        child: Chip(
                          label: Text(
                            animal['sale_status'] == 'reserved'
                                ? 'Reserved'
                                : 'For Sale',
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
                    detail(
                      'Breed',
                      '${recorded('breed')}${animal['breed_unrecognized'] == true ? ' (Unrecognized)' : ''}',
                    ),
                    detail(
                      'Variety',
                      '${varietyLabel(animal).isEmpty ? 'Not recorded' : varietyLabel(animal)}${animal['variety_unrecognized'] == true ? ' (Unrecognized)' : ''}',
                    ),
                    detail('DOB', _displayDob(animal['dob'])),
                    detail(
                      'Sex',
                      sexLabel(
                        animal['species'] ?? 'rabbit',
                        animal['sex'] ?? '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            'View details',
                            style: TextStyle(
                              color: BreederColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
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
