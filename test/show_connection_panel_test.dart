import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/widgets/show_connection_panel.dart';

void main() {
  testWidgets('Connect then explicitly select a herd before sharing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? connection;
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShowConnectionPanel(
            gateway: (action, ids) async {
              calls.add(action);
              if (action == 'connect') {
                connection = {'enabled': false, 'herd_ids': <String>[]};
              }
              if (action == 'save') {
                expect(ids, ['herd']);
                connection = {'enabled': true, 'herd_ids': ids};
                return {'count': 2};
              }
              if (action == 'disconnect') {
                connection = {'enabled': false, 'herd_ids': <String>[]};
                return {'count': 0};
              }
              return {
                'connection': connection,
                'herds': [
                  {'id': 'herd', 'name': 'Hunter'},
                ],
              };
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, ['status']);
    await tester.tap(find.text('Connect RingMaster Show'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('Hunter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save herd selection'));
    await tester.pumpAndSettle();
    expect(find.text('Refreshed 2 animals in Show.'), findsOneWidget);
    await tester.tap(find.text('Stop sharing'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
  });
}
