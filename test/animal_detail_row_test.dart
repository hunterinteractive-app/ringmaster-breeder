import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/animal_detail_screen.dart';

void main() {
  testWidgets('Animal details display numeric legs and missing values', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AnimalDetailRow(title: 'Legs', value: 13),
              AnimalDetailRow(title: 'Registration #', value: 'F803P'),
              AnimalDetailRow(title: 'GC #'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('13'), findsOneWidget);
    expect(find.text('F803P'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
