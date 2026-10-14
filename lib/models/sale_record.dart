class SaleRecord {
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> payments;
  const SaleRecord(this.data, [this.payments = const []]);
  String get id => data['id'] as String;
  String get status => data['status'] as String;
  int? get asking => (data['asking_cents'] as num?)?.toInt();
  int? get price => (data['sale_cents'] as num?)?.toInt() ?? asking;
  int get paid => payments.fold(
    0,
    (sum, p) =>
        sum +
        (p['kind'] == 'refund' ? -1 : 1) * (p['amount_cents'] as num).toInt(),
  );
  bool get imported => data['import_source'] == 'global_pedigree';
  bool get paymentHistoryComplete => data['payment_history_complete'] != false;
  int? get balance =>
      !paymentHistoryComplete || price == null ? null : price! - paid;
  int get deposits => payments
      .where((p) => p['kind'] == 'deposit')
      .fold(0, (sum, p) => sum + (p['amount_cents'] as num).toInt());
  bool get open => status == 'for_sale' || status == 'reserved';
  String get paymentStatus => !paymentHistoryComplete
      ? 'Payment history not recorded'
      : price == null
      ? 'Price not set'
      : balance == 0
      ? 'Paid in full'
      : paid == 0
      ? 'Unpaid'
      : 'Part paid';
}

int? parseSaleMoney(String text) {
  final value = text.trim();
  if (value.isEmpty) return null;
  if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException(
      'Enter an amount with up to two decimal places.',
    );
  }
  final pieces = value.split('.');
  return int.parse(pieces[0]) * 100 +
      (pieces.length == 1 ? 0 : int.parse(pieces[1].padRight(2, '0')));
}

String saleMoney(int? cents) =>
    cents == null ? 'Not set' : '\$${(cents / 100).toStringAsFixed(2)}';
String saleStatus(String status) => switch (status) {
  'for_sale' => 'For Sale',
  'reserved' => 'Reserved',
  'sold' => 'Sold',
  'cancelled' => 'Cancelled',
  _ => status,
};
