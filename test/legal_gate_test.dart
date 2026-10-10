import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/legal/legal_gate.dart';
import 'package:ringmaster_breeder/services/legal_service.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';

class FakeLegal implements LegalGateway {
  bool accepted = false, checkFails = false, saveFails = false;
  int saves = 0, exits = 0;
  @override
  Future<bool> hasAccepted() async {
    if (checkFails) throw Exception();
    return accepted;
  }

  @override
  Future<void> accept() async {
    saves++;
    if (saveFails) throw Exception();
    accepted = true;
  }

  @override
  Future<void> signOut() async {
    exits++;
  }
}

Future<void> showGate(WidgetTester tester, FakeLegal gateway) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: LegalGate(gateway: gateway, child: const Text('Private dashboard')),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> agree(WidgetTester tester) async {
  for (final label in [
    'I have reviewed and agree to the Terms of Service',
    'I have reviewed and acknowledge the Privacy Policy',
  ]) {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.text('Agree and continue'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agree and continue'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Both agreements required; saved acceptance unlocks app', (
    tester,
  ) async {
    final gateway = FakeLegal();
    await showGate(tester, gateway);
    expect(find.text('Private dashboard'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    await agree(tester);
    expect(gateway.saves, 1);
    expect(find.text('Private dashboard'), findsOneWidget);
  });
  testWidgets(
    'Current acceptance skips review; outdated acceptance requires it',
    (tester) async {
      await showGate(tester, FakeLegal()..accepted = true);
      expect(find.text('Private dashboard'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await showGate(tester, FakeLegal());
      expect(find.text('Private dashboard'), findsNothing);
    },
  );
  testWidgets('Failed check and save cannot unlock the app', (tester) async {
    final gateway = FakeLegal()..checkFails = true;
    await showGate(tester, gateway);
    expect(find.text('Private dashboard'), findsNothing);
    gateway.checkFails = false;
    await tester.tap(find.text('Retry policy check'));
    await tester.pumpAndSettle();
    gateway.saveFails = true;
    await agree(tester);
    expect(find.text('Private dashboard'), findsNothing);
    expect(
      find.text('Unable to save your agreement. Please try again.'),
      findsOneWidget,
    );
    gateway.saveFails = false;
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();
    expect(find.text('Private dashboard'), findsOneWidget);
  });
  testWidgets('Review links return to blocked gate; sign out is available', (
    tester,
  ) async {
    final gateway = FakeLegal();
    await showGate(tester, gateway);
    await tester.tap(find.text('Review Terms of Service'));
    await tester.pumpAndSettle();
    expect(find.text('1. Use of the Platform'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Private dashboard'), findsNothing);
    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(gateway.exits, 1);
  });
}
