import '../widgets/adaptive_layout.dart';
import '../widgets/pedigree_email_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sale_record.dart';
import '../services/sales_service.dart';
import '../widgets/ringmaster_page_shell.dart';
import '../widgets/bulk_sale_dialog.dart';

class SalesDashboardScreen extends StatefulWidget {
  final String ownerId;
  final String? ringId;
  final Future<List<SaleRecord>> Function()? loadSales;
  const SalesDashboardScreen({
    super.key,
    required this.ownerId,
    this.ringId,
    this.loadSales,
  });
  @override
  State<SalesDashboardScreen> createState() => _SalesDashboardScreenState();
}

class _SalesDashboardScreenState extends State<SalesDashboardScreen> {
  late Future<List<SaleRecord>> records;
  String filter = 'Open', query = '';
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    final next =
        widget.loadSales?.call() ??
        SalesService.list(widget.ownerId, ringId: widget.ringId);
    setState(() {
      records = next;
    });
  }

  Future<void> add(List<SaleRecord> sales) async {
    try {
      final farms = List<Map<String, dynamic>>.from(
        await SalesService.client
            .from('farms')
            .select('id')
            .eq('owner_id', widget.ownerId),
      );
      final candidates = <Map<String, dynamic>>[];
      for (final farm in farms) {
        if (widget.ringId != null && farm['id'] != widget.ringId) continue;
        for (var offset = 0; ; offset += 500) {
          final page = List<Map<String, dynamic>>.from(
            await SalesService.client
                .from('animals')
                .select('id,ring_id,name,tattoo,breed,status,pedigree_only')
                .eq('ring_id', farm['id'])
                .eq('status', 'active')
                .eq('pedigree_only', false)
                .order('id')
                .range(offset, offset + 499),
          );
          candidates.addAll(page);
          if (page.length < 500) break;
        }
      }
      final listed = sales
          .where((s) => s.open)
          .map((s) => s.data['animal_id'])
          .toSet();
      candidates.removeWhere((a) => listed.contains(a['id']));
      if (!mounted) return;
      final n = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => BulkSaleDialog(animals: candidates),
      );
      if (n != null && mounted) {
        refresh();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$n animals marked For Sale.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load animals. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> edit(SaleRecord sale) async {
    final savedStatus = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SaleEditDialog(sale: sale),
    );
    if (savedStatus != null && mounted) {
      if (savedStatus == 'sold') {
        setState(() {
          filter = 'Sold';
          query = '';
        });
      }
      refresh();
    }
  }

  Future<void> emailPedigree(SaleRecord sale) async {
    await offerBuyerPedigree(
      context,
      animalId: sale.data['animal_id'],
      saleId: sale.id,
      buyerEmail: sale.data['buyer_email'] ?? '',
    );
    if (mounted) refresh();
  }

  Future<void> payment(SaleRecord sale) async {
    final savedStatus = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SalePaymentDialog(sale: sale),
    );
    if (savedStatus != null && mounted) {
      if (savedStatus == 'sold') {
        setState(() {
          filter = 'Sold';
          query = '';
        });
      }
      refresh();
    }
  }

  Future<void> history(SaleRecord sale) async {
    await showDialog<void>(
      context: context,
      builder: (_) => SaleHistoryDialog(sale: sale),
    );
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Sales',
    isSalesPage: true,
    onRefresh: refresh,
    body: FutureBuilder<List<SaleRecord>>(
      future: records,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to load sales.'),
                TextButton(onPressed: refresh, child: const Text('Try again')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        final visible = all.where((s) {
          final matches = switch (filter) {
            'Open' => s.open,
            'History' => !s.open,
            'All' => true,
            _ => saleStatus(s.status) == filter,
          };
          return matches &&
              '${s.data['animal_name']} ${s.data['buyer_name']} ${s.data['buyer_email']}'
                  .toLowerCase()
                  .contains(query.toLowerCase());
        }).toList();
        final net = all.fold<int>(0, (n, s) => n + s.paid);
        final due = all
            .where((s) => s.status != 'cancelled')
            .fold<int>(0, (n, s) => n + (s.balance ?? 0));
        return ListView(
          padding: BreederLayout.pagePadding(context, normal: 20),
          children: [
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  widget.ringId == null ? 'Family sales' : 'Herd sales',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                FilledButton.icon(
                  onPressed: () => add(all),
                  icon: const Icon(Icons.add),
                  label: const Text('Add animals'),
                ),
              ],
            ),
            const AdaptiveGap(height: 16),
            AdaptiveOverview(
              title: 'Sales overview',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  summary(
                    'For Sale',
                    '${all.where((s) => s.status == 'for_sale').length}',
                  ),
                  summary(
                    'Reserved',
                    '${all.where((s) => s.status == 'reserved').length}',
                  ),
                  summary(
                    'Sold',
                    '${all.where((s) => s.status == 'sold').length}',
                  ),
                  summary('Net received', saleMoney(net)),
                  summary('Balance due', saleMoney(due)),
                ],
              ),
            ),
            if (all.any((s) => !s.paymentHistoryComplete))
              Text(
                '${all.where((s) => !s.paymentHistoryComplete).length} historical sales have unrecorded payment history; their balances are excluded.',
              ),
            const AdaptiveGap(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    initialValue: filter,
                    decoration: const InputDecoration(labelText: 'Show'),
                    items:
                        [
                              'Open',
                              'For Sale',
                              'Reserved',
                              'Sold',
                              'History',
                              'All',
                            ]
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => filter = v!),
                  ),
                ),
                SizedBox(
                  width: BreederLayout.compact(context)
                      ? MediaQuery.sizeOf(context).width - 24
                      : 300,
                  child: TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                      labelText: 'Search animal or buyer',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
              ],
            ),
            const AdaptiveGap(height: 16),
            if (filter == 'Open')
              AdaptivePadding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextButton.icon(
                  onPressed: () => setState(() => filter = 'Sold'),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('View sold animals and email pedigrees'),
                ),
              ),
            if (visible.isEmpty)
              const AdaptivePadding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'No sales in this view. Use Add animals to start a listing.',
                ),
              ),
            for (final sale in visible)
              Card(
                child: AdaptivePadding(
                  padding: BreederLayout.pagePadding(context, normal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              sale.data['animal_name'],
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Chip(label: Text(saleStatus(sale.status))),
                        ],
                      ),
                      if (sale.imported)
                        Text(
                          'Imported from Global Pedigree • Sale ${sale.data['import_source_id']}',
                        ),
                      if ((sale.data['buyer_name'] as String).isNotEmpty)
                        Text('Buyer: ${sale.data['buyer_name']}'),
                      if (sale.data['sale_date'] != null)
                        Text('Sold: ${sale.data['sale_date']}'),
                      const AdaptiveGap(height: 8),
                      Wrap(
                        spacing: 20,
                        runSpacing: 8,
                        children: [
                          Text('Asking: ${saleMoney(sale.asking)}'),
                          Text(
                            'Agreed: ${saleMoney((sale.data['sale_cents'] as num?)?.toInt())}',
                          ),
                          Text(
                            'Deposits: ${sale.paymentHistoryComplete ? saleMoney(sale.deposits) : 'Not recorded'}',
                          ),
                          Text(
                            'Net paid: ${sale.paymentHistoryComplete ? saleMoney(sale.paid) : 'Not recorded'}',
                          ),
                          Text(
                            'Balance: ${sale.paymentHistoryComplete ? saleMoney(sale.balance) : 'Not recorded'}',
                          ),
                          Text(sale.paymentStatus),
                        ],
                      ),
                      const AdaptiveGap(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (sale.status != 'cancelled')
                            TextButton.icon(
                              onPressed: () => edit(sale),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit sale'),
                            ),
                          if (sale.status != 'cancelled')
                            TextButton.icon(
                              onPressed: () => payment(sale),
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('Record payment / refund'),
                            ),
                          if (sale.status == 'sold')
                            FilledButton.icon(
                              onPressed: () => emailPedigree(sale),
                              icon: const Icon(Icons.email_outlined),
                              label: const Text('Email pedigree to buyer'),
                            ),
                          TextButton.icon(
                            onPressed: () => history(sale),
                            icon: const Icon(Icons.history),
                            label: const Text('History'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
  Widget summary(String label, String value) => SizedBox(
    width: MediaQuery.sizeOf(context).width < 500
        ? (MediaQuery.sizeOf(context).width - 52) / 2
        : 190,
    child: Card(
      child: AdaptivePadding(
        padding: BreederLayout.pagePadding(context, normal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    ),
  );
}

String salesError(Object e) => e is PostgrestException
    ? e.code == 'P0001'
          ? e.message
          : e.code == '23505'
          ? 'This animal is already listed. Refresh and try again.'
          : e.code == '42501'
          ? 'Family access is no longer available.'
          : 'Unable to save. Check the amounts and dates, then try again.'
    : e is FormatException
    ? e.message
    : e is StateError
    ? e.message
    : 'Unable to save. Check your connection and try again.';

class SaleEditDialog extends StatefulWidget {
  final SaleRecord sale;
  const SaleEditDialog({super.key, required this.sale});
  @override
  State<SaleEditDialog> createState() => _SaleEditDialogState();
}

class _SaleEditDialogState extends State<SaleEditDialog> {
  late final fields = {
    for (final k in [
      'buyer_name',
      'buyer_email',
      'buyer_phone',
      'buyer_address',
      'notes',
    ])
      k: TextEditingController(text: widget.sale.data[k] ?? ''),
  };
  late final asking = TextEditingController(
    text: widget.sale.asking == null
        ? ''
        : (widget.sale.asking! / 100).toStringAsFixed(2),
  );
  late final agreed = TextEditingController(
    text: widget.sale.data['sale_cents'] == null
        ? ''
        : ((widget.sale.data['sale_cents'] as num) / 100).toStringAsFixed(2),
  );
  late String status = widget.sale.status;
  late DateTime? date = DateTime.tryParse(widget.sale.data['sale_date'] ?? '');
  late bool paymentComplete = widget.sale.paymentHistoryComplete;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    for (final c in [...fields.values, asking, agreed]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    try {
      final askingCents = parseSaleMoney(asking.text),
          saleCents = parseSaleMoney(agreed.text);
      if (!widget.sale.imported &&
          ['reserved', 'sold'].contains(status) &&
          fields['buyer_name']!.text.trim().isEmpty) {
        throw StateError('Enter the buyer name.');
      }
      if (!widget.sale.imported &&
          status == 'sold' &&
          (saleCents == null || date == null)) {
        throw StateError('Enter the agreed sale price and sale date.');
      }
      if (status == 'cancelled') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cancel this listing?'),
            content: const Text(
              'It will stay in sales history. Any payments must be refunded first.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep listing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancel listing'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      setState(() {
        saving = true;
        error = null;
      });
      final savedStatus = await SalesService.update(widget.sale, {
        'status': status,
        if (widget.sale.imported) 'payment_history_complete': paymentComplete,
        'asking_cents': askingCents,
        'sale_cents': saleCents,
        'sale_date': date == null
            ? null
            : DateFormat('yyyy-MM-dd').format(date!),
        for (final e in fields.entries) e.key: e.value.text.trim(),
      });
      status = savedStatus;
      if (mounted && status == 'sold' && widget.sale.status != 'sold') {
        await offerBuyerPedigree(
          context,
          animalId: widget.sale.data['animal_id'],
          saleId: widget.sale.id,
          buyerEmail: fields['buyer_email']!.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, status);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = salesError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AdaptiveFormDialog(
      title: Text(widget.sale.data['animal_name']),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: AbsorbPointer(
            absorbing: saving,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(
                    labelText: 'Sale status',
                    helperText:
                        'Buyer name reserves the rabbit. Full agreed payment marks it Sold.',
                    helperMaxLines: 3,
                  ),
                  items:
                      (widget.sale.status == 'sold'
                              ? ['sold']
                              : ['for_sale', 'reserved', 'sold', 'cancelled'])
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(saleStatus(s)),
                            ),
                          )
                          .toList(),
                  onChanged: widget.sale.status == 'sold'
                      ? null
                      : (v) => setState(() => status = v!),
                ),
                if (widget.sale.imported)
                  CheckboxListTile(
                    value: paymentComplete,
                    onChanged: (v) => setState(() => paymentComplete = v!),
                    title: const Text('Payment history is complete'),
                    subtitle: const Text(
                      'Confirm after recording all payments and refunds.',
                    ),
                  ),
                field(asking, 'Asking price (USD)', money: true),
                field(agreed, 'Agreed sale price (USD)', money: true),
                for (final e in fields.entries)
                  field(e.value, switch (e.key) {
                    'buyer_name' => 'Buyer name',
                    'buyer_email' => 'Buyer email',
                    'buyer_phone' => 'Buyer phone',
                    'buyer_address' => 'Buyer address',
                    _ => 'Private notes',
                  }, lines: ['buyer_address', 'notes'].contains(e.key) ? 3 : 1),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: date ?? DateTime.now(),
                      firstDate: widget.sale.imported
                          ? DateTime(1)
                          : DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (d != null && mounted) setState(() => date = d);
                  },
                  icon: const Icon(Icons.event),
                  label: Text(
                    date == null
                        ? 'Set sale date'
                        : 'Sale date: ${DateFormat.yMd().format(date!)}',
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Save sale'),
        ),
      ],
    ),
  );
  Widget field(
    TextEditingController c,
    String label, {
    bool money = false,
    int lines = 1,
  }) => AdaptivePadding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: c,
      maxLines: BreederLayout.fieldLines(context, lines),
      keyboardType: money
          ? const TextInputType.numberWithOptions(decimal: true)
          : lines > 1
          ? TextInputType.multiline
          : null,
      decoration: InputDecoration(labelText: label),
    ),
  );
}

class SalePaymentDialog extends StatefulWidget {
  final SaleRecord sale;
  const SalePaymentDialog({super.key, required this.sale});
  @override
  State<SalePaymentDialog> createState() => _SalePaymentDialogState();
}

class _SalePaymentDialogState extends State<SalePaymentDialog> {
  final amount = TextEditingController(),
      method = TextEditingController(),
      reference = TextEditingController(),
      notes = TextEditingController();
  final id = SalesService.newId();
  String kind = 'deposit';
  DateTime date = DateTime.now();
  bool saving = false;
  String? error;
  Map<String, dynamic>? submitted;
  @override
  void dispose() {
    for (final c in [amount, method, reference, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    try {
      final cents = parseSaleMoney(amount.text);
      if (cents == null || cents <= 0) {
        throw StateError('Enter a positive amount.');
      }
      final payload = {
        'kind': kind,
        'amount_cents': cents,
        'paid_on': DateFormat('yyyy-MM-dd').format(date),
        'method': method.text.trim(),
        'reference': reference.text.trim(),
        'notes': notes.text.trim(),
      };
      if (submitted != null &&
          payload.entries.any((e) => submitted![e.key] != e.value)) {
        throw StateError(
          'Close and refresh to check the prior payment before changing it.',
        );
      }
      submitted = payload;
      setState(() {
        saving = true;
        error = null;
      });
      final savedStatus = await SalesService.payment(
        id,
        widget.sale.id,
        payload,
      );
      if (mounted && savedStatus == 'sold' && widget.sale.status != 'sold') {
        await offerBuyerPedigree(
          context,
          animalId: widget.sale.data['animal_id'],
          saleId: widget.sale.id,
          buyerEmail: widget.sale.data['buyer_email'] ?? '',
        );
      }
      if (mounted) Navigator.pop(context, savedStatus);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          if (e is PostgrestException &&
              ['P0001', '23514', '23503', '42501'].contains(e.code)) {
            submitted = null;
          }
          error = salesError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AdaptiveFormDialog(
      title: const Text('Record payment or refund'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: AbsorbPointer(
            absorbing: saving,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Balance due: ${saleMoney(widget.sale.balance)} • Net paid: ${saleMoney(widget.sale.paid)}',
                ),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  items: ['deposit', 'payment', 'refund']
                      .map(
                        (k) => DropdownMenuItem(
                          value: k,
                          child: Text(k[0].toUpperCase() + k.substring(1)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => kind = v!),
                  decoration: const InputDecoration(labelText: 'Record type'),
                ),
                for (final f in [
                  (amount, 'Amount (USD)'),
                  (method, 'Method, e.g. cash or check'),
                  (reference, 'Reference / receipt number'),
                  (notes, 'Notes'),
                ])
                  AdaptivePadding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: f.$1,
                      keyboardType: f.$1 == amount
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : null,
                      decoration: InputDecoration(labelText: f.$2),
                    ),
                  ),
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (d != null && mounted) setState(() => date = d);
                  },
                  child: Text('Date: ${DateFormat.yMd().format(date)}'),
                ),
                const Text(
                  'This records money you received or refunded. It does not charge the buyer.',
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Save record'),
        ),
      ],
    ),
  );
}

class SaleHistoryDialog extends StatefulWidget {
  final SaleRecord sale;
  const SaleHistoryDialog({super.key, required this.sale});
  @override
  State<SaleHistoryDialog> createState() => _SaleHistoryDialogState();
}

class _SaleHistoryDialogState extends State<SaleHistoryDialog> {
  late final future = SalesService.history(widget.sale.id);
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('History • ${widget.sale.data['animal_name']}'),
    content: SizedBox(
      width: 600,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Unable to load history. Close and try again.');
          }
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final events = [...snapshot.data!]
            ..sort(
              (a, b) => (b['created_at'] as String).compareTo(
                a['created_at'] as String,
              ),
            );
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in events)
                  AdaptivePadding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e['event']} • ${DateFormat.yMd().add_jm().format(DateTime.parse(e['created_at']).toLocal())}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(describe(e)),
                      ],
                    ),
                  ),
                if (events.isEmpty) const Text('No history recorded.'),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
  String describe(Map<String, dynamic> event) {
    final d = Map<String, dynamic>.from(event['details'] as Map);
    if (event['event'] == 'pedigree_email_accepted') {
      return 'Pedigree PDF and JSON email accepted for ${d['recipient']}';
    }
    if (['deposit', 'payment', 'refund'].contains(event['event'])) {
      return '${saleMoney((d['amount_cents'] as num).toInt())} • ${d['paid_on']}\n${d['method']} ${d['reference']}\n${d['notes']}';
    }
    final after = Map<String, dynamic>.from(d['after'] as Map);
    final before = d['before'] as Map?;
    const labels = {
      'status': 'Status',
      'asking_cents': 'Asking price',
      'sale_cents': 'Agreed price',
      'buyer_name': 'Buyer',
      'buyer_email': 'Email',
      'buyer_phone': 'Phone',
      'buyer_address': 'Address',
      'sale_date': 'Sale date',
      'notes': 'Notes',
    };
    String value(String key, dynamic v) => key.endsWith('_cents')
        ? saleMoney((v as num?)?.toInt())
        : key == 'status'
        ? saleStatus(v?.toString() ?? '')
        : (v?.toString().isNotEmpty == true ? v.toString() : 'Not recorded');
    final changes = [
      for (final key in labels.keys)
        if (before == null || before[key] != after[key])
          '${labels[key]}: ${before == null ? '' : '${value(key, before[key])} → '}${value(key, after[key])}',
    ];
    return changes.join('\n');
  }
}
