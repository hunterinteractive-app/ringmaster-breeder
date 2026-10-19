import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/legal/legal_gate.dart';
import 'package:ringmaster_breeder/screens/profile_onboarding_gate.dart';
import 'package:ringmaster_breeder/services/record_import_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'legal_gate_test.dart' show FakeLegal, agree;
import 'record_import_test.dart' show FakeImport;

class FakeOnboarding implements ProfileOnboardingGateway {
  bool needed = true, fails = false;
  int checks = 0;
  Completer<bool>? pending;
  @override
  Future<bool> needsReview() async {
    checks++;
    if (fails) throw Exception('Unavailable');
    return pending == null ? needed : await pending!.future;
  }
}

class OnboardingImport extends FakeImport {
  OnboardingImport() : super(hasRing: false);
  bool lookupFails = false, importFails = false, noMatches = false;
  int lookups = 0;
  @override
  Future<Map<String, dynamic>> lookup() async {
    lookups++;
    if (lookupFails) throw Exception('Offline');
    if (noMatches) return {'status': 'not_found', 'matches': []};
    return super.lookup();
  }

  @override
  Future<Map<String, dynamic>> importRecords(Map<String, dynamic> selection) {
    if (importFails) throw StateError('Import unavailable');
    return super.importRecords(selection);
  }
}

Widget onboarding(FakeOnboarding gateway, OnboardingImport imports) =>
    ProfileOnboardingGate(
      gateway: gateway,
      importGateway: imports,
      child: const Text('Herd setup'),
    );

void main() {
  setUpAll(() async {
    if (kIsWeb) {
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        anonKey: 'test-key',
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
        ),
      );
    }
  });
  tearDownAll(() async {
    if (kIsWeb) await Supabase.instance.dispose();
  });
  testWidgets('Terms precede profile review, which precedes herd setup', (
    tester,
  ) async {
    final gateway = FakeOnboarding();
    final imports = OnboardingImport();
    await tester.pumpWidget(
      MaterialApp(
        home: LegalGate(
          gateway: FakeLegal(),
          child: onboarding(gateway, imports),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.checks, 0);
    expect(imports.lookups, 0);
    expect(find.text('Herd setup'), findsNothing);
    await agree(tester);
    expect(imports.lookups, 1);
    expect(find.text('Show exhibitor'), findsOneWidget);
    expect(find.text('Herd setup'), findsNothing);
    // Back cannot reveal the private application navigator.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Herd setup'), findsNothing);
    await tester.tap(find.text('Club'));
    await tester.pumpAndSettle();
    expect(find.text('Club exhibitor'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Continue without importing'),
      250,
    );
    await tester.tap(find.text('Continue without importing'));
    await tester.pumpAndSettle();
    expect(find.text('Herd setup'), findsOneWidget);
  });

  testWidgets(
    'Profile import works before a herd exists and continues to setup',
    (tester) async {
      final imports = OnboardingImport();
      await tester.pumpWidget(
        MaterialApp(home: onboarding(FakeOnboarding(), imports)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show exhibitor'));
      await tester.scrollUntilVisible(
        find.text('Import selected records'),
        250,
      );
      await tester.tap(find.text('Import selected records'));
      await tester.pumpAndSettle();
      expect(imports.selection?['profile_ids'], ['show-profile']);
      expect(imports.selection?['include_animals'], false);
      expect(find.text('Herd setup'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Continue to herd setup'), 150);
      await tester.tap(find.text('Continue to herd setup'));
      await tester.pumpAndSettle();
      expect(find.text('Herd setup'), findsOneWidget);
    },
  );

  testWidgets('No matches still presents onboarding before continuing', (
    tester,
  ) async {
    final imports = OnboardingImport()..noMatches = true;
    await tester.pumpWidget(
      MaterialApp(home: onboarding(FakeOnboarding(), imports)),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No matching Show or Club profiles'),
      findsOneWidget,
    );
    expect(find.text('Herd setup'), findsNothing);
    await tester.scrollUntilVisible(find.text('Continue to herd setup'), 150);
    await tester.tap(find.text('Continue to herd setup'));
    await tester.pumpAndSettle();
    expect(find.text('Herd setup'), findsOneWidget);
  });

  testWidgets('Failed import retains review and allows retry', (tester) async {
    final imports = OnboardingImport()..importFails = true;
    await tester.pumpWidget(
      MaterialApp(home: onboarding(FakeOnboarding(), imports)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show exhibitor'));
    await tester.scrollUntilVisible(find.text('Import selected records'), 250);
    await tester.tap(find.text('Import selected records'));
    await tester.pumpAndSettle();
    expect(find.text('Herd setup'), findsNothing);
    expect(find.text('Import successful'), findsNothing);
    expect(find.text('Import unavailable'), findsOneWidget);
    imports.importFails = false;
    await tester.ensureVisible(find.text('Import selected records'));
    await tester.tap(find.text('Import selected records'));
    await tester.pumpAndSettle();
    expect(find.text('Import successful'), findsOneWidget);
  });

  testWidgets(
    'Lookup failure cannot silently skip linking and can be retried',
    (tester) async {
      final imports = OnboardingImport()..lookupFails = true;
      await tester.pumpWidget(
        MaterialApp(home: onboarding(FakeOnboarding(), imports)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Herd setup'), findsNothing);
      expect(find.text('Continue without importing'), findsNothing);
      imports.lookupFails = false;
      await tester.scrollUntilVisible(find.text('Retry profile lookup'), 150);
      await tester.tap(find.text('Retry profile lookup'));
      await tester.pumpAndSettle();
      expect(imports.lookups, 2);
      expect(find.text('Show exhibitor'), findsOneWidget);
    },
  );

  testWidgets('Existing accounts bypass review; failed status checks retry', (
    tester,
  ) async {
    final gateway = FakeOnboarding()..fails = true;
    final imports = OnboardingImport();
    await tester.pumpWidget(MaterialApp(home: onboarding(gateway, imports)));
    await tester.pumpAndSettle();
    expect(find.text('Herd setup'), findsNothing);
    expect(imports.lookups, 0);
    gateway.fails = false;
    gateway.needed = false;
    await tester.tap(find.text('Retry profile check'));
    await tester.pumpAndSettle();
    expect(find.text('Herd setup'), findsOneWidget);
    expect(imports.lookups, 0);
  });

  testWidgets('Checking status never mounts herd setup early', (tester) async {
    final gateway = FakeOnboarding()..pending = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(home: onboarding(gateway, OnboardingImport())),
    );
    await tester.pump();
    expect(find.text('Herd setup'), findsNothing);
    gateway.pending!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Show exhibitor'), findsOneWidget);
    expect(find.text('Herd setup'), findsNothing);
  });
}
