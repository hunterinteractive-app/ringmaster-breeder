import 'herd_contacts_screen.dart';
import 'kintraks_import_screen.dart';
import 'kintraks_history_screen.dart';
import 'rabbit_register_import_screen.dart';
import 'rabbit_register_history_screen.dart';
import '../widgets/adaptive_layout.dart';
import '../offline/offline_runtime.dart';
import 'global_pedigree_history_screen.dart';
import '../widgets/sync_dialog.dart';
import 'super_admin_screen.dart';
import 'global_billing_settings_screen.dart';
import 'registration_feedback_screen.dart';
import 'registration_insights_screen.dart';
import 'billing_screen.dart';
import 'delete_account_screen.dart';
import '../widgets/show_connection_panel.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/ringmaster_page_shell.dart';
import '../services/family_service.dart';
import '../services/license_service.dart';
import 'family_access_screen.dart';
import 'record_import_screen.dart';
import 'global_pedigree_import_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final client = OfflineRuntime.client;
  final fields = <String, TextEditingController>{
    for (final key in [
      'display_name',
      'rabbitry_name',
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
  bool superAdmin = false;
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
          .select(
            'display_name,rabbitry_name,email,phone,address,city,state,zip',
          )
          .eq('id', owner!)
          .single();
      final plan = await fetchLicenseStatus(owner!);
      final admin = await client.rpc('breeder_is_super_admin') == true;
      if (!mounted) return;
      for (final entry in fields.entries) {
        entry.value.text = profile[entry.key]?.toString() ?? '';
      }
      setState(() {
        email = client.auth.currentUser?.email ?? profile['email'];
        license = plan;
        superAdmin = admin;
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
                'id,ring_id,name,tattoo,species,breed,variety,sex,dob,status,sire_id,dam_id,pedigree_only,animal_weights(weight,recorded_at)',
              )
              .inFilter('ring_id', names.keys.toList())
              .order('id')
              .order(
                'recorded_at',
                referencedTable: 'animal_weights',
                ascending: false,
              )
              .order('id', referencedTable: 'animal_weights', ascending: false)
              .limit(1, referencedTable: 'animal_weights')
              .range(offset, offset + 499);
          for (final animal in page) {
            final weights = animal['animal_weights'] as List? ?? [];
            if (weights.isNotEmpty) {
              animal['latest_weight_lb'] = weights.first['weight'];
              animal['latest_weight_recorded_at'] =
                  weights.first['recorded_at'];
            }
          }
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
        'latest_weight_lb',
        'latest_weight_recorded_at',
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
    if (mounted &&
        !dirty &&
        (screen is HerdContactsScreen ||
            screen is RabbitRegisterImportScreen)) {
      await load();
    }
  }

  Widget section(String title, IconData icon, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: PageStorageKey<String>('account-$title'),
      maintainState: true,
      leading: Icon(icon),
      title: Text(title, style: Theme.of(context).textTheme.titleLarge),
      tilePadding: BreederLayout.padding(
        context,
        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      ),
      childrenPadding: BreederLayout.padding(
        context,
        const EdgeInsets.fromLTRB(24, 8, 24, 24),
      ),
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
    isAccountPage: true,
    onRefresh: dirty || saving || loading ? null : load,
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
            padding: BreederLayout.pagePadding(context, normal: 24),
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
                    const AdaptiveGap(height: 8),
                    Text(email ?? ''),
                    const AdaptiveGap(height: 24),
                    section('Contact & address', Icons.contact_mail_outlined, [
                      const Text(
                        'These details belong to your account and are used for your pedigree contact information.',
                      ),
                      const AdaptiveGap(height: 20),
                      Form(
                        key: form,
                        child: Column(
                          children: [
                            for (final e in {
                              'display_name': 'Name',
                              'rabbitry_name': 'Rabbitry / caviary name',
                              'phone': 'Phone',
                              'address': 'Street address',
                              'city': 'City',
                              'state': 'State / province',
                              'zip': 'ZIP / postal code',
                            }.entries)
                              AdaptivePadding(
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
                        title: const Text('Import from Kintraks'),
                        subtitle: const Text(
                          'Upload a Kintraks All records CSV export.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(const KintraksImportScreen()),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Import from Rabbit Register'),
                        subtitle: const Text(
                          'Upload an Evans Rabbit Register XML export.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(const RabbitRegisterImportScreen()),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Import from Global Pedigree'),
                        subtitle: const Text(
                          'Bring in your rabbits and pedigree ancestors.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(const GlobalPedigreeImportScreen()),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Import RingMaster records'),
                        subtitle: const Text(
                          'Bring in profiles, animals, and show history.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(const RecordImportScreen()),
                      ),
                      const Divider(),
                      const Text(
                        'Download an animal list for all herds you own, including pedigree-only animals and parent IDs. Includes the latest recorded weight in pounds and its recorded date/time. Animals without a weight have blank weight fields. Photos, health records, full weight history, and breeding history are not included.',
                      ),
                      const AdaptiveGap(height: 12),
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
                    section('Contacts & rabbitries', Icons.contacts_outlined, [
                      ListTile(
                        title: const Text('Contacts & account setup'),
                        subtitle: const Text(
                          'Review imported people and choose account or show details.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(const HerdContactsScreen()),
                      ),
                    ]),
                    section('Imported history', Icons.history, [
                      ListTile(
                        title: const Text('Kintraks history'),
                        subtitle: const Text(
                          'Original animal fields, custom information, and import choices.',
                        ),
                        onTap: () => open(const KintraksHistoryScreen()),
                      ),
                      ListTile(
                        title: const Text('Rabbit Register history'),
                        subtitle: const Text(
                          'Original rabbits, contacts, litters, show results, and weights.',
                        ),
                        onTap: () => open(const RabbitRegisterHistoryScreen()),
                      ),
                      ListTile(
                        title: const Text('Global Pedigree history'),
                        subtitle: const Text(
                          'Imported litters, breedings, and dated weights.',
                        ),
                        onTap: () => open(const GlobalPedigreeHistoryScreen()),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Imported profiles & show history'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(const ImportedRecordsScreen()),
                      ),
                    ]),
                    section('Subscription', Icons.credit_card_outlined, [
                      ListTile(
                        title: const Text('Manage membership & billing'),
                        subtitle: const Text(
                          'Monthly or yearly plans, payment methods and invoices',
                        ),
                        onTap: () => open(const BillingScreen()),
                      ),
                      Text('Plan: ${license?.tierCode ?? 'Unavailable'}'),
                      Text(
                        license?.hasActiveLicense == true
                            ? 'Active • ${license!.currentRings} of ${license!.maxRings} herds used'
                            : 'No active subscription',
                      ),
                      const AdaptiveGap(height: 12),
                      const Text(
                        'Open Manage membership & billing to choose a monthly or yearly plan, update payment methods, view invoices, or cancel future renewals. Plan changes take effect at your next renewal.',
                      ),
                    ]),
                    if (superAdmin)
                      section('Super Admin', Icons.admin_panel_settings_outlined, [
                        ListTile(
                          title: const Text('Global billing settings'),
                          subtitle: const Text(
                            'Early-adopter limits and monthly/yearly prices for all accounts.',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              open(const GlobalBillingSettingsScreen()),
                        ),
                        ListTile(
                          title: const Text('Registration insights'),
                          subtitle: const Text(
                            'Herd tracking, referrals, and feature requests.',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => open(const RegistrationInsightsScreen()),
                        ),
                        ListTile(
                          title: const Text('View As User'),
                          subtitle: const Text(
                            'Inspect user accounts, herds, and animal records.',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => open(const SuperAdminScreen()),
                        ),
                      ]),
                    section('Feedback & referrals', Icons.feedback_outlined, [
                      ListTile(
                        title: const Text('Your feedback & referral code'),
                        subtitle: const Text(
                          'Share feature ideas, update your answers, and view referred signups.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => open(const RegistrationFeedbackScreen()),
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
                          'Permanently delete your Breeder account and all herds you own. Export any records you want to keep first.',
                        ),
                        const AdaptiveGap(height: 12),
                        OutlinedButton(
                          onPressed: () => open(const DeleteAccountScreen()),
                          child: const Text('Delete account'),
                        ),
                        const AdaptiveGap(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              if (!await confirmOfflineLogout(context)) return;
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
