import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/genetics_preview.dart';
import '../genetics/color_prediction.dart';
import '../theme/app_theme.dart';

class GeneticsPredictionResults extends StatefulWidget {
  final ColorPrediction prediction;
  const GeneticsPredictionResults({super.key, required this.prediction});

  @override
  State<GeneticsPredictionResults> createState() =>
      _GeneticsPredictionResultsState();
}

class _GeneticsPredictionResultsState extends State<GeneticsPredictionResults> {
  static const _pageSize = 48;
  int _page = 0;
  ColorPrediction get prediction => widget.prediction;
  bool get _paged => prediction.colors.length > 96;
  int get _start => _paged ? _page * _pageSize : 0;
  int get _end => _paged
      ? (_start + _pageSize).clamp(0, prediction.colors.length)
      : prediction.colors.length;

  @override
  void didUpdateWidget(covariant GeneticsPredictionResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.prediction, prediction)) _page = 0;
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 4, right: 10),
                child: Icon(
                  Icons.palette_outlined,
                  color: BreederColors.primary,
                ),
              ),
              Expanded(
                child: Text(
                  prediction.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          if (prediction.limitation != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BreederColors.primary.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prediction.limitationTitle ?? 'Prediction limits',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(prediction.limitation!),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            prediction.hasRanges
                ? 'Hidden carrier genes are unknown. Ranges show how a color’s chance changes across possible parent genes; they are not fixed odds and should not be added together.'
                : 'These modeled chances use the selected colors and carrier information, under the assumptions above.',
          ),
          if (prediction.colors.any((c) => c.isColorFamily)) ...[
            const SizedBox(height: 8),
            const Text(
              'A color family groups related appearances. Its percentage does not promise an exact shade or set of markings.',
            ),
          ],
          if (prediction.parentInterpretations.isNotEmpty ||
              prediction.unresolvedInformation.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('What affects these estimates?'),
              children: [
                for (final note in prediction.parentInterpretations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(note),
                    ),
                  ),
                for (final note in prediction.unresolvedInformation)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(note),
                    ),
                  ),
                if (prediction.unresolvedInformation.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Verified carrier information can narrow some ranges. Keep Unknown when you do not know; a possible outcome does not mean a hidden gene is known to be present.',
                    ),
                  ),
              ],
            ),
          if (prediction.markings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Spotting inheritance',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'These describe inherited spotting states. White genes can hide the visible markings. Spot placement and show quality are not predicted.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final marking in prediction.markings)
                  _MarkingEstimateCard(chance: marking),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Color and marking combinations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              const _RangeKey(striped: false, label: 'Lowest modeled chance'),
              if (prediction.hasRanges)
                const _RangeKey(
                  striped: true,
                  label: 'Possible increase with hidden genes',
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_paged) ...[
            Text(
              'Showing colors ${_start + 1}–$_end of ${prediction.colors.length}. Use the color page buttons to view all possibilities.',
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 520
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final chance in prediction.colors.sublist(_start, _end))
                    SizedBox(
                      width: width,
                      child: _ColorEstimateCard(chance: chance),
                    ),
                ],
              );
            },
          ),
          if (_paged) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _page > 0 ? () => setState(() => _page--) : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Previous colors'),
                ),
                OutlinedButton.icon(
                  onPressed: _end < prediction.colors.length
                      ? () => setState(() => _page++)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next colors'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Color swatches are approximate. Actual coats and markings vary.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text(prediction.scope),
          const SizedBox(height: 12),
          const Text(
            'Each chance applies to an individual kit under this model. It does not promise a litter’s colors or counts. Other genes may change the actual appearance, including when a base-color estimate is 100%.',
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: BreederColors.primary.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: BreederColors.primary,
                  ),
                  SizedBox(width: 10),
                  Expanded(child: Text(GeneticsPreview.disclaimer)),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MarkingEstimateCard extends StatelessWidget {
  final MarkingChanceRange chance;
  const _MarkingEstimateCard({required this.chance});

  @override
  Widget build(BuildContext context) {
    String percent(double p) => NumberFormat('0.##').format(p * 100);
    final exact = (chance.maximum - chance.minimum).abs() < 1e-10;
    final label = exact
        ? '${percent(chance.maximum)}%'
        : '${percent(chance.minimum)}–${percent(chance.maximum)}%';
    return Container(
      constraints: const BoxConstraints(minWidth: 170),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        border: Border.all(color: const Color(0xFFDEE2E8)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(chance.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            exact ? 'Modeled inheritance per kit' : 'Unknown parent spotting',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

Color _coat(BaseCoatColor color) => switch (color) {
  BaseCoatColor.black => const Color(0xFF29272D),
  BaseCoatColor.blue => const Color(0xFF65758B),
  BaseCoatColor.chocolate => const Color(0xFF704B39),
  BaseCoatColor.lilac => const Color(0xFFAB96A3),
};

class _ColorEstimateCard extends StatelessWidget {
  final ColorChanceRange chance;
  const _ColorEstimateCard({required this.chance});

  @override
  Widget build(BuildContext context) {
    String percent(double p) => NumberFormat('0.##').format(p * 100);
    final label = chance.isExact
        ? '${percent(chance.maximum)}%'
        : '${percent(chance.minimum)}–${percent(chance.maximum)}%';
    final baseSwatch = switch (chance.swatch) {
      'white' => const Color(0xFFF9F6F0),
      'orange' => const Color(0xFFCA833E),
      'cream' => const Color(0xFFE4C898),
      _ => _coat(chance.color),
    };
    final swatchColors = chance.broken
        ? [Colors.white, baseSwatch]
        : chance.tortoise
        ? [const Color(0xFFD6A366), baseSwatch]
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        border: Border.all(color: const Color(0xFFDEE2E8)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: swatchColors == null ? baseSwatch : null,
                    gradient: swatchColors == null
                        ? null
                        : LinearGradient(colors: swatchColors),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: const SizedBox(width: 28, height: 28),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    chance.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: BreederColors.text,
              ),
            ),
            if (chance.isColorFamily) ...[
              const SizedBox(height: 8),
              Text(
                'Color family • exact appearance varies',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              chance.isExact
                  ? 'Modeled chance per kit'
                  : 'Range across possible parent genes',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Semantics(
              label:
                  'Chance scale: ${percent(chance.minimum)} to ${percent(chance.maximum)} percent out of 100',
              child: SizedBox(
                height: 14,
                child: CustomPaint(
                  painter: _ChanceRangePainter(chance.minimum, chance.maximum),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0%', style: Theme.of(context).textTheme.bodySmall),
                Text('100%', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeKey extends StatelessWidget {
  final bool striped;
  final String label;
  const _RangeKey({required this.striped, required this.label});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 22,
        height: 12,
        child: CustomPaint(painter: _ChanceRangePainter(striped ? 0 : 1, 1)),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}

/// Solid fill encodes the minimum; hatching spans minimum to maximum.
/// No midpoint, average probability, or simulated litter is invented.
class _ChanceRangePainter extends CustomPainter {
  final double minimum, maximum;
  const _ChanceRangePainter(this.minimum, this.maximum);
  @override
  void paint(Canvas canvas, Size size) {
    final track = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(track, const Radius.circular(4)));
    canvas.drawRect(track, Paint()..color = const Color(0xFFE2E6EC));
    final left = size.width * minimum;
    final right = size.width * maximum;
    if (right > left) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(left, 0, right, size.height));
      canvas.drawRect(track, Paint()..color = const Color(0xFFBFCBDD));
      final stripe = Paint()
        ..color = BreederColors.text.withValues(alpha: .5)
        ..strokeWidth = 2;
      for (double x = left - size.height; x < right + size.height; x += 7) {
        canvas.drawLine(
          Offset(x, size.height),
          Offset(x + size.height, 0),
          stripe,
        );
      }
      canvas.restore();
    }
    if (left > 0) {
      canvas.drawRect(
        Rect.fromLTRB(0, 0, left, size.height),
        Paint()..color = BreederColors.text,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChanceRangePainter oldDelegate) =>
      minimum != oldDelegate.minimum || maximum != oldDelegate.maximum;
}
