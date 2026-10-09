import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class WeightGraph extends StatelessWidget {
  final List weights;

  const WeightGraph({super.key, required this.weights});

  @override
  Widget build(BuildContext context) {
    if (weights.length < 2) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Add more weights to see growth trends.',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    }

    final spots = <FlSpot>[];

    final first = DateTime.parse(
      weights.first['recorded_at'],
    ).millisecondsSinceEpoch;
    for (int i = 0; i < weights.length; i++) {
      final w = weights[i];
      spots.add(
        FlSpot(
          (DateTime.parse(w['recorded_at']).millisecondsSinceEpoch - first) /
              Duration.millisecondsPerDay,
          (w['weight'] as num).toDouble(),
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: true),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 3,
              color: BreederColors.primary,
              dotData: FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }
}
