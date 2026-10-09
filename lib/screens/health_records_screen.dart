import '../widgets/ringmaster_page_shell.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class HealthRecordsScreen extends StatefulWidget {
  final String animalId;
  const HealthRecordsScreen({super.key, required this.animalId});

  @override
  State<HealthRecordsScreen> createState() => _HealthRecordsScreenState();
}

class _HealthRecordsScreenState extends State<HealthRecordsScreen> {
  final supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _fetchRecords() async {
    final res = await supabase
        .from('animal_health_records')
        .select()
        .eq('animal_id', widget.animalId)
        .order('administered_date', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  void _openModal({Map<String, dynamic>? existing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          HealthRecordModal(animalId: widget.animalId, existing: existing),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'Health & Vaccine Records',
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openModal(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder(
        future: _fetchRecords(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final records = snapshot.data!;
          if (records.isEmpty) {
            return const Center(child: Text("No records yet."));
          }

          return ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, i) {
              final r = records[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(r['title'] ?? 'Record'),
                  subtitle: Text(
                    '${r['record_type']} — ${r['administered_date'] ?? ''}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete health record',
                    onPressed: () async {
                      await supabase
                          .from('animal_health_records')
                          .delete()
                          .eq('id', r['id']);
                      if (mounted) setState(() {});
                    },
                  ),
                  onTap: () => _openModal(existing: r),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// =============================================================
/// MODAL FORM
/// =============================================================
class HealthRecordModal extends StatefulWidget {
  final String animalId;
  final Map<String, dynamic>? existing;
  const HealthRecordModal({super.key, required this.animalId, this.existing});

  @override
  State<HealthRecordModal> createState() => _HealthRecordModalState();
}

class _HealthRecordModalState extends State<HealthRecordModal> {
  final supabase = Supabase.instance.client;

  late TextEditingController titleCtrl;
  late TextEditingController medicationCtrl;
  late TextEditingController dosageCtrl;
  late TextEditingController vetCtrl;
  late TextEditingController descriptionCtrl;

  DateTime? administeredDate;
  DateTime? expiresDate;
  DateTime? readministerDate;

  String recordType = 'health';
  String retention = '7 days';
  String? attachmentUrl;
  Uint8List? attachmentBytes;
  String? attachmentName;
  bool saving = false;

  bool get isEditing => widget.existing != null;

  final retentionOptions = [
    '7 days',
    '1 month',
    '3 months',
    '6 months',
    '1 year',
    'never',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    titleCtrl = TextEditingController(text: e?['title'] ?? '');
    medicationCtrl = TextEditingController(text: e?['medication'] ?? '');
    dosageCtrl = TextEditingController(text: e?['dosage'] ?? '');
    vetCtrl = TextEditingController(text: e?['veterinarian'] ?? '');
    descriptionCtrl = TextEditingController(text: e?['description'] ?? '');

    recordType = e?['record_type'] ?? 'health';
    retention = (e?['retention'] ?? '7 days').toString().replaceAll('_', ' ');
    if (!retentionOptions.contains(retention)) retention = '7 days';
    attachmentUrl = e?['attachment_url'];
    if (attachmentUrl != null &&
        attachmentUrl!.contains('/health_attachments/')) {
      attachmentUrl = Uri.decodeComponent(
        attachmentUrl!.split('/health_attachments/').last.split('?').first,
      );
    }

    administeredDate = _parseDate(e?['administered_date']) ?? DateTime.now();
    expiresDate = _parseDate(e?['expires_date']);
    readministerDate = _parseDate(e?['readminister_date']);
  }

  DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  Future<void> _pickDate(Function(DateTime) onPick) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: DateTime.now(),
    );
    if (picked != null) onPick(picked);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (!mounted || result == null) return;
    final file = result.files.single;
    if (file.size > 10 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a file smaller than 10 MB.')),
      );
      return;
    }
    setState(() {
      attachmentBytes = file.bytes;
      attachmentName = file.name;
    });
  }

  Future<void> _save() async {
    if (saving) return;
    if (titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a record title.')));
      return;
    }
    setState(() => saving = true);
    try {
      String? uploadedUrl = attachmentUrl;
      if (attachmentBytes != null) {
        final filename =
            '${widget.animalId}/${DateTime.now().microsecondsSinceEpoch}_${attachmentName!.replaceAll(RegExp(r"[^a-zA-Z0-9._-]"), "_")}';
        await supabase.storage
            .from('health_attachments')
            .uploadBinary(filename, attachmentBytes!);
        uploadedUrl = filename;
      }
      final data = {
        'animal_id': widget.animalId,
        'title': titleCtrl.text,
        'medication': medicationCtrl.text,
        'dosage': dosageCtrl.text,
        'veterinarian': vetCtrl.text,
        'description': descriptionCtrl.text,
        'record_type': recordType,
        'administered_date': administeredDate?.toIso8601String(),
        'expires_date': expiresDate?.toIso8601String(),
        'readminister_date': readministerDate?.toIso8601String(),
        'retention': retention,
        'attachment_url': uploadedUrl,
      };

      if (isEditing) {
        await supabase
            .from('animal_health_records')
            .update(data)
            .eq('id', widget.existing!['id']);
      } else {
        await supabase.from('animal_health_records').insert(data);
      }

      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to save health record. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      titleCtrl,
      medicationCtrl,
      dosageCtrl,
      vetCtrl,
      descriptionCtrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Text(
              isEditing ? 'View / Edit Record' : 'Add Record',
              style: Theme.of(context).textTheme.titleLarge,
            ),

            DropdownButtonFormField<String>(
              initialValue: recordType,
              decoration: const InputDecoration(labelText: 'Record Type'),
              items: const [
                DropdownMenuItem(value: 'health', child: Text('Health')),
                DropdownMenuItem(value: 'vaccine', child: Text('Vaccine')),
              ],
              onChanged: isEditing
                  ? null
                  : (v) => setState(() => recordType = v!),
            ),

            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: medicationCtrl,
              decoration: const InputDecoration(labelText: 'Medication'),
            ),
            TextField(
              controller: dosageCtrl,
              decoration: const InputDecoration(labelText: 'Dosage'),
            ),
            TextField(
              controller: vetCtrl,
              decoration: const InputDecoration(labelText: 'Veterinarian'),
            ),
            TextField(
              controller: descriptionCtrl,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),

            const SizedBox(height: 12),

            _dateRow(
              'Administered',
              administeredDate,
              (d) => setState(() => administeredDate = d),
            ),
            _dateRow(
              'Expires',
              expiresDate,
              (d) => setState(() => expiresDate = d),
            ),
            _dateRow(
              'Re-administer',
              readministerDate,
              (d) => setState(() => readministerDate = d),
            ),

            DropdownButtonFormField<String>(
              initialValue: retention,
              decoration: const InputDecoration(labelText: 'Retention'),
              items: retentionOptions
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: isEditing
                  ? null
                  : (v) => setState(() => retention = v!),
            ),

            const SizedBox(height: 8),

            if (isEditing && attachmentUrl != null)
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text("View Attachment"),
                onPressed: () async {
                  final signedUrl = attachmentUrl!.startsWith('http')
                      ? attachmentUrl!
                      : await supabase.storage
                            .from('health_attachments')
                            .createSignedUrl(attachmentUrl!, 60);
                  final uri = Uri.parse(signedUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.attach_file),
                label: const Text("Attach File"),
                onPressed: _pickFile,
              ),

            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: saving ? null : _save,
              child: const Text('Save Record'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateRow(String label, DateTime? date, Function(DateTime) onPick) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$label: ${date == null ? '-' : date.toLocal().toString().split(' ')[0]}',
          ),
        ),
        TextButton(
          onPressed: () => _pickDate(onPick),
          child: const Text('Pick'),
        ),
      ],
    );
  }
}
