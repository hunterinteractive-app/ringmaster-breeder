import 'package:flutter/material.dart';
import '../services/catalog_service.dart';

class CatalogField extends StatefulWidget {
  final String species, value;
  final String? breed;
  final ValueChanged<String> onChanged;
  final Future<List<Map<String, dynamic>>> Function(String, String?)?
  loadOptions;
  const CatalogField({
    super.key,
    required this.species,
    required this.value,
    this.breed,
    this.loadOptions,
    required this.onChanged,
  });
  @override
  State<CatalogField> createState() => _CatalogFieldState();
}

class _CatalogFieldState extends State<CatalogField> {
  List<Map<String, dynamic>> rows = [];
  bool failed = false;
  late String value;
  @override
  void initState() {
    super.initState();
    value = widget.value;
    _load();
  }

  @override
  void didUpdateWidget(CatalogField old) {
    super.didUpdateWidget(old);
    if (old.species != widget.species || old.breed != widget.breed) _load();
  }

  Future<void> _load() async {
    final species = widget.species, breed = widget.breed;
    try {
      final data = await (widget.loadOptions ?? CatalogService.options)(
        species,
        breed,
      );
      if (mounted && species == widget.species && breed == widget.breed) {
        setState(() {
          rows = data;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  void change(String v) {
    setState(() => value = v);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final exact = rows.where((r) => CatalogService.matches(r, value));
    final custom =
        value.trim().isNotEmpty &&
        (exact.isEmpty || exact.first['is_recognized'] != true);
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: widget.value),
      optionsBuilder: (v) => rows
          .where(
            (r) =>
                v.text.isEmpty ||
                r['name'].toString().toLowerCase().contains(
                  v.text.toLowerCase(),
                ) ||
                (v.text.trim().length >= 3 &&
                    CatalogService.distance(v.text, r['name']) <= 2),
          )
          .map((r) => r['name'] as String),
      onSelected: change,
      fieldViewBuilder: (context, controller, focus, submit) => TextFormField(
        controller: controller,
        focusNode: focus,
        onChanged: change,
        textInputAction: TextInputAction.next,
        // Keep focus anchored here until the highlighted option is committed.
        onEditingComplete: () {},
        onFieldSubmitted: (_) {
          submit();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) focus.nextFocus();
          });
        },
        maxLength: 100,
        decoration: InputDecoration(
          labelText: widget.breed == null ? 'Breed' : 'Variety',
          counterText: '',
          helperMaxLines: 3,
          helperText: failed
              ? 'Catalog unavailable. You can still type a name.'
              : exact.isNotEmpty && CatalogService.isCod(exact.first)
              ? 'COD • Listed as COD in RingMaster Show.'
              : custom
              ? 'Unrecognized • shared custom entry. Check suggestions for spelling.'
              : exact.isNotEmpty &&
                    CatalogService.choiceNote(exact.first) != null
              ? '${CatalogService.choiceNote(exact.first)}. Add color details below when needed.'
              : 'Choose a name or type a shared custom entry.',
        ),
      ),
      optionsViewBuilder: (context, select, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          child: SizedBox(
            width: 320,
            height: 220,
            child: _CatalogOptions(
              options: options.toList(),
              rows: rows,
              select: select,
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogOptions extends StatefulWidget {
  final List<String> options;
  final List<Map<String, dynamic>> rows;
  final ValueChanged<String> select;
  const _CatalogOptions({
    required this.options,
    required this.rows,
    required this.select,
  });
  @override
  State<_CatalogOptions> createState() => _CatalogOptionsState();
}

class _CatalogOptionsState extends State<_CatalogOptions> {
  final scroll = ScrollController();
  int previous = -1;
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = AutocompleteHighlightedOption.of(context);
    if (previous != highlighted) {
      previous = highlighted;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scroll.hasClients) return;
        final top = highlighted * 72.0;
        final bottom = top + 72;
        final viewport = scroll.position.viewportDimension;
        if (top < scroll.offset || bottom > scroll.offset + viewport) {
          scroll.jumpTo(
            (top < scroll.offset ? top : bottom - viewport).clamp(
              0.0,
              scroll.position.maxScrollExtent,
            ),
          );
        }
      });
    }
    return ListView.builder(
      controller: scroll,
      padding: EdgeInsets.zero,
      itemExtent: 72,
      itemCount: widget.options.length,
      itemBuilder: (context, index) {
        final name = widget.options[index];
        final row = widget.rows.firstWhere((r) => r['name'] == name);
        return ListTile(
          selected: index == highlighted,
          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
          title: Text(name),
          subtitle: CatalogService.choiceNote(row) == null
              ? null
              : Text(CatalogService.choiceNote(row)!),
          onTap: () => widget.select(name),
        );
      },
    );
  }
}
