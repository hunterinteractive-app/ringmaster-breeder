import '../widgets/show_connection_panel.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/ringmaster_page_shell.dart';
import '../services/family_service.dart';
import '../services/license_service.dart';
import 'family_access_screen.dart';
import 'record_import_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final client = Supabase.instance.client;
  final fields = <String, TextEditingController>{
    for (final key in [
      'display_name',
      'phone',
      'address',
      'city',
      'state',
      'zip',
    ])
      key: TextEditingController(),
  };
  final form = GlobalKey<FormState>();
  String? owner, email, error;
  LicenseStatus? license;
  bool loading = true, saving = false, exporting = false, dirty = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    try {
      await FamilyService.refresh();
      owner = FamilyService.households.firstWhere(
        (h) => h['is_owner'] == true,
      )['owner_user_id'];
      final profile = await client
          .from('users')
          .select('display_name,email,phone,address,city,state,zip')
          .eq('id', owner!)
          .single();
      final plan = await fetchLicenseStatus(owner!);
      if (!mounted) return;
      for (final entry in fields.entries) {
        entry.value.text = profile[entry.key]?.toString() ?? '';
      }
      setState(() {
        email = client.auth.currentUser?.email ?? profile['email'];
        license = plan;
        loading = false;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Unable to load your account. Please try again.';
        });
      }
    }
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await client
          .from('users')
          .update({for (final e in fields.entries) e.key: e.value.text.trim()})
          .eq('id', owner!)
          .select('id')
          .single();
      if (mounted) setState(() => dirty = false);
      message('Contact and address saved.');
    } catch (_) {
      message('Unable to save your details. Please try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> exportAnimals() async {
    setState(() => exporting = true);
    try {
      final herds = await client
          .from('farms')
          .select('id,name')
          .eq('owner_id', owner!);
      final names = {for (final h in herds) h['id']: h['name']};
      final animals = <Map<String, dynamic>>[];
      if (names.isNotEmpty) {
        for (var offset = 0; ; offset += 500) {
          final page = await client
              .from('animals')
              .select(
                'id,ring_id,name,tattoo,species,breed,variety,sex,dob,status,sire_id,dam_id,pedigree_only',
              )
              .inFilter('ring_id', names.keys.toList())
              .order('id')
              .range(offset, offset + 499);
          animals.addAll(page);
          if (page.length < 500) break;
        }
      }
      final keys = [
        'id',
        'herd',
        'name',
        'tattoo',
        'species',
        'breed',
        'variety',
        'sex',
        'dob',
        'status',
        'sire_id',
        'dam_id',
        'pedigree_only',
      ];
      String cell(dynamic value) {
        var text = value?.toString() ?? '';
        if (RegExp(r'^[=+@\-\t\r]').hasMatch(text)) text = "'$text";
        return '"${text.replaceAll('"', '""')}"';
      }

      final csv = [
        keys.map(cell).join(','),
        for (final a in animals)
          keys
              .map((k) => cell(k == 'herd' ? names[a['ring_id']] : a[k]))
              .join(','),
      ].join('\r\n');
      await FilePicker.platform.saveFile(
        dialogTitle: 'Export animals',
        fileName: 'ringmaster-breeder-animals.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(csv)),
      );
    } catch (_) {
      message('Unable to export animals. Please try again.');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> open(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Widget section(String title, IconData icon, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: PageStorageKey<String>('account-$title'),
      maintainState: true,
      leading: Icon(icon),
      title: Text(title, style: Theme.of(context).textTheme.titleLarge),
      tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      childrenPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Account',
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error!),
                TextButton(
                  onPressed: () {
                    setState(() => loading = true);
                    load();
                  },
                  child: const Text('Try again'),
                ),
              ],
            ),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Your account, all in one place',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(email ?? ''),
                    const SizedBox(height: 24),
                    section('Contact & address', Icons.contact_mail_outlined, [
                      const Text(
                        'These details belong to your account and are used for your pedigree contact information.',
                      ),
                      const SizedBox(height: 20),
                      Form(
                        key: form,
                        child: Column(
                          children: [
                            for (final e in {
                              'display_name': 'Name / rabbitry or caviary name',
                              'phone': 'Phone',
                              'address': 'Street address',
                              'city': 'City',
                              'state': 'State / province',
                              'zip': 'ZIP / postal code',
                            }.entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: TextFormField(
                                  controller: fields[e.key],
                                  enabled: !saving,
                                  decoration: InputDecoration(
                                    labelText: e.value,
                                  ),
                                  keyboardType: e.key == 'phone'
                                      ? TextInputType.phone
                                      : TextInputType.text,
                                  textInputAction: TextInputAction.next,
                                  maxLength: e.key == 'address' ? 300 : 150,
                                  onChanged: (_) =>
                                      setState(() => dirty = true),
                                ),
                              ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: saving || !dirty ? null : save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          saving ? 'Saving…' : 'Save contact details',
                        ),
                      ),
                    ]),
                    section('Connected show programs', Icons.sync, [
                      const ShowConnectionPanel(),
                    ]),
                    section('Import & export', Icons.import_export, [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Import RingMaster records'),
                        subtitle: const Text(
                          'Bring in profiles, animals, and show history.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(const RecordImportScreen()),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Imported profiles & show history'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(const ImportedRecordsScreen()),
                      ),
                      const Divider(),
                      const Text(
                        'Download an animal list for all herds you own, including pedigree-only animals and parent IDs. This CSV does not include photos, health records, weights, or breeding history.',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: exporting ? null : exportAnimals,
                        icon: const Icon(Icons.download_outlined),
                        label: Text(
                          exporting
                              ? 'Preparing export…'
                              : 'Export animals (CSV)',
                        ),
                      ),
                    ]),
                    section('Subscription', Icons.credit_card_outlined, [
                      Text('Plan: ${license?.tierCode ?? 'Unavailable'}'),
                      Text(
                        license?.hasActiveLicense == true
                            ? 'Active • ${license!.currentRings} of ${license!.maxRings} herds used'
                            : 'No active subscription',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Billing will be managed through Stripe. Plan changes and cancellation will be available once Stripe is connected.',
                      ),
                    ]),
                    section('Family access', Icons.group_outlined, [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Manage family access'),
                        subtitle: const Text(
                          'Invite family members and manage shared access.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(const FamilyAccessScreen()),
                      ),
                    ]),
                    section(
                      'Account management',
                      Icons.manage_accounts_outlined,
                      [
                        const Text(
                          'Account closure and permanent deletion require a verified account-management service. They are not available here yet.',
                        ),
                        const SizedBox(height: 12),
                        const OutlinedButton(
                          onPressed: null,
                          child: Text('Delete account — not yet available'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await client.auth.signOut();
                              if (context.mounted) {
                                Navigator.of(
                                  context,
                                ).popUntil((r) => r.isFirst);
                              }
                            } catch (_) {
                              message('Unable to sign out. Please try again.');
                            }
                          },
                          icon: const Icon(Icons.logout),
                          label: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
