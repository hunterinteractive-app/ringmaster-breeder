import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/sales_service.dart';
import '../services/billing_service.dart';
import '../widgets/ringmaster_page_shell.dart';
import '../widgets/account_billing_overview.dart';

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
  Map<String, dynamic>? data, billingDetails;
  String? detailsError;
  bool busy = false;
  String? message;
  String tier = 'PRO';
  final note = TextEditingController(), amount = TextEditingController();
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
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      detailsError = null;
    });
    try {
      final value = await BillingService.call('admin-status', {
        'owner': widget.owner,
      });
      if (mounted) setState(() => data = value);
      try {
        final details = await BillingService.call('admin-billing-details', {
          'owner': widget.owner,
        });
        if (mounted) setState(() => billingDetails = details);
      } catch (_) {
        if (mounted) {
          setState(
            () => detailsError =
                'Unable to load billing history. Refresh to try again.',
          );
        }
      }
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

  Future<void> loadHistory(String kind) async {
    final cursor = billingDetails?['${kind}_next'];
    if (cursor == null || busy) return;
    setState(() {
      busy = true;
      detailsError = null;
    });
    try {
      final page = await BillingService.call('admin-billing-history', {
        'owner': widget.owner,
        'kind': kind,
        'after': cursor,
      });
      if (mounted) {
        setState(() {
          final combined = <String, dynamic>{
            for (final row in billingDetails![kind]) row['id']: row,
            for (final row in page[kind]) row['id']: row,
          };
          final rows = combined.values.toList()
            ..sort(
              (a, b) => (b['created_at'] as String? ?? '').compareTo(
                a['created_at'] as String? ?? '',
              ),
            );
          billingDetails = {
            ...billingDetails!,
            kind: rows,
            '${kind}_next': page['${kind}_available'] == true
                ? page['${kind}_next']
                : cursor,
            '${kind}_available': page['${kind}_available'],
            'warnings': <String>{
              ...List<String>.from(billingDetails!['warnings']),
              ...List<String>.from(page['warnings']),
            }.toList(),
          };
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => detailsError =
              'Unable to load older billing history. Please try again.',
        );
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
        if (detailsError != null) Text(detailsError!),
        if (billingDetails != null)
          AccountBillingOverview(
            data: billingDetails!,
            busy: busy,
            onRefresh: load,
            onMoreTransactions: () => loadHistory('transactions'),
            onMoreInvoices: () => loadHistory('invoices'),
          ),
        const SizedBox(height: 16),
        Text(
          'Membership controls',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        DropdownButtonFormField<String>(
          initialValue: tier,
          decoration: const InputDecoration(
            labelText: 'Lifetime membership tier',
          ),
          items: const [
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
          'Private lifetime purchase — grants access only to this account',
        ),
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'One-time lifetime price (USD)',
          ),
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
      ],
    ),
  );
}
