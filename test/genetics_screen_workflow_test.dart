import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_breeder/config/genetics_preview.dart';
import 'package:ringmaster_breeder/screens/animal_list_screen.dart';
import 'package:ringmaster_breeder/screens/genetics_screen.dart';
import 'package:ringmaster_breeder/services/family_service.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/genetics_prediction_results.dart';

const captureKey = ValueKey('genetics-screen-capture');

class _MemoryAuthStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async => values.remove(key);
}

ThemeData get screenTheme => AppTheme.light.copyWith(
  textTheme: AppTheme.light.textTheme.apply(fontFamily: 'BreederSans'),
);
Map<String, dynamic> rabbit(
  String id,
  String sex, {
  String breed = 'Tan',
  String variety = 'Black',
  String? name,
}) => {
  'id': id,
  'name': name ?? id,
  'tattoo': id,
  'species': 'rabbit',
  'sex': sex,
  'status': 'active',
  'breed': breed,
  'variety': variety,
  'dob': '2025-04-03',
  'pedigree_only': false,
};

final samples = [
  rabbit(
    'buck',
    'M',
    name: 'A very long registered rabbit name with breeder prefix',
  ),
  rabbit(
    'doe',
    'F',
    name: 'Another long registered rabbit name for narrow screens',
  ),
  rabbit('blue', 'M', variety: 'Blue'),
  rabbit('unsupported', 'F', breed: 'Mini Rex', variety: 'White'),
];

Future<void> identity(String email) async {
  final expiration = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String encoded(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  // Synthetic in-memory session, never a request to a real authentication host.
  // ignore: invalid_use_of_internal_member
  await Supabase.instance.client.auth.setInitialSession(
    jsonEncode({
      'access_token':
          '${encoded({})}.${encoded({'sub': 'screen-user', 'exp': expiration})}.fixture',
      'refresh_token': 'fixture',
      'token_type': 'bearer',
      'user': {
        'id': 'screen-user',
        'email': email,
        'app_metadata': {},
        'user_metadata': {'email': 'zaynetort2@gmail.com'},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

Widget preview(List<Map<String, dynamic>> animals, {double textScale = 1}) =>
    MaterialApp(
      theme: screenTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(key: captureKey, child: child!),
      ),
      home: GeneticsScreen(animals: animals),
    );

Future<void> choose(WidgetTester tester, Finder field, String text) async {
  await tester.ensureVisible(field);
  // At 200% text a four-line selector can exceed the available phone body.
  // Its visible top remains tappable even when its center is off-screen.
  await tester.tapAt(tester.getTopLeft(field) + const Offset(20, 20));
  await tester.pumpAndSettle();
  final item = find.textContaining(text).last;
  await tester.ensureVisible(item);
  await tester.tapAt(tester.getTopLeft(item) + const Offset(8, 8));
  await tester.pumpAndSettle();
}

Future<void> calculate(WidgetTester tester) async {
  final button = find.text('See Possible Colors');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(GeneticsPredictionResults), findsOneWidget);
  expect(find.text('Tan coat-color estimates').hitTestable(), findsOneWidget);
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('GENETICS_SCREEN_CAPTURES')) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('docs/genetics/screen-captures');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <String>[];
  setUpAll(() async {
    await (FontLoader(
      'BreederSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await Supabase.initialize(
      url: 'https://genetics-screen.invalid',
      anonKey: 'test-only',
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return http.Response(
          jsonEncode(
            request.url.path == '/rest/v1/animals' &&
                    int.parse(request.url.queryParameters['offset'] ?? '0') == 0
                ? samples
                : [],
          ),
          200,
          headers: {'Content-Type': 'application/json'},
          request: request,
        );
      }),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAuthStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });
  setUp(() async {
    requests.clear();
    FamilyService.clear();
    await identity('zaynetort2@gmail.com');
  });
  tearDownAll(() async => Supabase.instance.dispose());

  for (final scenario in [
    ('small-phone', const Size(320, 568), 1.0),
    ('phone', const Size(390, 844), 1.0),
    ('landscape', const Size(844, 390), 1.0),
    ('desktop', const Size(1440, 900), 1.0),
    ('large-text', const Size(320, 844), 2.0),
  ]) {
    testWidgets('Full Genetics screen fits and recalculates: ${scenario.$1}', (
      tester,
    ) async {
      tester.view.physicalSize = scenario.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = jsonEncode(samples);
      await tester.pumpWidget(preview(samples, textScale: scenario.$3));
      await tester.pumpAndSettle();
      expect(find.text(GeneticsPreview.disclaimer), findsOneWidget);
      await capture(tester, '${scenario.$1}-initial');
      await choose(
        tester,
        find.byType(DropdownButtonFormField<String>).first,
        'A very long',
      );
      await choose(
        tester,
        find.byType(DropdownButtonFormField<String>).last,
        'Another long',
      );
      expect(find.text('Breed: Tan • Variety: Black'), findsNWidgets(2));
      expect(find.text('DOB: 04/03/2025'), findsNWidgets(2));
      await calculate(tester);
      await tester.ensureVisible(find.text('Tan coat-color estimates'));
      await capture(tester, '${scenario.$1}-results');
      expect(find.textContaining('not fixed odds'), findsOneWidget);
      final affects = find.text('What affects these estimates?');
      await tester.ensureVisible(affects);
      await tester.tap(affects);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Keep Unknown when you do not know'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text(GeneticsPreview.disclaimer).last);
      await capture(tester, '${scenario.$1}-notice');
      await choose(
        tester,
        find.byType(DropdownButtonFormField<String>).first,
        'blue • blue',
      );
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      await calculate(tester);
      expect(find.text('Tan coat-color estimates'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(jsonEncode(samples), original);
      expect(requests, isEmpty);
    });
  }

  testWidgets(
    'Empty lists disable calculation and missing/invalid pair recovers',
    (tester) async {
      await tester.pumpWidget(preview([]));
      await tester.pumpAndSettle();
      expect(find.text('No active rabbits available'), findsNWidgets(2));
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(preview(samples));
      await tester.pumpAndSettle();
      await choose(
        tester,
        find.byType(DropdownButtonFormField<String>).first,
        'A very long',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      await choose(
        tester,
        find.byType(DropdownButtonFormField<String>).last,
        'unsupported • unsupported',
      );
      expect(find.text('Prediction unavailable'), findsOneWidget);
      expect(find.textContaining('support@ringmasterone.com'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      await choose(
        tester,
        find.byType(DropdownButtonFormField<String>).last,
        'Another long',
      );
      expect(find.text('Prediction unavailable'), findsNothing);
      await calculate(tester);
      expect(tester.takeException(), isNull);
      expect(requests, isEmpty);
    },
  );

  testWidgets(
    'Carrier conflict clears results and restoring Unknown recovers',
    (tester) async {
      await tester.pumpWidget(preview(samples));
      await tester.pumpAndSettle();
      await choose(
        tester,
        find.byType(DropdownButtonFormField<String>).first,
        'A very long',
      );
      await choose(
        tester,
        find.byType(DropdownButtonFormField<String>).last,
        'Another long',
      );
      await calculate(tester);
      final optional = find.text('Optional: known carrier information').first;
      await tester.ensureVisible(optional);
      await tester.tap(optional);
      await tester.pumpAndSettle();
      await choose(
        tester,
        find.byKey(const ValueKey('buck-true-E')),
        'Yes — known carrier',
      );
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      await choose(
        tester,
        find.byKey(const ValueKey('buck-true-ej')),
        'Yes — known carrier',
      );
      expect(find.text('Prediction unavailable'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      await choose(
        tester,
        find.byKey(const ValueKey('buck-true-ej')),
        'Unknown',
      );
      await calculate(tester);
      await choose(
        tester,
        find.byType(DropdownButtonFormField<String>).first,
        'blue • blue',
      );
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      expect(tester.takeException(), isNull);
      expect(requests, isEmpty);
    },
  );

  testWidgets(
    'Actual session changes hide screen and discard prior selections',
    (tester) async {
      await tester.pumpWidget(preview(samples));
      await tester.pumpAndSettle();
      await choose(
        tester,
        find.byType(DropdownButtonFormField<String>).first,
        'A very long',
      );
      await choose(
        tester,
        find.byType(DropdownButtonFormField<String>).last,
        'Another long',
      );
      await calculate(tester);
      FamilyService.selectedOwner.value = 'allowed-profile-owner';
      await identity('other@example.com');
      await tester.pumpAndSettle();
      expect(
        find.text('This preview is not available for this account.'),
        findsOneWidget,
      );
      expect(find.byType(GeneticsPreviewForm), findsNothing);
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      await identity('zaynetort2@gmail.com');
      await tester.pumpAndSettle();
      expect(find.byType(GeneticsPreviewForm), findsOneWidget);
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('This preview is not available for this account.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Actual Actions navigation returns and reacts to account change',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: screenTheme,
          home: const AnimalListScreen(
            ringId: 'sample-ring',
            ringName: 'Sample Ring',
          ),
        ),
      );
      // PostgREST decoding uses an isolate; let mocked read responses finish on
      // the real event loop before settling the loading animation.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Genetics'));
      await tester.pumpAndSettle();
      expect(find.byType(GeneticsScreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(AnimalListScreen), findsOneWidget);
      await identity('other@example.com');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Actions'));
      await tester.pumpAndSettle();
      expect(find.text('Genetics'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(
        requests.where((r) => r.contains('/rest/') && !r.startsWith('GET ')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'Keyboard chooses a parent and Escape cancels without changing it',
    (tester) async {
      await tester.pumpWidget(preview(samples));
      await tester.pumpAndSettle();
      final field = find.byType(DropdownButtonFormField<String>).first;
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final selected = tester
          .widget<DropdownButtonFormField<String>>(field)
          .initialValue;
      expect(selected, isNotNull);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropdownButtonFormField<String>>(field).initialValue,
        selected,
      );
      expect(tester.takeException(), isNull);
      expect(requests, isEmpty);
    },
  );

  testWidgets('Long selector lists can reach the final rabbit on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final herd = [
      for (var i = 0; i < 80; i++)
        rabbit('Buck ${i.toString().padLeft(3, '0')}', 'M'),
      rabbit('Doe', 'F'),
    ];
    await tester.pumpWidget(preview(herd));
    await tester.pumpAndSettle();
    final field = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    final last = find.text('Buck 079 • Buck 079');
    await tester.scrollUntilVisible(
      last,
      400,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 80,
    );
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DropdownButtonFormField<String>>(field).initialValue,
      'Buck 079',
    );
    expect(tester.takeException(), isNull);
    expect(requests, isEmpty);
  });

  testWidgets('Result bars expose spoken percentages alongside color labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(preview(samples));
    await tester.pumpAndSettle();
    await choose(
      tester,
      find.byType(DropdownButtonFormField<String>).first,
      'A very long',
    );
    await choose(
      tester,
      find.byType(DropdownButtonFormField<String>).last,
      'Another long',
    );
    await calculate(tester);
    final scales = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label?.startsWith('Chance scale:') ?? false),
    );
    expect(scales, findsWidgets);
    final scale = scales.first;
    await tester.ensureVisible(scale);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(scale).label, contains('percent out of 100'));
    expect(find.text('Otter / tan pattern (black base)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
