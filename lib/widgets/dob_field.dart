import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

DateTime? parseDob(String value) {
  try {
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)
        ? DateFormat('yyyy-MM-dd').parseStrict(value)
        : DateFormat('MM/dd/yyyy').parseStrict(value);
  } catch (_) {
    return null;
  }
}

String? dobError(String value) {
  if (value.trim().isEmpty) return null;
  final date = parseDob(value);
  if (date == null) return 'Enter a valid date as MM/DD/YYYY';
  if (date.isBefore(DateTime(1900))) return 'DOB must be 1900 or later';
  if (date.isAfter(DateTime.now())) return 'DOB cannot be in the future';
  return null;
}

class DobFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) digits = digits.substring(0, 8);
    final caret = newValue.selection.extentOffset.clamp(
      0,
      newValue.text.length,
    );
    var before = newValue.text
        .substring(0, caret)
        .replaceAll(RegExp(r'\D'), '')
        .length
        .clamp(0, digits.length);
    if (newValue.text.length < oldValue.text.length &&
        digits == oldValue.text.replaceAll(RegExp(r'\D'), '') &&
        before > 0) {
      digits = digits.substring(0, before - 1) + digits.substring(before);
      before--;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    final offset = before + (before > 2 ? 1 : 0) + (before > 4 ? 1 : 0);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset.clamp(0, text.length)),
    );
  }
}

class DobField extends StatefulWidget {
  final String value;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  const DobField({
    super.key,
    required this.value,
    required this.onChanged,
    this.readOnly = false,
  });
  @override
  State<DobField> createState() => _DobFieldState();
}

class _DobFieldState extends State<DobField> {
  late final TextEditingController controller;
  String display(String value) {
    final date = parseDob(value);
    return date == null ? value : DateFormat('MM/dd/yyyy').format(date);
  }

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: display(widget.value));
  }

  @override
  void didUpdateWidget(DobField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && display(widget.value) != controller.text) {
      controller.text = display(widget.value);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void changed(String text) {
    final date = parseDob(text);
    widget.onChanged(
      date == null ? text : DateFormat('yyyy-MM-dd').format(date),
    );
  }

  Future<void> pick() async {
    final now = DateTime.now();
    final entered = parseDob(controller.text);
    final date = await showDatePicker(
      context: context,
      initialDate: entered != null && dobError(controller.text) == null
          ? entered
          : now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (date != null && mounted) {
      controller.text = DateFormat('MM/dd/yyyy').format(date);
      changed(controller.text);
    }
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    readOnly: widget.readOnly,
    keyboardType: TextInputType.datetime,
    textInputAction: TextInputAction.next,
    inputFormatters: [DobFormatter()],
    onChanged: changed,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: (v) => widget.readOnly ? null : dobError(v ?? ''),
    decoration: InputDecoration(
      labelText: 'DOB (MM/DD/YYYY)',
      hintText: 'MM/DD/YYYY',
      suffixIcon: IconButton(
        tooltip: 'Choose date of birth',
        onPressed: widget.readOnly ? null : pick,
        icon: const Icon(Icons.calendar_today),
      ),
    ),
  );
}
