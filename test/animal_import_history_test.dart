import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_breeder/services/animal_history_service.dart';
import 'package:ringmaster_breeder/widgets/animal_import_history.dart';

void main() {
  const tables = {
    'global_pedigree_history': AnimalHistorySource.globalPedigree,
    'rabbit_register_animals': AnimalHistorySource.rabbitRegister,
    'rabbit_register_records': AnimalHistorySource.rabbitRegister,
    'kintraks_animals': AnimalHistorySource.kintraks,
  };
  for (final matchingTable in [null, ...tables.keys]) {
    test(
      'Source availability checks only this animal: $matchingTable',
      () async {
        final visited = <String>{};
        final client = SupabaseClient(
          'https://history-test.invalid',
          'fixture',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            final table = request.url.pathSegments.last;
            visited.add(table);
            expect(request.method, 'GET');
            expect(request.url.queryParameters['limit'], '1');
            if (table == 'global_pedigree_history' ||
                table == 'rabbit_register_records') {
              expect(
                request.url.queryParameters['or'],
                '(animal_id.eq.animal-a,sire_id.eq.animal-a)',
              );
            } else {
              expect(request.url.queryParameters['animal_id'], 'eq.animal-a');
            }
            return http.Response(
              jsonEncode(
                table == matchingTable
                    ? [
                        {'animal_id': null, 'sire_id': 'animal-a'},
                      ]
                    : [],
              ),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        expect(
          await AnimalHistoryService.sources('animal-a', client: client),
          matchingTable == null
              ? <AnimalHistorySource>{}
              : {tables[matchingTable]!},
        );
        expect(visited, tables.keys.toSet());
      },
    );
  }

  testWidgets('Only linked source histories appear; changing animals reloads', (
    tester,
  ) async {
    Future<Set<AnimalHistorySource>> load(String id) async => switch (id) {
      'a' => {AnimalHistorySource.rabbitRegister},
      'b' => {AnimalHistorySource.kintraks, AnimalHistorySource.globalPedigree},
      _ => {},
    };
    Future<void> open(String id) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimalImportHistory(animalId: id, loader: load),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await open('a');
    expect(find.text('Rabbit Register history'), findsOneWidget);
    expect(find.text('Global Pedigree history'), findsNothing);
    expect(find.text('Kintraks history'), findsNothing);
    await open('b');
    expect(find.text('Rabbit Register history'), findsNothing);
    expect(find.text('Global Pedigree history'), findsOneWidget);
    expect(find.text('Kintraks history'), findsOneWidget);
    await open('empty');
    expect(find.byType(ElevatedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Failed checks offer a retry rather than claiming no history', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimalImportHistory(
            animalId: 'a',
            loader: (_) async {
              if (calls++ == 0) throw Exception('Unavailable');
              return {AnimalHistorySource.rabbitRegister};
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rabbit Register history'), findsNothing);
    await tester.tap(find.text('Unable to check import history. Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Rabbit Register history'), findsOneWidget);
    expect(calls, 2);
  });
}
