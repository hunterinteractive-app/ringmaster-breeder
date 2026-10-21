import '../widgets/managed_record_dialogs.dart';
import '../services/sales_service.dart';
import 'package:flutter/material.dart';
import '../offline/offline_runtime.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/ringmaster_page_shell.dart';

class HerdContactsScreen extends StatefulWidget {
  final String? ringId;
  const HerdContactsScreen({super.key, this.ringId});
  @override
  State<HerdContactsScreen> createState() => _HerdContactsScreenState();
}

class _HerdContactsScreenState extends State<HerdContactsScreen> {
  late Future<List<Map<String, dynamic>>> contacts;
  @override
  void initState() {
    super.initState();
    contacts = load();
  }

  Future<List<Map<String, dynamic>>> load() async {
    final rows = <Map<String, dynamic>>[];
    for (var from = 0; ; from += 500) {
      var q = OfflineRuntime.client.from('herd_contacts').select();
      if (widget.ringId != null) q = q.eq('ring_id', widget.ringId!);
      final page = await q.order('name').order('id').range(from, from + 499);
      rows.addAll(List<Map<String, dynamic>>.from(page));
      if (page.length < 500) return rows;
    }
  }

  Future<void> edit([Map<String, dynamic>? row]) async {
    try {
      final herds = List<Map<String, dynamic>>.from(
        await OfflineRuntime.client
            .from('farms')
            .select('id,name')
            .eq('is_demo', false)
            .order('name'),
      );
      if (herds.isEmpty) {
        throw StateError('Create a herd before adding contacts.');
      }
      final id = row?['id'] as String? ?? SalesService.newId();
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ContactEditorDialog(
          initial: row ?? {'ring_id': widget.ringId},
          herds: herds,
          writer: (data) async {
            await OfflineRuntime.client.rpc(
              'save_herd_contact',
              params: {
                'p_id': id,
                'p_ring': data['ring_id'],
                'p_data': data,
                'p_revision': row?['revision'] ?? 0,
              },
            );
          },
        ),
      );
      if (saved == true && mounted) setState(() => contacts = load());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message.toString()
                  : 'Unable to load contact editing. Reconnect and retry.',
            ),
          ),
        );
      }
    }
  }

  Future<void> use(Map<String, dynamic> c) async {
    try {
      final db = OfflineRuntime.client;
      final herd = await db
          .from('farms')
          .select('owner_id')
          .eq('id', c['ring_id'])
          .single();
      final current = await db
          .from('users')
          .select(
            'display_name,rabbitry_name,phone,address,city,state,zip,auth_user_id',
          )
          .eq('id', herd['owner_id'])
          .single();
      if (current['auth_user_id'] != db.auth.currentUser?.id) {
        throw StateError(
          'Only the account owner can replace their contact details.',
        );
      }
      if (!mounted) return;
      final fields = {
        'display_name': c['name'],
        'rabbitry_name': c['rabbitry'],
        'phone': c['phone'],
        'address': c['address'],
        'city': c['city'],
        'state': c['state'],
        'zip': c['zip'],
      };
      String mode = 'fill';
      bool show = false, saving = false;
      String? error;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => AdaptiveFormDialog(
            title: const Text('Use this contact for your account'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose how to apply this contact. Your sign-in email stays the same.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: 'fill',
                      child: Text('Fill empty account fields'),
                    ),
                    DropdownMenuItem(
                      value: 'replace',
                      child: Text('Replace account contact details'),
                    ),
                    DropdownMenuItem(
                      value: 'show',
                      child: Text('Show profile only'),
                    ),
                  ],
                  onChanged: saving ? null : (v) => set(() => mode = v!),
                ),
                const SizedBox(height: 16),
                for (final e in fields.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${e.key.replaceAll('_', ' ')}\nCurrent: ${current[e.key] ?? ''}\nAfter: ${mode == 'show' ? (current[e.key] ?? '') : ((mode == 'replace' || (current[e.key] ?? '').toString().trim().isEmpty) && (e.value ?? '').toString().isNotEmpty ? e.value : current[e.key] ?? '')}',
                    ),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: mode == 'show' || show,
                  title: const Text(
                    'Make this contact available as a show profile',
                  ),
                  onChanged: saving || mode == 'show'
                      ? null
                      : (v) => set(() => show = v ?? false),
                ),
                if (error != null) Text(error!),
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        set(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await db.rpc(
                            'use_herd_contact',
                            params: {
                              'p_contact': c['id'],
                              'p_mode': mode,
                              'p_show': show,
                            },
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Contact details applied.'),
                              ),
                            );
                          }
                        } catch (_) {
                          if (ctx.mounted) {
                            set(() {
                              saving = false;
                              error =
                                  'Unable to apply these details. Reconnect and retry.';
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Applying…' : 'Apply reviewed details'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message.toString()
                  : 'Unable to load account details. Reconnect and retry.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Contacts & rabbitries',
    floatingActionButton: FloatingActionButton(
      onPressed: () => edit(),
      tooltip: 'Add contact / rabbitry',
      child: const Icon(Icons.person_add_outlined),
    ),
    onRefresh: () => setState(() => contacts = load()),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: contacts,
      builder: (context, s) {
        if (s.hasError) {
          return const Center(
            child: Text('Unable to load contacts. Reconnect and refresh.'),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: BreederLayout.pagePadding(context, normal: 24),
          children: [
            const Text(
              'Imported contacts remain separate people and rabbitries. Select your own record to set up account details or a show profile.',
            ),
            const SizedBox(height: 20),
            if (s.data!.isEmpty)
              const Text(
                'No contacts yet. Add a contact or import a Rabbit Register export.',
              ),
            for (final c in s.data!)
              Card(
                child: ExpansionTile(
                  title: Text(
                    (c['name'] as String).isEmpty ? c['rabbitry'] : c['name'],
                  ),
                  subtitle: Text(c['rabbitry']),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final k in [
                            'email',
                            'phone',
                            'address',
                            'city',
                            'state',
                            'zip',
                            'country',
                          ])
                            if (c[k] != '') SelectableText('${c[k]}'),
                          TextButton.icon(
                            onPressed: () => edit(c),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit contact'),
                          ),
                          TextButton(
                            onPressed: () => use(c),
                            child: const Text(
                              'Use for my account / show profile',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}
