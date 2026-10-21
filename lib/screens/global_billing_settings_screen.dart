import 'package:flutter/material.dart';
import '../services/billing_service.dart';
import '../widgets/ringmaster_page_shell.dart';

class GlobalBillingSettingsScreen extends StatefulWidget {
  const GlobalBillingSettingsScreen({super.key});
  @override
  State<GlobalBillingSettingsScreen> createState() =>
      _GlobalBillingSettingsScreenState();
}

class _GlobalBillingSettingsScreenState
    extends State<GlobalBillingSettingsScreen> {
  Map<String, dynamic>? data;
  String tier = 'HOBBY', interval = 'year';
  bool busy = false;
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
      final value = await BillingService.call('admin-global-status');
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
      final result = await BillingService.call(action, args);
      final results = result['results'] as List?;
      final failed = results?.where((r) => r['error'] != null).length ?? 0;
      if (mounted) {
        setState(
          () => message = results == null
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
            'Price changes apply at renewal. Locked prices and customer plan changes already scheduled are preserved.',
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
                        'confirm_notice': true,
                      },
                      'Publish \$$text/$interval USD for ${billingTier(tier)} across all accounts? Confirm that you have handled required renewal notices. Eligible unlocked subscribers change at their next renewal. Review the scheduling results and retry this same price if any memberships could not be updated.',
                    );
                  },
            child: const Text('Confirm notices handled & publish price'),
          ),
        ]),
      ],
    ),
  );
}
