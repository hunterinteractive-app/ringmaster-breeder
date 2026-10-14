import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sales_service.dart';
import 'pedigree_pdf_service.dart';

class PedigreeEmailDraft {
  final String requestId, ownerName, ownerEmail, buyerEmail;
  final Uint8List pdf;
  const PedigreeEmailDraft({
    required this.requestId,
    required this.ownerName,
    required this.ownerEmail,
    this.buyerEmail = '',
    required this.pdf,
  });
}

abstract class PedigreeEmailGateway {
  Future<PedigreeEmailDraft> prepare(
    String requestId,
    String animalId,
    String? saleId,
  );
  Future<void> send(
    PedigreeEmailDraft draft,
    String animalId,
    String recipient,
  );
}

class PedigreeEmailService implements PedigreeEmailGateway {
  Future<Map<String, dynamic>> call(Map<String, dynamic> body) async {
    try {
      final result = await Supabase.instance.client.functions.invoke(
        'email-buyer-pedigree',
        body: body,
      );
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['error'] != null) throw StateError(data['error']);
      return data;
    } on FunctionException catch (e) {
      final details = e.details;
      throw StateError(
        details is Map && details['error'] is String
            ? details['error'] as String
            : 'Email is temporarily unavailable. The sale is saved.',
      );
    }
  }

  @override
  Future<PedigreeEmailDraft> prepare(
    String requestId,
    String animalId,
    String? saleId,
  ) async {
    final data = await call({
      'action': 'prepare',
      'request_id': requestId,
      'animal_id': animalId,
      if (saleId != null) 'sale_id': saleId,
    });
    final pedigree = Map<String, dynamic>.from(data['pedigree'] as Map);
    return PedigreeEmailDraft(
      requestId: requestId,
      ownerName: data['owner_name'],
      ownerEmail: data['owner_email'],
      buyerEmail: data['buyer_email'] ?? '',
      pdf: await PedigreePdfService.generate(pedigree: pedigree),
    );
  }

  @override
  Future<void> send(
    PedigreeEmailDraft draft,
    String animalId,
    String recipient,
  ) async {
    await call({
      'action': 'send',
      'request_id': draft.requestId,
      'animal_id': animalId,
      'recipient': recipient,
      'pdf': base64Encode(draft.pdf),
    });
  }

  static String requestId() => SalesService.newId();
}
