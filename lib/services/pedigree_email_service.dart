import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sales_service.dart';
import 'pedigree_pdf_service.dart';
import 'pedigree_service.dart';
import 'family_service.dart';
import 'license_service.dart';
import '../offline/offline_runtime.dart';

class PedigreeEmailDraft {
  final String requestId, ownerName, ownerEmail, buyerEmail;
  final Uint8List pdf;
  final Map<String, dynamic>? approvedSnapshot;
  final String? saleId;
  const PedigreeEmailDraft({
    required this.requestId,
    required this.ownerName,
    required this.ownerEmail,
    this.buyerEmail = '',
    required this.pdf,
    this.approvedSnapshot,
    this.saleId,
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
  bool queued = false;
  Future<Map<String, dynamic>> call(Map<String, dynamic> body) async {
    try {
      final result = await OfflineRuntime.client.functions.invoke(
        'email-buyer-pedigree',
        body: body,
      );
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['queued'] == true) {
        queued = true;
        return data;
      }
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
    final license = await fetchLicenseStatus(FamilyService.ownerId!);
    if (!license.buyerPedigreeEmail) {
      throw StateError(
        'Emailing pedigrees to buyers requires Professional Breeder or Top Tier. Your sale remains saved.',
      );
    }
    if (OfflineRuntime.workspaceReady) {
      final client = OfflineRuntime.client;
      final owner = await client
          .from('users')
          .select()
          .eq('id', FamilyService.ownerId!)
          .single();
      final pedigree = await PedigreeService.build(animalId);
      String buyer = '';
      if (saleId != null) {
        final sale = await client
            .from('animal_sales')
            .select('buyer_email')
            .eq('id', saleId)
            .single();
        buyer = sale['buyer_email'] ?? '';
      }
      return PedigreeEmailDraft(
        requestId: requestId,
        ownerName: owner['display_name'] ?? owner['username'] ?? 'Breeder',
        ownerEmail: owner['email'] ?? '',
        buyerEmail: buyer,
        pdf: await PedigreePdfService.generate(pedigree: pedigree),
        approvedSnapshot: pedigree,
        saleId: saleId,
      );
    }
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
      if (draft.approvedSnapshot != null)
        'approved_snapshot': draft.approvedSnapshot,
      if (draft.approvedSnapshot != null)
        'approved_owner_name': draft.ownerName,
      if (draft.approvedSnapshot != null)
        'approved_owner_email': draft.ownerEmail,
      if (draft.saleId != null) 'sale_id': draft.saleId,
    });
  }

  static String requestId() => SalesService.newId();
}
