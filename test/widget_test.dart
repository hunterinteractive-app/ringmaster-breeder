import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/login_screen.dart';
import 'package:ringmaster_breeder/services/auth_service.dart';
import 'package:ringmaster_breeder/utils/animal_labels.dart';
import 'package:ringmaster_breeder/utils/pedigree_counts.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/app_shell.dart';
import 'package:ringmaster_breeder/widgets/ringmaster_page_shell.dart';

class FakeAuth implements AuthGateway {
  String? email;
  String? code;
  int requests = 0;
  bool fail = false;
  @override
  Future<void> requestCode(String email) async {
    requests++;
    this.email = email;
    if (fail) throw Exception('offline');
  }

  @override
  Future<void> verifyCode(String email, String code) async {
    this.email = email;
    this.code = code;
    if (fail) throw Exception('expired');
  }
}

void main() {
  test('Repeated ancestry counts actual slots and excludes the subject', () {
    final counts = pedigreeCounts({
      'animal': {'id': 'subject'},
      'sire': {'id': 'sire'},
      'dam': null,
      'sire_sire': {'id': 'ancestor'},
      'dam_sire': {'id': 'ancestor'},
    });
    expect(counts, {'sire': 1, 'ancestor': 2});
  });
  test('Rabbit and cavy labels and historical locks', () {
    expect(sexLabel('Cavy', 'F'), 'Sow');
    expect(sexLabel('cavy', 'M'), 'Boar');
    expect(sexLabel('Rabbit', 'F'), 'Doe');
    expect(sexLabel('rabbit', 'Buck'), 'Buck');
    expect(sexLabel('rabbit', 'Doe'), 'Doe');
    expect(sexLabel('cavy', 'Boar'), 'Boar');
    expect(sexLabel('cavy', 'Sow'), 'Sow');
    expect(animalIsLocked('sold'), true);
    expect(animalIsLocked('retired'), false);
  });
  testWidgets(
    'Login validates, normalizes email, verifies code and prevents immediate resend',
    (tester) async {
      final auth = FakeAuth();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LoginScreen(auth: auth),
        ),
      );
      await tester.ensureVisible(find.text('Send sign-in code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send sign-in code'));
      await tester.pump();
      expect(auth.requests, 0);
      await tester.enterText(
        find.byType(TextFormField).first,
        ' FAMILY@EXAMPLE.COM ',
      );
      await tester.ensureVisible(find.text('Send sign-in code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send sign-in code'));
      await tester.pump();
      expect(auth.email, 'family@example.com');
      expect(auth.requests, 1);
      expect(find.text('Resend in 60 seconds'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).last, '123456');
      await tester.ensureVisible(find.text('Sign in'));
      await tester.pump();
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(auth.code, '123456');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Login failure remains actionable and displays no raw server errors',
    (tester) async {
      final auth = FakeAuth()..fail = true;
      await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth)));
      await tester.enterText(
        find.byType(TextFormField).first,
        'family@example.com',
      );
      await tester.ensureVisible(find.text('Send sign-in code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send sign-in code'));
      await tester.pump();
      expect(find.textContaining('We could not send a code'), findsOneWidget);
      expect(find.text('Send sign-in code'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Login policies open and return to the form', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoginScreen(auth: FakeAuth()),
      ),
    );
    for (final title in ['Terms of Service', 'Privacy Policy']) {
      await tester.ensureVisible(find.text(title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(
        find.text('Effective date: October 9, 2026 • Version 2026-10'),
        findsOneWidget,
      );
      expect(find.text('8. Permanent Deletion'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Shell fits a narrow screen with brand and version visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (_, child) => AppShell(child: child!),
        home: const RingMasterPageShell(
          title: 'My Rings',
          body: Text('Content'),
        ),
      ),
    );
    expect(find.text('RingMaster Breeder'), findsOneWidget);
    expect(find.text('Version 0.2.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
