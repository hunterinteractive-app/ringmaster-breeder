import 'dart:async';
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
import 'package:ringmaster_breeder/genetics/animal_genotype.dart';
import 'package:ringmaster_breeder/screens/animal_detail_screen.dart';
import 'package:ringmaster_breeder/services/animal_service.dart';
import 'package:ringmaster_breeder/widgets/animal_genotype_section.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';

const captureKey = ValueKey('genotype-capture');
ThemeData get genotypeTestTheme => AppTheme.light.copyWith(
  textTheme: AppTheme.light.textTheme.apply(fontFamily: 'BreederSans'),
);
Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('GENOTYPE_CAPTURES')) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(
      name.endsWith('-section')
          ? const ValueKey('genotype-section')
          : captureKey,
    ),
  );
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final data = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('docs/genetics/screen-captures/genotype-$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    picture.dispose();
  });
}

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
  // Test-only in-memory identity; no real auth host or credential.
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

Map<String, dynamic> animal() => {
  'id': 'a',
  'name': 'Sample rabbit',
  'tattoo': 'A',
  'species': 'rabbit',
  'breed': 'Dutch',
  'variety': 'Chocolate',
  'sex': 'Buck',
  'status': 'active',
  'genotype': <String, dynamic>{},
  'revision': 7,
};

Future<void> openEditor(
  WidgetTester tester,
  Future<void> Function(Map<String, dynamic>) writer, {
  AnimalGenotype? initial,
  bool ready = true,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        theme: genotypeTestTheme,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => AnimalGenotypeDialog(
                  initial: initial,
                  colorInference: 'aa bb C- D- V-',
                  onSave: writer,
                  storageReady: ready,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> typeGenotype(WidgetTester tester, String text) async {
  final field = find.byKey(const ValueKey('genotype-notation'));
  if (field.evaluate().isEmpty) {
    final advanced = find.text('Advanced: type or paste genotype');
    await tester.ensureVisible(advanced);
    await tester.pumpAndSettle();
    await tester.tap(advanced);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

Future<void> typeSource(WidgetTester tester, String text) async {
  final field = find.byKey(const ValueKey('genotype-source'));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
}

Future<void> chooseAllele(
  WidgetTester tester,
  String locus,
  int copy,
  String current,
  String value,
) async {
  final field = find.byKey(ValueKey('allele-$locus-$copy-$current'));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(
    (value == 'Unknown'
            ? find.text('Unknown')
            : find.byWidgetPredicate(
                (w) => w is Text && (w.data?.startsWith('$value ·') ?? false),
              ))
        .last,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'BreederSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await Supabase.initialize(
      url: 'https://animal-genotype.invalid',
      anonKey: 'fixture',
      httpClient: MockClient(
        (r) async => http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: MemoryAuth(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() async => identity('zaynetort2@gmail.com'));

  testWidgets(
    'Guided choices default to unknown, update the preview and save only chosen copies',
    (tester) async {
      Map<String, dynamic>? saved;
      await openEditor(tester, (v) async => saved = v);
      expect(find.byKey(const ValueKey('genotype-notation')), findsNothing);
      expect(find.text('No genes recorded — all unknown'), findsOneWidget);
      await chooseAllele(tester, 'A', 0, 'unknown', 'a');
      await chooseAllele(tester, 'A', 1, 'unknown', 'a');
      await chooseAllele(tester, 'B', 0, 'unknown', 'b');
      final preview = tester.widget<SelectableText>(
        find.byKey(const ValueKey('genotype-preview')),
      );
      expect(preview.data, 'aa b-');
      await tester.tap(find.text('Save genotype'));
      await tester.pumpAndSettle();
      expect(saved, {'notation': 'aa b-', 'basis': 'breeder_entered'});
    },
  );

  testWidgets(
    'Unknown choices remove known copies without filling other genes',
    (tester) async {
      Map<String, dynamic>? saved;
      await openEditor(
        tester,
        (v) async => saved = v,
        initial: const AnimalGenotype(notation: 'aa bb C_', basis: 'imported'),
      );
      await chooseAllele(tester, 'A', 1, 'a', 'Unknown');
      await chooseAllele(tester, 'A', 0, 'a', 'Unknown');
      await tester.tap(find.text('Save genotype'));
      await tester.pumpAndSettle();
      expect(saved!['notation'], 'bb C_');
      expect(saved!['basis'], 'breeder_entered');
    },
  );

  testWidgets(
    'Unsupported imported notation stays intact in Advanced and supported typing syncs choices',
    (tester) async {
      Map<String, dynamic>? saved;
      const original = 'aabbC-D-E-enenSa-L-wewe';
      await openEditor(
        tester,
        (v) async => saved = v,
        initial: const AnimalGenotype(
          notation: original,
          basis: 'imported',
          source: 'Rabbit Register',
        ),
      );
      expect(
        find.textContaining('nothing will be removed automatically'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('allele-A-0-a')), findsNothing);
      await tester.tap(find.text('Save genotype'));
      await tester.pumpAndSettle();
      expect(saved!['notation'], original);
      expect(saved!['basis'], 'imported');
      await openEditor(
        tester,
        (v) async => saved = v,
        initial: AnimalGenotype.read(saved),
      );
      await typeGenotype(tester, 'aa bb C_ dd E_');
      expect(find.byKey(const ValueKey('allele-D-0-d')), findsOneWidget);
      await chooseAllele(tester, 'D', 0, 'd', 'D');
      await tester.tap(find.text('Save genotype'));
      await tester.pumpAndSettle();
      expect(saved!['notation'], 'aa bb C_ Dd E_');
      expect(saved!['basis'], 'breeder_entered');
      expect(saved!['source'], 'Rabbit Register');
    },
  );

  testWidgets(
    'Clear genotype resets guided choices, Advanced text and source together',
    (tester) async {
      Map<String, dynamic>? saved;
      await openEditor(
        tester,
        (v) async => saved = v,
        initial: const AnimalGenotype(notation: 'bb dd', source: 'Source'),
      );
      final clear = find.text('Clear genotype');
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('allele-B-0-unknown')), findsOneWidget);
      expect(find.text('No genes recorded — all unknown'), findsOneWidget);
      await tester.tap(find.text('Save genotype'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
    },
  );

  testWidgets(
    'Save retains original notation and source; cancel never writes',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      await openEditor(tester, (v) async => writes.add(v));
      await typeGenotype(tester, 'aabbC-D-E-enenSa-L-wewe');
      await typeSource(tester, 'Rabbit Register');
      await tester.tap(find.text('Save genotype'));
      await tester.pumpAndSettle();
      expect(writes.single, {
        'notation': 'aabbC-D-E-enenSa-L-wewe',
        'basis': 'breeder_entered',
        'source': 'Rabbit Register',
      });
      await openEditor(tester, (v) async => writes.add(v));
      await typeGenotype(tester, 'aa bb');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
    },
  );

  testWidgets(
    'Using a color estimate labels it inferred and clearing removes the entry',
    (tester) async {
      Map<String, dynamic>? saved;
      await openEditor(tester, (v) async => saved = v);
      await tester.ensureVisible(find.text('Use color-based estimate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use color-based estimate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save genotype'));
      await tester.pumpAndSettle();
      expect(saved!['basis'], 'inferred');
      expect(saved!['notation'], 'aa bb C- D- V-');
      await openEditor(
        tester,
        (v) async => saved = v,
        initial: AnimalGenotype.read(saved),
      );
      await typeGenotype(tester, '');
      await typeSource(tester, '');
      await tester.tap(find.text('Save genotype'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
    },
  );

  testWidgets(
    'Failure keeps text; conflict prevents overwriting; missing storage prevents queueing',
    (tester) async {
      var attempts = 0;
      await openEditor(tester, (_) async {
        attempts++;
        throw StateError('offline');
      });
      await typeGenotype(tester, 'aa bb C-');
      await tester.tap(find.text('Save genotype'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your entry is still here'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('genotype-notation')))
            .controller!
            .text,
        'aa bb C-',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await openEditor(tester, (_) async {
        attempts++;
        throw AnimalEditConflict();
      });
      await tester.tap(find.text('Save genotype'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This animal changed'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save genotype'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await openEditor(tester, (_) async {
        attempts++;
      }, ready: false);
      expect(find.textContaining('saving is not available'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save genotype'),
            )
            .onPressed,
        isNull,
      );
      expect(attempts, 2);
    },
  );

  testWidgets('Repeated Save cannot submit twice while saving', (tester) async {
    var attempts = 0;
    final done = Completer<void>();
    await openEditor(tester, (_) {
      attempts++;
      return done.future;
    });
    await typeGenotype(tester, 'aa bb');
    await tester.tap(find.text('Save genotype'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(attempts, 1);
    done.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Actual details show a private section, save only genotype with revision, revoke on auth change',
    (tester) async {
      // Simulate a previously downloaded row from before the new column.
      var record = animal()..remove('genotype');
      final writes = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AnimalDetailScreen(
            animalId: 'a',
            loader: (_) async => {...record},
            weightLoader: (_) async => null,
            genotypeWriter: (id, changes, revision) async {
              expect(id, 'a');
              expect(revision, 7);
              writes.add(changes);
              record = {...record, ...changes, 'revision': 8};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final change = find.byTooltip('Change genotype');
      await tester.ensureVisible(change);
      await tester.pumpAndSettle();
      await tester.tap(change);
      await tester.pumpAndSettle();
      await typeGenotype(tester, 'aa bb C- Dd');
      await tester.tap(find.text('Save genotype'));
      await tester.pumpAndSettle();
      expect(writes.single.keys, ['genotype']);
      expect(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == 'aa bb C- Dd',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(change);
      await tester.pumpAndSettle();
      await tester.tap(change);
      await tester.pumpAndSettle();
      await identity('other@example.com');
      await tester.pumpAndSettle();
      expect(find.byType(AnimalGenotypeSection), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('This preview is not available for this account.'),
        findsOneWidget,
      );
      expect(writes, hasLength(1));
    },
  );

  testWidgets('Genotype row keeps notes in hover and tap help', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimalGenotypeSection(animal: animal(), onChange: () {}),
        ),
      ),
    );
    expect(find.byType(Card), findsNothing);
    expect(find.text('Genotype:'), findsOneWidget);
    expect(find.byTooltip('Change genotype'), findsOneWidget);
    expect(find.textContaining('Inferred from recorded color'), findsNothing);
    final help = find.byIcon(Icons.info_outline);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(help));
    await tester.pumpAndSettle();
    expect(find.textContaining('Inferred from recorded color'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Inferred from recorded color'), findsNothing);
    await mouse.removePointer();
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Compatible saved genes help narrow offspring predictions',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final status in ['sold', 'deceased']) {
    testWidgets(
      'Locked $status animal shows genotype without a change action',
      (tester) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              theme: genotypeTestTheme,
              debugShowCheckedModeBanner: false,
              home: AnimalDetailScreen(
                animalId: 'a',
                loader: (_) async => {...animal(), 'status': status},
                weightLoader: (_) async => null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AnimalGenotypeSection), findsOneWidget);
        expect(find.byTooltip('Change genotype'), findsNothing);
      },
    );
  }

  for (final (size, scale) in [
    (const Size(320, 568), 2.0),
    (const Size(1440, 900), 1.0),
  ]) {
    testWidgets('Genotype reference wraps and editor scrolls at $size/$scale', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            theme: genotypeTestTheme,
            debugShowCheckedModeBanner: false,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: RepaintBoundary(
                  key: const ValueKey('genotype-section'),
                  child: AnimalGenotypeSection(
                    animal: {
                      ...animal(),
                      'genotype': const AnimalGenotype(
                        notation: 'aa bb C- D- E- enen Sa- L- wewe',
                        source: 'Rabbit Register inferred from pedigree',
                      ).toJson(),
                    },
                    onChange: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SelectableText>(find.byType(SelectableText).first)
            .textAlign,
        TextAlign.right,
      );
      await capture(tester, '${size.width.toInt()}-section');
      await tester.ensureVisible(find.byTooltip('Change genotype'));
      expect(tester.takeException(), isNull);
      await openEditor(tester, (_) async {}, textScale: scale);
      await capture(tester, '${size.width.toInt()}-editor');
      await chooseAllele(tester, 'C', 0, 'unknown', 'cchd');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(TextField).last);
      expect(tester.takeException(), isNull);
    });
  }
}
