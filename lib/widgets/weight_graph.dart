import '../utils/weight_date.dart';
import 'dart:math' as math;
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

    final low = spots.map((p) => p.y).reduce(math.min);
    final high = spots.map((p) => p.y).reduce(math.max);
    final interval = math.max(0.1, ((high - low) / 4 * 10).ceil() / 10);
    final minY = math.max(0.0, (low / interval).floor() * interval - interval);
    final maxY = (high / interval).ceil() * interval + interval;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 12),
      child: SizedBox(
        height: 260,
        child: LineChart(
          LineChartData(
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (points) => points
                    .map(
                      (point) => LineTooltipItem(
                        '${point.y.toStringAsFixed(2)} lb\n${weightDate(weights[point.spotIndex]['recorded_at'])}',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    )
                    .toList(),
              ),
            ),
            minY: minY,
            maxY: maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: interval,
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 58,
                  interval: interval,
                  getTitlesWidget: (value, meta) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      value.toStringAsFixed(1),
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
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
      ),
    );
  }
}
