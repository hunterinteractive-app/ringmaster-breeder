import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/billing_service.dart';

String accountBillingMoney(dynamic cents, dynamic currency) {
  if (cents is! num) return 'Amount unavailable';
  final code = (currency ?? 'usd').toString().toUpperCase();
  final format = NumberFormat.currency(
    name: code,
    symbol: code == 'USD' ? r'$' : code,
  );
  return '${format.format(cents / pow(10, format.decimalDigits ?? 2))}${code == 'USD' ? ' USD' : ''}';
}

String accountBillingDate(dynamic value, {bool time = false}) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return 'Not recorded';
  return (time ? DateFormat.yMMMd().add_jm() : DateFormat.yMMMd()).format(
    date.toLocal(),
  );
}

String accountBillingStatus(dynamic value) =>
    const {
      'active': 'Active',
      'past_due': 'Payment overdue',
      'unpaid': 'Unpaid',
      'trialing': 'Trial',
      'incomplete': 'Payment incomplete',
      'incomplete_expired': 'Checkout expired',
      'canceled': 'Canceled',
      'paused': 'Paused',
      'succeeded': 'Paid',
      'failed': 'Failed',
      'pending': 'Pending',
      'authorized': 'Authorized',
      'disputed': 'Disputed',
      'refunded': 'Fully refunded',
      'partially_refunded': 'Partially refunded',
      'paid': 'Paid',
      'open': 'Awaiting payment',
      'draft': 'Draft',
      'void': 'Voided',
      'uncollectible': 'Uncollectible',
    }[value] ??
    value?.toString() ??
    'Not recorded';

class AccountBillingOverview extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool busy;
  final VoidCallback? onMoreTransactions, onMoreInvoices, onRefresh;
  const AccountBillingOverview({
    super.key,
    required this.data,
    this.busy = false,
    this.onMoreTransactions,
    this.onMoreInvoices,
    this.onRefresh,
  });
  String planPrice(Map plan) {
    final interval = plan['interval'];
    final count = plan['interval_count'] as num? ?? 1;
    return '${accountBillingMoney(plan['amount_cents'], plan['currency'])}${interval == null
        ? ''
        : count > 1
        ? ' every $count ${interval}s'
        : '/$interval'}';
  }

  Widget section(BuildContext context, String title, List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );
  Future<void> openLink(BuildContext context, dynamic value) async {
    final uri = Uri.tryParse(value?.toString() ?? '');
    try {
      if (uri == null ||
          uri.scheme != 'https' ||
          !(uri.host == 'stripe.com' || uri.host.endsWith('.stripe.com')) ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception();
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to open this Stripe document. Refresh the billing details and try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = data['access'] as Map?;
    final subscriptions = data['subscriptions'] as List? ?? [];
    final transactions = data['transactions'] as List? ?? [];
    final invoices = data['invoices'] as List? ?? [];
    final activity = data['membership_activity'] as List? ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final warning in data['warnings'] as List? ?? [])
          Text(
            warning.toString(),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if ((data['warnings'] as List? ?? []).isNotEmpty)
          TextButton(
            onPressed: busy ? null : onRefresh,
            child: const Text('Retry billing details'),
          ),
        section(context, 'Current membership access', [
          Text(
            access?['name'] ?? 'No active license',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (access != null) ...[
            Text(
              const [
                    'manual_lifetime',
                    'stripe_lifetime',
                  ].contains(access['source'])
                  ? 'Lifetime access · no membership renewal required.'
                  : access['source'] == 'stripe_subscription'
                  ? 'Paid subscription access'
                  : 'Existing license · no Stripe renewal is attached to this license.',
            ),
            if (access['expires_at'] != null)
              Text(
                'Access through ${accountBillingDate(access['expires_at'])}',
              ),
          ],
        ]),
        section(context, 'Plans & renewals', [
          if (subscriptions.isEmpty)
            const Text('No Stripe subscription recorded for this account.'),
          for (final sub in subscriptions) ...[
            Text(
              sub['plan']['name'],
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Plan price: ${planPrice(sub['plan'])}'),
            Text('Status: ${accountBillingStatus(sub['status'])}'),
            if (sub['verified_live'] != true)
              const Text(
                'Saved details — live renewal status could not be confirmed.',
              ),
            if (const [
              'canceled',
              'incomplete_expired',
            ].contains(sub['status']))
              const Text('Not renewing')
            else if (sub['cancel_at_period_end'] == true)
              Text(
                'Cancellation scheduled · renewals stop ${accountBillingDate(sub['period_end'])}',
              )
            else
              Text('Next renewal: ${accountBillingDate(sub['period_end'])}'),
            if (sub['paid_through'] != null)
              Text(
                'Confirmed paid access through ${accountBillingDate(sub['paid_through'])}',
              ),
            Text('Price lock: ${sub['price_locked'] == true ? 'Yes' : 'No'}'),
            if (sub['scheduled_plan'] != null) ...[
              const SizedBox(height: 6),
              Text('Scheduled change: ${sub['scheduled_plan']['name']}'),
              Text(
                '${planPrice(sub['scheduled_plan'])} from ${accountBillingDate(sub['scheduled_plan']['effective_at'])}',
              ),
            ],
            const Divider(),
          ],
          const Text(
            'Plan prices are before any tax, discounts, or credits. Invoices show the actual billed totals.',
          ),
        ]),
        Card(
          child: ExpansionTile(
            title: const Text('Transaction history'),
            subtitle: Text('${transactions.length} loaded'),
            children: [
              if (data['transactions_available'] == false)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Some transaction history is unavailable. Refresh to retry.',
                  ),
                )
              else if (transactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No recorded Stripe transactions for this account. Manual lifetime grants are shown under membership activity.',
                  ),
                ),
              for (final t in transactions)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${accountBillingMoney(t['amount_cents'], t['currency'])} · ${accountBillingStatus(t['status'])}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(accountBillingDate(t['created_at'], time: true)),
                      Text(t['description']),
                      if ((t['refunded_cents'] as num? ?? 0) > 0)
                        Text(
                          'Refunded: ${accountBillingMoney(t['refunded_cents'], t['currency'])}',
                        ),
                      if (t['failure_message'] != null)
                        Text(t['failure_message']),
                      if (t['receipt_url'] != null)
                        TextButton(
                          onPressed: () => openLink(context, t['receipt_url']),
                          child: const Text('View receipt'),
                        ),
                      SelectableText('Reference: ${t['id']}'),
                      const Divider(),
                    ],
                  ),
                ),
              if (data['transactions_next'] != null)
                TextButton(
                  onPressed: busy ? null : onMoreTransactions,
                  child: const Text('Load older transactions'),
                ),
            ],
          ),
        ),
        Card(
          child: ExpansionTile(
            title: const Text('Invoices'),
            subtitle: Text('${invoices.length} loaded'),
            children: [
              if (data['invoices_available'] == false)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Invoices are unavailable. Refresh to retry.'),
                )
              else if (invoices.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No invoices recorded for this account.'),
                ),
              for (final i in invoices)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${i['number'] ?? 'Invoice'} · ${accountBillingStatus(i['status'])}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(accountBillingDate(i['created_at'])),
                      Text(
                        'Total: ${accountBillingMoney(i['total_cents'], i['currency'])}',
                      ),
                      Text(
                        'Paid: ${accountBillingMoney(i['paid_cents'], i['currency'])} · Remaining: ${accountBillingMoney(i['remaining_cents'], i['currency'])}',
                      ),
                      if (i['next_attempt_at'] != null)
                        Text(
                          'Next payment attempt: ${accountBillingDate(i['next_attempt_at'], time: true)}',
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (i['invoice_url'] != null)
                            TextButton(
                              onPressed: () =>
                                  openLink(context, i['invoice_url']),
                              child: const Text('View invoice'),
                            ),
                          if (i['pdf_url'] != null)
                            TextButton(
                              onPressed: () => openLink(context, i['pdf_url']),
                              child: const Text('Invoice PDF'),
                            ),
                        ],
                      ),
                      const Divider(),
                    ],
                  ),
                ),
              if (data['invoices_next'] != null)
                TextButton(
                  onPressed: busy ? null : onMoreInvoices,
                  child: const Text('Load older invoices'),
                ),
            ],
          ),
        ),
        if (activity.isNotEmpty)
          Card(
            child: ExpansionTile(
              title: const Text('Membership activity'),
              children: [
                for (final grant in activity)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${billingTier(grant['tier_code'])} lifetime · ${grant['active'] == true ? 'Active' : 'Removed'}',
                        ),
                        Text(
                          '${grant['source'] == 'manual_lifetime' ? 'Granted' : 'Purchased'} ${accountBillingDate(grant['created_at'])}',
                        ),
                        if (grant['revoked_at'] != null)
                          Text(
                            'Removed ${accountBillingDate(grant['revoked_at'])}',
                          ),
                        if (grant['note'] != null) Text(grant['note']),
                        const Divider(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
