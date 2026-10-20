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
import 'package:ringmaster_breeder/screens/what_if_screen.dart';
import 'package:ringmaster_breeder/services/what_if_catalog.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/genetics_prediction_results.dart';

class MemoryAuth extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

Future<void> identity(String email) async {
  final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String encode(Object v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  // Synthetic identity; the test HTTP client never contacts a server.
  // ignore: invalid_use_of_internal_member
  await Supabase.instance.client.auth.setInitialSession(
    jsonEncode({
      'access_token':
          '${encode({})}.${encode({'sub': 'fixture', 'exp': exp})}.fixture',
      'refresh_token': 'fixture',
      'token_type': 'bearer',
      'user': {
        'id': 'fixture',
        'email': email,
        'app_metadata': {},
        'user_metadata': {'email': 'zaynetort2@gmail.com'},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

const catalog = WhatIfCatalog(
  breeds: ['Dutch', 'Havana', 'Rex', 'Tan'],
  varieties: ['Black', 'Chocolate', 'Lilac', 'Unbuilt variety'],
);
Future<void> open(
  WidgetTester t, {
  double width = 1000,
  double scale = 1,
  bool failCatalog = false,
}) async {
  t.view.physicalSize = Size(width, 1100);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light.copyWith(
          textTheme: AppTheme.light.textTheme.apply(fontFamily: 'BreederSans'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: WhatIfScreen(
          catalogLoader: () async {
            if (failCatalog) throw StateError('offline');
            return catalog;
          },
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> type(WidgetTester t, String key, String value) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.enterText(f, value);
  await t.pumpAndSettle();
}

Future<void> click(WidgetTester t, String label) async {
  final f = find.text(label).last;
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> pairing(WidgetTester t) async {
  for (var i = 0; i < 2; i++) {
    await type(t, 'breed-$i', i == 0 ? 'Havana' : 'Rex');
    await type(t, 'variety-$i', 'Black');
  }
}

Future<void> genes(WidgetTester t, int i, String notation) async {
  final button = find.text('Hypothetical genotype').at(i);
  await t.ensureVisible(button);
  await t.pumpAndSettle();
  await t.tap(button);
  await t.pumpAndSettle();
  await click(t, 'Advanced: type or paste genotype');
  await type(t, 'genotype-notation', notation);
  await click(t, 'Use in What If');
}

Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('WHAT_IF_CAPTURES')) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/private/tmp/what-if-$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  final requests = <String>[];
  setUpAll(() async {
    await (FontLoader(
      'BreederSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await Supabase.initialize(
      url: 'https://what-if.invalid',
      anonKey: 'fixture',
      httpClient: MockClient((r) async {
        requests.add(r.method);
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: MemoryAuth(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() async {
    await identity('zaynetort2@gmail.com');
    requests.clear();
  });

  testWidgets(
    'Both searchable variety pickers use the full list, independent of breed',
    (t) async {
      await open(t);
      await type(t, 'breed-0', 'Tan');
      await type(t, 'breed-1', 'Dutch');
      for (final role in ['buck', 'doe']) {
        final browse = find.byTooltip('Browse all varieties $role');
        await t.ensureVisible(browse);
        await t.pumpAndSettle();
        await t.tap(browse);
        await t.pumpAndSettle();
        expect(find.text('All rabbit varieties'), findsOneWidget);
        expect(find.text('Unbuilt variety'), findsOneWidget);
        expect(find.text('Lilac'), findsOneWidget);
        await t.enterText(find.widgetWithText(TextField, 'Search'), 'choc');
        await t.pumpAndSettle();
        expect(find.text('Lilac'), findsNothing);
        await click(t, 'Chocolate');
      }
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('variety-0')))
            .controller!
            .text,
        'Chocolate',
      );
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('variety-1')))
            .controller!
            .text,
        'Chocolate',
      );
      expect(requests, isEmpty);
    },
  );

  testWidgets(
    'Temporary genotypes calculate exact colors, swap with parents, and clear on edits',
    (t) async {
      await open(t);
      await pairing(t);
      await type(t, 'variety-1', 'Lilac');
      await genes(t, 0, 'aa Bb CC Dd EE enen VV');
      await genes(t, 1, 'aa bb CC dd EE enen VV');
      await click(t, 'See possible colors');
      final result = t
          .widget<GeneticsPredictionResults>(
            find.byType(GeneticsPredictionResults),
          )
          .prediction;
      expect(result.colors.length, 4);
      expect(result.colors.every((c) => c.isExact && c.minimum == .25), isTrue);
      await capture(t, 'results');
      await click(t, 'Swap parents');
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('breed-0')))
            .controller!
            .text,
        'Rex',
      );
      await click(t, 'See possible colors');
      expect(
        t
            .widget<GeneticsPredictionResults>(
              find.byType(GeneticsPredictionResults),
            )
            .prediction
            .colors
            .map((c) => c.minimum),
        everyElement(.25),
      );
      await type(t, 'variety-0', 'Blue');
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      expect(find.text('aa bb CC dd EE enen VV'), findsNothing);
      await click(t, 'Start over');
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('breed-0')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        find.text('Genotype: color-based estimate; other genes Unknown'),
        findsNWidgets(2),
      );
      expect(requests, isEmpty);
    },
  );

  for (final config in [(320.0, 1.0), (320.0, 2.0), (1440.0, 1.0)]) {
    testWidgets('Responsive workflow ${config.$1} at scale ${config.$2}', (
      t,
    ) async {
      await open(t, width: config.$1, scale: config.$2);
      expect(find.text(GeneticsPreview.disclaimer), findsOneWidget);
      await capture(t, '${config.$1}-${config.$2}');
      await pairing(t);
      await click(t, 'See possible colors');
      expect(find.byType(GeneticsPredictionResults), findsOneWidget);
      expect(t.takeException(), isNull);
      await type(t, 'variety-1', 'Unbuilt variety');
      await click(t, 'See possible colors');
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      expect(find.textContaining('support@ringmasterone.com'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('Catalog failure still permits temporary typed parents', (
    t,
  ) async {
    await open(t, failCatalog: true);
    expect(find.text('Retry catalog'), findsOneWidget);
    await pairing(t);
    await click(t, 'See possible colors');
    expect(find.byType(GeneticsPredictionResults), findsOneWidget);
  });

  testWidgets(
    'Actual signed-in identity gates screen and revokes an open editor',
    (t) async {
      await identity('other@example.com');
      await open(t);
      expect(find.byType(WhatIfForm), findsNothing);
      await identity('zaynetort2@gmail.com');
      await t.pumpAndSettle();
      await pairing(t);
      final button = find.text('Hypothetical genotype').first;
      await t.ensureVisible(button);
      await t.pumpAndSettle();
      await t.tap(button);
      await t.pumpAndSettle();
      expect(find.text('Use in What If'), findsOneWidget);
      await identity('other@example.com');
      await t.pumpAndSettle();
      expect(find.byType(WhatIfForm), findsNothing);
      expect(find.text('Use in What If'), findsNothing);
      await identity('zaynetort2@gmail.com');
      await t.pumpAndSettle();
      expect(find.text('Use in What If'), findsNothing);
      await click(t, 'Close');
      await identity('zaynetort2@gmail.com');
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('breed-0')))
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  for (final allowed in [false, true]) {
    testWidgets('Actions What Ifs visibility $allowed', (t) async {
      var opened = false;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimalBrowser(
              animals: const [],
              onAdd: () {},
              onRefresh: () {},
              onOpen: (_) {},
              onWhatIfs: allowed ? () => opened = true : null,
            ),
          ),
        ),
      );
      await t.tap(find.byTooltip('Actions'));
      await t.pumpAndSettle();
      expect(find.text('What Ifs'), allowed ? findsOneWidget : findsNothing);
      if (allowed) {
        await t.tap(find.text('What Ifs'));
        await t.pumpAndSettle();
        expect(opened, isTrue);
      }
    });
  }
}
