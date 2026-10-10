import 'package:flutter/material.dart';
import '../services/catalog_service.dart';

class CatalogField extends StatefulWidget {
  final String species, value;
  final String? breed;
  final ValueChanged<String> onChanged;
  const CatalogField({
    super.key,
    required this.species,
    required this.value,
    this.breed,
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
      final data = await CatalogService.options(species, breed);
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
    final exact = rows.where(
      (r) =>
          CatalogService.identity(r['name']) == CatalogService.identity(value),
    );
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
            child: ListView(
              children: [
                for (final name in options)
                  ListTile(
                    title: Text(name),
                    subtitle:
                        rows.any(
                          (r) =>
                              r['name'] == name && r['is_recognized'] == true,
                        )
                        ? (rows.any(
                                (r) =>
                                    r['name'] == name &&
                                    CatalogService.isCod(r),
                              )
                              ? const Text('COD')
                              : null)
                        : const Text('Unrecognized'),
                    onTap: () => select(name),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
