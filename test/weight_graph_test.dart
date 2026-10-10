import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ringmaster_breeder/widgets/weight_graph.dart';

void main() {
  testWidgets('Weight graph leaves room for sparse single-line labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: WeightGraph(
              weights: [
                {'weight': 4.1, 'recorded_at': '2026-09-01'},
                {'weight': 4.4, 'recorded_at': '2026-09-08'},
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(
      data.titlesData.leftTitles.sideTitles.reservedSize,
      greaterThanOrEqualTo(50),
    );
    expect(
      (data.maxY - data.minY) / data.titlesData.leftTitles.sideTitles.interval!,
      lessThanOrEqualTo(7),
    );
    expect(data.maxY, greaterThan(4.4));
    expect(tester.takeException(), isNull);
  });
}
