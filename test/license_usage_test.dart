import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/services/license_service.dart';
import 'package:ringmaster_breeder/widgets/license_usage_card.dart';

LicenseStatus status(int count, {DateTime? due, bool provisional = false}) =>
    LicenseStatus(
      hasActiveLicense: true,
      tierCode: 'HOBBY',
      tierName: 'Hobby Breeder',
      maxRings: 1,
      currentRings: 1,
      maxActiveAnimals: 50,
      activeAnimals: count,
      annualPriceCents: 4900,
      graceEndsAt: due,
      provisional: provisional,
    );
void main() {
  test('warning thresholds use actual percentage without rounding up', () {
    expect(status(37).warningLevel, 0);
    expect(status(38).warningLevel, 75);
    expect(status(42).warningLevel, 75);
    expect(status(43).warningLevel, 85);
    expect(status(47).warningLevel, 85);
    expect(status(48).warningLevel, 95);
    expect(status(50).warningLevel, 100);
    expect(status(80).warningLevel, 100);
  });
  test('server entitlements and deadline are retained', () {
    final value = LicenseStatus.fromJson({
      'active': true,
      'code': 'PRO',
      'name': 'Professional Breeder',
      'max_rings': 1,
      'current_rings': 1,
      'max_active_animals': 250,
      'active_count': 260,
      'annual_price_cents': 9900,
      'buyer_pedigree_email': true,
      'custom_pedigree_branding': true,
      'saved_pedigree_layouts': true,
      'growth_blocked': true,
      'grace_ends_at': '2026-10-01T00:00:00Z',
    });
    expect(
      value.buyerPedigreeEmail &&
          value.customPedigreeBranding &&
          value.savedPedigreeLayouts,
      isTrue,
    );
    expect(value.growthBlocked, isTrue);
    expect(value.graceEndsAt, DateTime.utc(2026, 10, 1));
  });
  for (final count in [38, 43, 48, 50, 60]) {
    testWidgets('usage $count fits a narrow phone with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LicenseUsageCard(status: status(count, provisional: true)),
            ),
          ),
        ),
      );
      expect(find.text('$count / 50 active animals'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, lessThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'expired grace keeps record access and upgrade instructions visible',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LicenseUsageCard(
              status: status(
                52,
                due: DateTime.now().subtract(const Duration(days: 1)),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('grace period has ended'), findsOneWidget);
      await tester.tap(find.text('View plans'));
      await tester.pumpAndSettle();
      expect(find.text('Membership & billing'), findsOneWidget);
      expect(find.text('Retry / refresh payment status'), findsOneWidget);
    },
  );
}
