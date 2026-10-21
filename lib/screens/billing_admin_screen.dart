import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/sales_service.dart';
import '../services/billing_service.dart';
import '../widgets/ringmaster_page_shell.dart';

class BillingAdminScreen extends StatefulWidget {
  final String owner, label;
  const BillingAdminScreen({
    super.key,
    required this.owner,
    required this.label,
  });
  @override
  State<BillingAdminScreen> createState() => _BillingAdminScreenState();
}

class _BillingAdminScreenState extends State<BillingAdminScreen> {
  Map<String, dynamic>? data;
  bool busy = false;
  String? message;
  String tier = 'PRO', interval = 'year';
  final note = TextEditingController(),
      amount = TextEditingController(),
      quota = TextEditingController();
  String operation = SalesService.newId();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    note.dispose();
    amount.dispose();
    quota.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      final value = await BillingService.call('admin-status', {
        'owner': widget.owner,
      });
      if (mounted) setState(() => data = value);
    } catch (e) {
      if (mounted) {
        setState(() => message = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> run(
    String action,
    Map<String, dynamic> args,
    String warning,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm billing change'),
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
    setState(() => busy = true);
    try {
      final result = await BillingService.call(action, {
        'owner': widget.owner,
        ...args,
      });
      if (result['url'] != null) {
        await Clipboard.setData(ClipboardData(text: result['url']));
        operation = SalesService.newId();
      }
      if (mounted) {
        setState(
          () => message = result['url'] != null
              ? 'Private link copied. It grants access only to this account.'
              : result['results'] != null
              ? 'Price published. Renewal scheduling: ${result['results']}'
              : 'Change saved.',
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

  int? cents() {
    final value = num.tryParse(amount.text.trim());
    return value == null ? null : (value * 100).round();
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Membership administration',
    onRefresh: busy ? null : load,
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.titleLarge),
        const Text(
          'Changes here affect membership and billing. Actions are logged. Lifetime grants stop future recurring renewals; they do not refund prior payments.',
        ),
        if (busy) const LinearProgressIndicator(),
        if (message != null) SelectableText(message!),
        if (data?['manual_price_lock'] == true)
          const Text(
            'A price lock is reserved for this account’s next initial subscription.',
          ),
        for (final sub in data?['subscriptions'] as List? ?? [])
          Text(
            'Subscription: ${sub['status']} · Price locked: ${sub['price_locked'] == true ? 'Yes' : 'No'} · Renewal: ${sub['period_end'] ?? 'Pending'}',
          ),
        DropdownButtonFormField<String>(
          initialValue: tier,
          decoration: const InputDecoration(labelText: 'Tier'),
          items: const [
            DropdownMenuItem(value: 'HOBBY', child: Text('Hobby Breeder')),
            DropdownMenuItem(value: 'PRO', child: Text('Professional Breeder')),
            DropdownMenuItem(value: 'TOP', child: Text('Top Tier')),
          ],
          onChanged: busy ? null : (v) => setState(() => tier = v!),
        ),
        TextField(
          controller: note,
          decoration: const InputDecoration(
            labelText: 'Reason / notes (required for grants and removals)',
          ),
        ),
        FilledButton(
          onPressed: busy || tier == 'HOBBY'
              ? null
              : () => run(
                  'admin-grant',
                  {'tier': tier, 'note': note.text},
                  'Grant ${billingTier(tier)} lifetime access to ${widget.label}? Any current recurring membership will stop renewing.',
                ),
          child: const Text('Grant lifetime membership'),
        ),
        for (final g in (data?['grants'] as List? ?? []).where(
          (g) => g['active'] == true,
        ))
          ListTile(
            title: Text(
              '${billingTier(g['tier_code'])} lifetime · ${g['source']}',
            ),
            trailing: TextButton(
              onPressed: busy
                  ? null
                  : () => run(
                      'admin-revoke',
                      {'grant': g['id'], 'note': note.text},
                      'Remove this lifetime membership? Other valid memberships will remain in place.',
                    ),
              child: const Text('Remove'),
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => run(
                      'admin-lock',
                      {'enabled': true},
                      'Lock this account’s current price, or its next initial subscription price, while the same tier and interval remain continuously subscribed?',
                    ),
              child: const Text('Grant price lock'),
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => run(
                      'admin-lock',
                      {'enabled': false},
                      'Remove this account’s price lock? This does not change the price immediately.',
                    ),
              child: const Text('Remove price lock'),
            ),
          ],
        ),
        const Divider(),
        const Text(
          'Early-adopter offer — applies to the selected tier for all accounts',
        ),
        for (final r in data?['rules'] as List? ?? [])
          Text(
            '${billingTier(r['tier_code'])}: ${r['enabled'] == true ? 'first ${r['quota']} paid customers' : 'disabled'}',
          ),
        TextField(
          controller: quota,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'First-customer count (0 disables new locks)',
          ),
        ),
        OutlinedButton(
          onPressed: busy
              ? null
              : () => run(
                  'admin-rule',
                  {'tier': tier, 'quota': int.tryParse(quota.text)},
                  'Offer a continuous price lock to the first ${quota.text} eligible customers in ${billingTier(tier)}? Existing awards and pending reservations count toward this total.',
                ),
          child: const Text('Save early-adopter count'),
        ),
        const Divider(),
        const Text(
          'Private lifetime purchase — grants access only to this account',
        ),
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Price in USD'),
        ),
        FilledButton(
          onPressed: busy || tier == 'HOBBY'
              ? null
              : () => run(
                  'admin-lifetime-link',
                  {
                    'tier': tier,
                    'amount_cents': cents(),
                    'operation': operation,
                  },
                  'Create a private, single-purchase link for ${billingTier(tier)} lifetime at \$${amount.text} USD for ${widget.label}?',
                ),
          child: const Text('Create & copy private lifetime link'),
        ),
        for (final inv in data?['invitations'] as List? ?? [])
          if (inv['active'] == true)
            ListTile(
              title: SelectableText(
                inv['url'] ??
                    'Link creation pending — retry with the same settings',
              ),
              subtitle: const Text(
                'A checkout started before disabling can still complete.',
              ),
              trailing: TextButton(
                onPressed: busy
                    ? null
                    : () => run(
                        'admin-disable-link',
                        {'invitation': inv['id']},
                        'Disable this lifetime purchase link for new checkouts?',
                      ),
                child: const Text('Disable'),
              ),
            ),
        const Divider(),
        const Text('Publish a new recurring price for the selected tier'),
        DropdownButtonFormField<String>(
          initialValue: interval,
          items: const [
            DropdownMenuItem(value: 'month', child: Text('Monthly')),
            DropdownMenuItem(value: 'year', child: Text('Yearly')),
          ],
          onChanged: busy ? null : (v) => setState(() => interval = v!),
        ),
        OutlinedButton(
          onPressed: busy
              ? null
              : () => run(
                  'admin-publish-price',
                  {
                    'tier': tier,
                    'interval': interval,
                    'amount_cents': cents(),
                    'confirm_notice': true,
                  },
                  'Publish \$${amount.text}/$interval for ${billingTier(tier)}? Confirm that you have handled required renewal notices. Eligible unlocked subscribers change at their next renewal. Locked prices and already scheduled customer plan choices are preserved. Review the scheduling results and retry the same price if any fail.',
                ),
          child: const Text('Confirm notices handled & publish price'),
        ),
      ],
    ),
  );
}
