import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/billing_service.dart';
import '../widgets/ringmaster_page_shell.dart';

class GlobalBillingSettingsScreen extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  request;
  const GlobalBillingSettingsScreen({
    super.key,
    this.request = BillingService.call,
  });
  @override
  State<GlobalBillingSettingsScreen> createState() =>
      _GlobalBillingSettingsScreenState();
}

class _GlobalBillingSettingsScreenState
    extends State<GlobalBillingSettingsScreen> {
  Map<String, dynamic>? data;
  String tier = 'HOBBY', interval = 'year';
  bool busy = false;
  DateTime startsAt = DateTime.now().add(const Duration(days: 30));
  String? message;
  final quota = TextEditingController(), amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    quota.dispose();
    amount.dispose();
    super.dispose();
  }

  Map? get selectedPrice {
    for (final p in data?['offers'] as List? ?? []) {
      if (p['tier_code'] == tier && p['interval'] == interval) return p as Map;
    }
    return null;
  }

  void updateFields() {
    quota.text = '0';
    for (final rule in data?['rules'] as List? ?? []) {
      if (rule['tier_code'] == tier) quota.text = '${rule['quota']}';
    }
    final price = selectedPrice;
    amount.text = price == null
        ? ''
        : ((price['amount_cents'] as num) / 100).toStringAsFixed(2);
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final value = await widget.request('admin-global-status', {});
      if (mounted) {
        setState(() {
          data = value;
          updateFields();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => message = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save(
    String action,
    Map<String, dynamic> args,
    String warning,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm global billing change'),
        content: SingleChildScrollView(child: Text(warning)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result = await widget.request(action, args);
      final results = result['results'] as List?;
      final failed = results?.where((r) => r['error'] != null).length ?? 0;
      if (mounted) {
        setState(
          () => message = result['scheduled'] == true
              ? 'Price change scheduled. Automatic emails will name each affected member’s renewal date. Refresh to check delivery and scheduling.'
              : results == null
              ? 'Early-adopter limit saved for ${billingTier(args['tier'])}.'
              : 'Price saved. ${results.length - failed} memberships scheduled for renewal.${failed > 0 ? ' $failed could not be updated. Publish the same price again to retry.' : ''}',
        );
      }
      if (mounted) await load();
    } catch (e) {
      if (mounted) {
        setState(() => message = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Global billing settings',
    onRefresh: busy ? null : load,
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'These settings apply across all accounts. Choose the tier you want to update.',
        ),
        const SizedBox(height: 12),
        if (busy) const LinearProgressIndicator(),
        if (message != null) SelectableText(message!),
        DropdownButtonFormField<String>(
          initialValue: tier,
          decoration: const InputDecoration(labelText: 'Tier'),
          items: const [
            DropdownMenuItem(value: 'HOBBY', child: Text('Hobby Breeder')),
            DropdownMenuItem(value: 'PRO', child: Text('Professional Breeder')),
            DropdownMenuItem(value: 'TOP', child: Text('Top Tier')),
          ],
          onChanged: busy
              ? null
              : (v) => setState(() {
                  tier = v!;
                  updateFields();
                }),
        ),
        const SizedBox(height: 16),
        section('Early-adopter price locks', [
          for (final rule in data?['rules'] as List? ?? [])
            Text(
              '${billingTier(rule['tier_code'])}: ${rule['enabled'] == true ? 'first ${rule['quota']} eligible customers' : 'disabled'}',
            ),
          const SizedBox(height: 12),
          TextField(
            controller: quota,
            enabled: !busy && data != null,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '${billingTier(tier)} customer limit',
              helperText: '0 disables new locks. Existing locks are preserved.',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: busy || data == null
                ? null
                : () {
                    final count = int.tryParse(quota.text.trim());
                    if (count == null || count < 0 || count > 100000) {
                      setState(
                        () => message =
                            'Enter a customer limit between 0 and 100,000.',
                      );
                      return;
                    }
                    save(
                      'admin-rule',
                      {'tier': tier, 'quota': count},
                      'Set the global early-adopter limit for ${billingTier(tier)} to $count? Existing awards and pending checkout reservations count toward this total. A limit of 0 stops new awards.',
                    );
                  },
            child: const Text('Save early-adopter limit'),
          ),
        ]),
        section('${billingTier(tier)} recurring prices', [
          DropdownButtonFormField<String>(
            initialValue: interval,
            decoration: const InputDecoration(labelText: 'Billing interval'),
            items: const [
              DropdownMenuItem(value: 'month', child: Text('Monthly')),
              DropdownMenuItem(value: 'year', child: Text('Yearly')),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() {
                    interval = v!;
                    updateFields();
                  }),
          ),
          if (selectedPrice != null)
            Text('Current price: ${billingPrice(selectedPrice!)} USD'),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            enabled: !busy && data != null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'New recurring price (USD)',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'New purchases use the new price from the start date. Existing members change at their first renewal on or after that date, with at least 30 days’ email notice. Locked prices, lifetime memberships, and scheduled customer plan changes are preserved.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final days in [30, 60, 90])
                ActionChip(
                  label: Text('In $days days'),
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          startsAt = DateTime.now().add(Duration(days: days));
                        }),
                ),
            ],
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('Start date: ${DateFormat.yMMMd().format(startsAt)}'),
            onPressed: busy
                ? null
                : () async {
                    final now = DateTime.now();
                    final chosen = await showDatePicker(
                      context: context,
                      initialDate: startsAt,
                      firstDate: now.add(const Duration(days: 2)),
                      lastDate: now.add(const Duration(days: 730)),
                    );
                    if (chosen != null && mounted) {
                      setState(() => startsAt = chosen);
                    }
                  },
          ),
          OutlinedButton(
            onPressed: busy || data == null
                ? null
                : () {
                    final text = amount.text.trim();
                    final value = double.tryParse(text);
                    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(text) ||
                        value == null ||
                        value < 1 ||
                        value > 999999.99) {
                      setState(
                        () => message =
                            'Enter a USD price between 1.00 and 999,999.99, with no more than two decimal places.',
                      );
                      return;
                    }
                    save(
                      'admin-publish-price',
                      {
                        'tier': tier,
                        'interval': interval,
                        'amount_cents': (value * 100).round(),
                        'starts_at': startsAt.toUtc().toIso8601String(),
                      },
                      'Schedule \$$text/$interval USD for ${billingTier(tier)} starting ${DateFormat.yMMMd().format(startsAt)}? Affected members will automatically receive an email with their old price, new price and exact renewal date. Their change happens at a regular renewal on or after the start date, with at least 30 days’ notice. New purchases use this price from the start date.',
                    );
                  },
            child: const Text('Schedule price change & notify members'),
          ),
        ]),
        section('Scheduled changes & email status', [
          if ((data?['changes'] as List? ?? []).isEmpty)
            const Text('No price changes scheduled.'),
          for (final change in data?['changes'] as List? ?? []) ...[
            Text(
              '${billingTier(change['offer']['tier_code'])} · ${billingPrice(change['offer'])}',
            ),
            Text(
              'Start: ${DateFormat.yMMMd().format(DateTime.parse(change['starts_at']).toLocal())} · ${change['state']}',
            ),
            Builder(
              builder: (context) {
                final notices = (data?['notices'] as List? ?? [])
                    .where((n) => n['change_id'] == change['id'])
                    .toList();
                final accepted = notices
                    .where((n) => n['email_accepted_at'] != null)
                    .length;
                final complete = notices
                    .where((n) => n['scheduled_at'] != null)
                    .length;
                final review = notices
                    .where(
                      (n) =>
                          n['state'] == 'review' ||
                          n['state'] == 'queued' && n['last_error'] != null,
                    )
                    .length;
                return Text(
                  'Recent notices: $accepted accepted · $complete renewals scheduled · $review need attention',
                );
              },
            ),
            for (final n in (data?['notices'] as List? ?? []).where(
              (n) =>
                  n['change_id'] == change['id'] &&
                  n['last_error'] != null &&
                  n['state'] != 'skipped',
            ))
              Text('Notice ${n['id']}: ${n['last_error']}'),
            const SizedBox(height: 12),
          ],
          const Text(
            'Email acceptance confirms handoff to the email service, not delivery to an inbox. Refresh to see progress. A late or unconfirmed notice never triggers an earlier charge.',
          ),
        ]),
      ],
    ),
  );
}
