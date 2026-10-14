import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/services/pedigree_email_service.dart';
import 'package:ringmaster_breeder/widgets/pedigree_email_dialog.dart';

class FakeEmail implements PedigreeEmailGateway {
  int prepared = 0, sent = 0;
  bool fail = false;
  String? recipient, id;
  @override
  Future<PedigreeEmailDraft> prepare(
    String requestId,
    String animalId,
    String? saleId,
  ) async {
    prepared++;
    return PedigreeEmailDraft(
      requestId: requestId,
      ownerName: 'Family Owner',
      ownerEmail: 'owner@example.com',
      buyerEmail: 'buyer@example.com',
      pdf: Uint8List.fromList([37, 80, 68, 70]),
    );
  }

  @override
  Future<void> send(
    PedigreeEmailDraft draft,
    String animalId,
    String email,
  ) async {
    sent++;
    recipient = email;
    id = draft.requestId;
    if (fail) throw StateError('Retry this same email.');
  }
}

void main() {
  testWidgets(
    'offer pre-fills buyer, shows owner and attachments, and never auto sends',
    (tester) async {
      final gateway = FakeEmail();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PedigreeEmailDialog(animalId: 'animal', gateway: gateway),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('From: Family Owner'), findsOneWidget);
      expect(find.text('Replies go to: owner@example.com'), findsOneWidget);
      expect(
        find.text('Attachments: pedigree.pdf and pedigree.json'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextField, 'buyer@example.com'),
        findsOneWidget,
      );
      expect(gateway.sent, 0);
      await tester.tap(find.text('Send PDF and JSON'));
      await tester.pumpAndSettle();
      expect(gateway.sent, 1);
      expect(gateway.recipient, 'buyer@example.com');
      expect(find.text('Pedigree email submitted'), findsOneWidget);
    },
  );
  testWidgets(
    'failed send retries the same request without preparing a different PDF',
    (tester) async {
      final gateway = FakeEmail()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PedigreeEmailDialog(animalId: 'animal', gateway: gateway),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send PDF and JSON'));
      await tester.pumpAndSettle();
      final id = gateway.id;
      gateway.fail = false;
      await tester.tap(find.text('Retry same email'));
      await tester.pumpAndSettle();
      expect(gateway.id, id);
      expect(gateway.prepared, 1);
      expect(gateway.sent, 2);
    },
  );
  testWidgets('invalid buyer email blocks sending', (tester) async {
    final gateway = FakeEmail();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PedigreeEmailDialog(animalId: 'animal', gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.tap(find.text('Send PDF and JSON'));
    await tester.pumpAndSettle();
    expect(gateway.sent, 0);
    expect(find.text('Enter the buyer’s email address.'), findsOneWidget);
  });
}
