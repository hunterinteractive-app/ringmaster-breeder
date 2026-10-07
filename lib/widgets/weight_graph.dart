import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

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

    for (int i = 0; i < weights.length; i++) {
      final w = weights[i];
      spots.add(
        FlSpot(
          i.toDouble(),
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
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: true),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 3,
              color: Colors.green,
              dotData: FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }
}