import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/registration_feedback_screen.dart';
import 'package:ringmaster_breeder/screens/registration_insights_screen.dart';

Map<String, dynamic> fixture({bool show = true}) => {
  'herd_tracking': '',
  'referred_by': '',
  'requested_features': '',
  'referral_code': 'RM-123456789ABC',
  'referred_signups': 0,
  'referral_recorded': false,
  'show_onboarding': show,
};
void main() {
  testWidgets('all questions can be skipped without any answers', (
    tester,
  ) async {
    final calls = <String>[];
    bool continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: RegistrationFeedbackScreen(
          initial: fixture(),
          request: (action, args) async {
            calls.add(action);
            return fixture();
          },
          onContinue: () => continued = true,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Skip for now'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(calls, ['skip']);
    expect(continued, isTrue);
  });
  testWidgets('optional answers save and remain available from Account', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: RegistrationFeedbackScreen(
          initial: fixture(),
          request: (action, args) async {
            saved = args;
            return {...fixture(), ...args, 'referral_recorded': true};
          },
        ),
      ),
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Paper and spreadsheets');
    await tester.enterText(fields.at(1), 'RM-FRIEND');
    await tester.enterText(fields.at(2), 'More pedigree layouts');
    await tester.scrollUntilVisible(
      find.text('Save answers'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Save answers'));
    await tester.pumpAndSettle();
    expect(saved?['herd_tracking'], 'Paper and spreadsheets');
    expect(saved?['referred_by'], 'RM-FRIEND');
    expect(saved?['requested_features'], 'More pedigree layouts');
    final referralField = find.widgetWithText(TextField, 'Referrer (optional)');
    await tester.scrollUntilVisible(
      referralField,
      -300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.widget<TextField>(referralField).enabled, isFalse);
    await tester.scrollUntilVisible(
      find.textContaining('Referral rewards are not currently enabled.'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.text('Referral rewards are not currently enabled.'),
      findsNothing,
    );
    expect(
      find.textContaining('Referral rewards are not currently enabled.'),
      findsOneWidget,
    );
  });
  testWidgets('existing members bypass signup questions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RegistrationFeedbackGate(
          request: (a, b) async => fixture(show: false),
          child: const Text('My herds'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My herds'), findsOneWidget);
  });
  testWidgets('optional survey outage does not block access', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RegistrationFeedbackGate(
          request: (a, b) async => throw Exception('offline'),
          child: const Text('My herds'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My herds'), findsOneWidget);
  });
  testWidgets('questions fit a narrow phone and skip remains usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: RegistrationFeedbackScreen(
          initial: fixture(),
          request: (a, b) async => fixture(),
          onContinue: () => continued = true,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Skip for now'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(continued, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('admin sees responses and linked signup totals', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RegistrationInsightsScreen(
          request: (a, b) async => {
            'responses': [
              {
                'display_name': 'Breeder',
                'email': 'breeder@example.test',
                'herd_tracking': 'Kintraks',
                'referred_by': 'Friend',
                'requested_features': 'Health reminders',
                'referral_code': 'RM-CODE',
                'referred_signups': 2,
              },
            ],
            'more': false,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Herd tracking: Kintraks'), findsOneWidget);
    expect(find.text('Feature requests: Health reminders'), findsOneWidget);
  });
}
