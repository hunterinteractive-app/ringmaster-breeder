import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SexField extends StatefulWidget {
  final String species, value;
  final ValueChanged<String>? onChanged;
  const SexField({
    super.key,
    required this.species,
    required this.value,
    this.onChanged,
  });
  @override
  State<SexField> createState() => _SexFieldState();
}

class _SexFieldState extends State<SexField> {
  final menu = MenuController();
  late final FocusNode focus;
  @override
  void initState() {
    super.initState();
    focus = FocusNode(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            !menu.isOpen &&
            widget.onChanged != null &&
            [
              LogicalKeyboardKey.arrowDown,
              LogicalKeyboardKey.arrowUp,
            ].contains(event.logicalKey)) {
          menu.open();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    focus.addListener(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (focus.hasFocus && widget.onChanged != null) {
          menu.open();
        } else if (menu.isOpen) {
          menu.close();
        }
      });
    });
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DropdownMenu<String>(
    expandedInsets: EdgeInsets.zero,
    focusNode: focus,
    menuController: menu,
    initialSelection: widget.value,
    label: const Text('Sex'),
    requestFocusOnTap: true,
    enableFilter: false,
    enabled: widget.onChanged != null,
    dropdownMenuEntries: [
      for (final sex
          in widget.species == 'cavy' ? ['Boar', 'Sow'] : ['Buck', 'Doe'])
        DropdownMenuEntry(value: sex, label: sex),
    ],
    onSelected: (v) {
      if (v != null) widget.onChanged?.call(v);
    },
  );
}
