import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../services/billing_service.dart';
import '../widgets/ringmaster_page_shell.dart';

class BillingScreen extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  request;
  const BillingScreen({super.key, this.request = BillingService.call});
  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  String interval = 'year';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load(refresh: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) load(refresh: true);
  }

  Future<void> load({bool refresh = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (refresh) await widget.request('refresh', {});
      final result = await widget.request('status', {});
      if (mounted) setState(() => data = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Unable to refresh billing. ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm membership'),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep current plan'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> action(String name, Map<String, dynamic> values) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.request(name, values);
      if (result['url'] != null) {
        final uri = Uri.parse(result['url'] as String);
        if (uri.scheme != 'https' ||
            !(uri.host.endsWith('.stripe.com') || uri.host == 'stripe.com')) {
          throw Exception('Invalid payment link');
        }
        if (!await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_self',
        )) {
          throw Exception('Could not open Stripe');
        }
      }
      if (mounted) await load();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String date(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '');
    return d == null
        ? 'Awaiting confirmation'
        : DateFormat.yMMMd().format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final subscriptions = (data?['subscriptions'] as List? ?? [])
        .where((s) => !['canceled', 'incomplete_expired'].contains(s['status']))
        .toList();
    final lifetime = (data?['grants'] as List? ?? [])
        .where((g) => g['active'] == true)
        .toList();
    final prices = data?['prices'] as List? ?? [];
    Map? price(dynamic id) {
      for (final p in prices) {
        if (p['id'] == id) return p as Map;
      }
      return null;
    }

    return RingMasterPageShell(
      title: 'Membership & billing',
      onRefresh: busy ? null : () => load(refresh: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Billing belongs to your own account. Shared household access does not allow another member to change your membership.',
          ),
          const SizedBox(height: 12),
          if (busy) const LinearProgressIndicator(),
          if (error != null) ...[
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: busy ? null : () => load(refresh: true),
              child: const Text('Retry / refresh payment status'),
            ),
          ],
          for (final grant in lifetime)
            Card(
              child: ListTile(
                leading: const Icon(Icons.workspace_premium),
                title: Text('${billingTier(grant['tier_code'])} · Lifetime'),
                subtitle: const Text('No recurring membership charge.'),
              ),
            ),
          for (final sub in subscriptions)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${billingTier(price(sub['offer_id'])?['tier_code'] ?? 'Breeder')} · ${price(sub['offer_id']) == null ? '' : billingPrice(price(sub['offer_id'])!)}',
                    ),
                    Text('Payment status: ${sub['status']}'),
                    Text(
                      '${sub['cancel_at_period_end'] == true ? 'Ends' : 'Next renewal'}: ${date(sub['period_end'])}',
                    ),
                    if (sub['price_locked'] == true)
                      const Text(
                        'Your price is locked while you keep this plan and billing interval continuously. Updating your card keeps your lock.',
                      ),
                    if (sub['pending_offer_id'] != null &&
                        price(sub['pending_offer_id']) != null)
                      Text(
                        'At renewal: ${billingTier(price(sub['pending_offer_id'])!['tier_code'])} · ${billingPrice(price(sub['pending_offer_id'])!)} on ${date(sub['pending_effective_at'] ?? sub['period_end'])}',
                      ),
                  ],
                ),
              ),
            ),
          if (subscriptions.isNotEmpty)
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (await confirm(
                            'Stop future Breeder renewals? Paid access stays available until its paid-through date. Your price lock ends when the subscription ends.',
                          ) &&
                          mounted) {
                        await action('cancel-subscription', {'confirm': true});
                      }
                    },
              child: const Text('Cancel future renewals'),
            ),
          if (data != null)
            OutlinedButton(
              onPressed: busy ? null : () => action('portal', {}),
              child: const Text('Payment methods, invoices & cancellation'),
            ),
          if ((data?['checkouts'] as List? ?? []).isNotEmpty) ...[
            const Text(
              'You have an unfinished checkout. Resume the same plan or close it before selecting a different one.',
            ),
            for (final c in data!['checkouts'])
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => action('cancel-checkout', {'checkout': c['id']}),
                child: const Text('Close unfinished checkout'),
              ),
          ],
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'month', label: Text('Monthly')),
              ButtonSegment(value: 'year', label: Text('Yearly')),
            ],
            selected: {interval},
            onSelectionChanged: busy
                ? null
                : (v) => setState(() => interval = v.first),
          ),
          const SizedBox(height: 12),
          for (final offer in (data?['offers'] as List? ?? []).where(
            (p) => p['interval'] == interval,
          ))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      billingTier(offer['tier_code']),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(billingPrice(offer)),
                    Text(
                      offer['tier_code'] == 'HOBBY'
                          ? '50 active animals · 1 herd'
                          : offer['tier_code'] == 'PRO'
                          ? '250 active animals · 1 herd'
                          : '1,000 active animals across up to 5 herds',
                    ),
                    if (offer['tier_code'] != 'HOBBY')
                      const Text(
                        'Buyer pedigree emails included. Custom pedigree branding and saved layouts are planned; they are not available yet.',
                      ),
                    FilledButton(
                      onPressed:
                          busy ||
                              lifetime.isNotEmpty ||
                              data?['checkout_enabled'] != true
                          ? null
                          : () async {
                              final sub = subscriptions.isEmpty
                                  ? null
                                  : subscriptions.first;
                              final message = sub == null
                                  ? '${billingTier(offer['tier_code'])}: ${billingPrice(offer)} USD, charged automatically until canceled. This replaces any complimentary testing access. Early-adopter locks, if available, apply only while the same tier and interval remain continuously subscribed.'
                                  : 'Switch to ${billingTier(offer['tier_code'])} at ${billingPrice(offer)} USD on ${date(sub['period_end'])}. Your current paid membership stays in place until then. Changing tier or billing interval removes your current price lock. Your next charge will use the selected price.';
                              if (!await confirm(message) || !mounted) return;
                              await action(
                                sub == null ? 'checkout' : 'change-plan',
                                {
                                  'offer': offer['id'],
                                  'confirm': true,
                                  if (sub != null)
                                    'subscription': sub['stripe_subscription'],
                                  'accept_lock_loss': true,
                                },
                              );
                            },
                      child: Text(
                        subscriptions.isEmpty
                            ? 'Choose plan'
                            : 'Switch at renewal',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (data?['checkout_enabled'] == false)
            const Text('Online purchases are not enabled yet.'),
          const Text(
            'Sold, deceased, archived and pedigree-only records do not count toward active-animal limits. Prices shown in USD. Payment is confirmed by Stripe; returning to this page alone does not activate a membership.',
          ),
        ],
      ),
    );
  }
}
