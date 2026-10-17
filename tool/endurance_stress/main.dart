// Explicit local release-browser harness. Never imported by the production app.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_breeder/screens/animal_list_screen.dart';
import 'package:ringmaster_breeder/screens/herd_calendar_screen.dart';
import 'package:ringmaster_breeder/services/animal_service.dart';
import 'package:ringmaster_breeder/services/herd_calendar_service.dart';
import 'package:ringmaster_breeder/services/record_write_attempt.dart';
import 'package:ringmaster_breeder/services/sales_service.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/bulk_records_dialog.dart';
import 'package:ringmaster_breeder/widgets/weight_graph.dart';

const ring = 'e1000000-0000-4000-8000-000000000010';
final nav = GlobalKey<NavigatorState>();
final errors = <String>[];
@JS('performance.memory.usedJSHeapSize')
external JSNumber? get browserHeapBytes;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!['127.0.0.1', 'localhost'].contains(html.window.location.hostname)) {
    throw StateError('This harness requires loopback hosting.');
  }
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  final fixture = jsonDecode(await html.HttpRequest.getString('/fixture.json'));
  await Supabase.initialize(
    url: 'http://127.0.0.1:56440/backend',
    anonKey: fixture['key'],
  );
  await Supabase.instance.client.auth.signInWithPassword(
    email: fixture['email'],
    password: fixture['password'],
  );
  runApp(
    MaterialApp(navigatorKey: nav, theme: AppTheme.light, home: const Soak()),
  );
}

class Soak extends StatefulWidget {
  const Soak({super.key});
  @override
  State<Soak> createState() => _SoakState();
}

class _SoakState extends State<Soak> {
  final bodyKey = GlobalKey();
  final clock = Stopwatch();
  List<Map<String, dynamic>> animals = [];
  final counters = <String, int>{};
  final samples = <Map<String, dynamic>>[];
  final operations = <int>[];
  final frameMs = <int>[];
  String phase = 'Preparing', view = 'animals';
  int tick = 0, cycle = 0, maxCards = 0;
  bool running = false, complete = false;
  List<Map<String, dynamic>> weights = [];
  Map<String, dynamic>? lastSave;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        frameMs.add(t.totalSpan.inMilliseconds);
      }
      if (frameMs.length > 10000) {
        frameMs.removeRange(0, frameMs.length - 10000);
      }
    });
  }

  void count(String key) =>
      counters.update(key, (n) => n + 1, ifAbsent: () => 1);
  Future<void> settle() async {
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 180));
  }

  List<Element> elements() {
    final found = <Element>[];
    void visit(Element e) {
      found.add(e);
      e.visitChildren(visit);
    }

    final root = nav.currentContext;
    if (root is Element) visit(root);
    return found;
  }

  Future<void> icon(String tooltip) async {
    final buttons = elements()
        .map((e) => e.widget)
        .whereType<IconButton>()
        .where((b) => b.tooltip == tooltip && b.onPressed != null);
    if (buttons.isEmpty) throw StateError('Missing $tooltip control');
    buttons.last.onPressed!();
    count(tooltip);
    await settle();
  }

  Future<void> control(String mode) async => html.HttpRequest.request(
    '/control',
    method: 'POST',
    sendData: jsonEncode({'mode': mode}),
  );

  Future<void> reload() async {
    animals = await AnimalService.list(ring);
    if (animals.length != 1000) {
      throw StateError('Animal pagination lost records: ${animals.length}');
    }
    count('complete_herd_loads');
    setState(() {});
  }

  Future<void> saveWithFault(String mode) async {
    setState(() {
      view = 'animals';
      phase = 'Bulk save: $mode';
    });
    await settle();
    final done = showDialog<int>(
      context: nav.currentContext!,
      barrierDismissible: false,
      builder: (_) =>
          BulkRecordsDialog(animals: animals.take(3).toList(), weights: true),
    );
    await settle();
    for (final cb
        in elements().map((e) => e.widget).whereType<CheckboxListTile>()) {
      if ((cb.title as Text?)?.data == 'Select all eligible animals') {
        cb.onChanged!(true);
      }
    }
    await settle();
    for (final f in elements().map((e) => e.widget).whereType<TextField>()) {
      if (f.decoration?.labelText?.endsWith('weight (lb)') == true) {
        f.controller!.text = '4.75';
      }
    }
    await control(mode);
    void save() {
      final button = elements()
          .map((e) => e.widget)
          .whereType<FilledButton>()
          .where(
            (b) =>
                b.child is Text &&
                (b.child as Text).data == 'Save for 3 animals',
          )
          .last;
      button.onPressed!();
    }

    save();
    final deadline = DateTime.now().add(const Duration(seconds: 80));
    if (mode != 'normal' && mode != 'slow') {
      while (!elements().any(
        (e) =>
            e.widget is Text &&
            ((e.widget as Text).data ?? '').startsWith(
              'Unable to confirm the save.',
            ),
      )) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Save fault did not surface in the actual dialog');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      count('visible_save_errors');
      await control('normal');
      save();
    }
    final saved = await done.timeout(const Duration(seconds: 80));
    if (saved != 3) {
      throw StateError('Bulk dialog did not confirm all three records');
    }
    count('bulk_saves');
    count('recovered_$mode');
  }

  Future<void> step() async {
    final step = tick++ % 16;
    final t = Stopwatch()..start();
    try {
      switch (step) {
        case 0:
          setState(() {
            view = 'animals';
            phase = 'Reload 1,000 animals';
          });
          await control(cycle % 3 == 1 ? 'slow' : 'normal');
          await reload();
          await control('normal');
        case 1:
          final search = elements()
              .map((e) => e.widget)
              .whereType<TextField>()
              .firstWhere((f) => f.decoration?.labelText == 'Search animals');
          search.controller!.text = 'SCALE-999';
          search.onChanged!('SCALE-999');
          count('searches');
          await settle();
          if (!elements().any(
            (e) =>
                e.widget is Text &&
                (e.widget as Text).data == '1 of 1000 animals',
          )) {
            throw StateError('Search returned incomplete results');
          }
          await icon('Clear search');
        case 2:
          final scrolls = elements()
              .whereType<StatefulElement>()
              .map((e) => e.state)
              .whereType<ScrollableState>();
          for (final scroll in scrolls) {
            if (scroll.position.hasContentDimensions &&
                scroll.position.maxScrollExtent > 1000) {
              scroll.position.jumpTo(scroll.position.maxScrollExtent * .85);
              count('scrolls');
            }
          }
          await settle();
        case 3:
          elements()
              .map((e) => e.widget)
              .whereType<SegmentedButton<bool>>()
              .single
              .onSelectionChanged!({false});
          count('List view');
          await settle();
        case 4:
          elements()
              .map((e) => e.widget)
              .whereType<SegmentedButton<bool>>()
              .single
              .onSelectionChanged!({true});
          count('Card view');
          await settle();
        case 5:
          setState(() {
            view = 'calendar';
            phase = 'Three-month calendar';
          });
          await settle();
        case 6:
          await icon('Next month');
        case 7:
          await icon('Previous month');
        case 8:
          await control('offline');
          await icon('Next month');
          final errorWait = Stopwatch()..start();
          while (!elements().any(
            (e) =>
                e.widget is Text &&
                (e.widget as Text).data ==
                    'Unable to load calendar. Please try again.',
          )) {
            if (errorWait.elapsed > const Duration(seconds: 10)) {
              throw StateError('Calendar outage did not surface within 10s');
            }
            // The error card follows the month grid in a lazy ListView. Bring
            // that part of the page into view before inspecting its elements.
            for (final scroll
                in elements()
                    .whereType<StatefulElement>()
                    .map((e) => e.state)
                    .whereType<ScrollableState>()) {
              if (scroll.position.hasContentDimensions) {
                scroll.position.jumpTo(scroll.position.maxScrollExtent);
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          counters['calendar_error_max_wait_ms'] = math.max(
            counters['calendar_error_max_wait_ms'] ?? 0,
            errorWait.elapsedMilliseconds,
          );
          count('visible_calendar_errors');
          await control('normal');
          final retry = elements()
              .map((e) => e.widget)
              .whereType<TextButton>()
              .firstWhere(
                (b) => b.child is Text && (b.child as Text).data == 'Retry',
              );
          retry.onPressed!();
          count('calendar_retries');
          await settle();
        case 9:
          final animal = animals[cycle % animals.length];
          weights = await AnimalService.weights(animal['id']);
          final health = await AnimalService.healthRecords(animal['id']);
          if (weights.length < 180 || health.length < 300) {
            throw StateError('Animal history truncated');
          }
          setState(() {
            view = 'weights';
            phase = 'Weight chart and health history';
          });
          count('history_views');
          await settle();
        case 10:
          await saveWithFault('lose-next-write-ack');
        case 11:
          await saveWithFault('offline');
        case 12:
          final id = SalesService.newId();
          final attempt = RecordWriteAttempt('animal_weights', [
            {
              'id': id,
              'animal_id': animals.first['id'],
              'weight': 4.8,
              'recorded_at': DateTime.now().toUtc().toIso8601String(),
            },
          ]);
          await Future.wait([attempt.save(), attempt.save()]);
          final rows = await Supabase.instance.client
              .from('animal_weights')
              .select('id')
              .eq('id', id);
          if (rows.length != 1) {
            throw StateError('Concurrent retry duplicated a weight');
          }
          count('concurrent_retry_checks');
        case 13:
          await saveWithFault('slow');
        case 14:
          final rows = await Supabase.instance.client
              .from('animals')
              .select('id,revision')
              .eq('id', animals.first['id'])
              .single();
          Future<bool> edit(String value) async {
            try {
              await AnimalService.update(rows['id'], {
                'notes': value,
              }, expectedRevision: rows['revision']);
              return true;
            } on AnimalEditConflict {
              return false;
            }
          }
          final outcomes = await Future.wait([
            edit('Synthetic editor A'),
            edit('Synthetic editor B'),
          ]);
          if (outcomes.where((v) => v).length != 1) {
            throw StateError('Concurrent edits lost conflict protection');
          }
          count('edit_conflict_checks');
        case 15:
          cycle++;
          setState(() {
            view = 'animals';
            phase = 'Cycle $cycle complete';
          });
      }
      await settle();
      final mounted = elements()
          .where((e) => e.widget is AnimalRecordCard)
          .length;
      if (mounted > maxCards) maxCards = mounted;
      if (mounted > 64) {
        throw StateError('Animal cards no longer lazy: $mounted');
      }
    } catch (e) {
      errors.add('step $step: $e');
      await control('normal');
      if (nav.currentState!.canPop()) nav.currentState!.pop();
      setState(() => view = 'animals');
    }
    operations.add(t.elapsedMilliseconds);
    if (tick % 4 == 0) await evidence();
    if (mounted) setState(() {});
  }

  Future<void> evidence() async {
    int? heap;
    try {
      heap = browserHeapBytes?.toDartInt;
    } catch (_) {}
    final sample = <String, dynamic>{
      'elapsed_seconds': clock.elapsed.inSeconds,
      'ticks': tick,
      'cycles': cycle,
      'phase': phase,
      'counters': Map.of(counters),
      'errors': List.of(errors),
      'max_mounted_cards': maxCards,
      'mounted_elements': elements().length,
      'js_heap_bytes': heap,
      'complete': complete,
      'operation_ms': operations.toList(),
      'recent_frame_ms': frameMs.toList(),
    };
    final pre =
        html.document.getElementById('stress-status') ??
        (html.PreElement()
          ..id = 'stress-status'
          ..style.cssText =
              'position:fixed;bottom:0;left:0;z-index:9999;max-height:90px;overflow:auto;background:#fff;font-size:11px;pointer-events:none;');
    pre.text = jsonEncode({
      ...sample,
      'operation_ms': operations.length,
      'recent_frame_ms': frameMs.length,
    });
    if (pre.parent == null) html.document.body!.append(pre);
    await html.HttpRequest.request(
      '/evidence',
      method: 'POST',
      sendData: jsonEncode(sample),
    );
  }

  Future<void> start() async {
    if (running) return;
    setState(() => running = true);
    clock.start();
    while (clock.elapsed < const Duration(minutes: 30) && mounted) {
      await step();
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    clock.stop();
    complete = true;
    running = false;
    await control('normal');
    await evidence();
    setState(() => phase = '30-minute run finished: ${errors.length} errors');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        'Local endurance test • ${clock.elapsed.inMinutes}m • cycle $cycle • ${errors.length} errors',
      ),
      actions: [
        TextButton(
          onPressed: running ? null : start,
          child: const Text('Start 30-minute test'),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(padding: const EdgeInsets.all(8), child: Text(phase)),
        Expanded(
          child: SizedBox(
            key: bodyKey,
            child: switch (view) {
              'calendar' => HerdCalendarScreen(
                ringId: ring,
                windowLoader: (w) async {
                  final values = await HerdCalendarService(
                    Supabase.instance.client,
                  ).load(ring, w);
                  if (values.any((v) => !w.includes(v))) {
                    throw StateError('Calendar escaped three-month window');
                  }
                  count('calendar_windows_loaded');
                  return values;
                },
              ),
              'weights' => SingleChildScrollView(
                child: WeightGraph(weights: weights),
              ),
              _ => AnimalBrowser(
                animals: animals,
                onAdd: () {},
                onRefresh: reload,
                onOpen: (_) {},
                ringId: ring,
              ),
            },
          ),
        ),
      ],
    ),
  );
}
