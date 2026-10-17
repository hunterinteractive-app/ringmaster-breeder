import 'package:flutter/material.dart';

/// Shared density rules. Text scaling and touch targets remain accessible;
/// compact layouts recover space from decoration, gaps and secondary content.
class BreederLayout {
  static bool compact(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_DensityScope>();
    final media = MediaQuery.of(context);
    return scope?.compact ??
        (media.size.width < 600 ||
            media.size.height - media.viewInsets.bottom < 500);
  }

  static EdgeInsets pagePadding(BuildContext context, {double normal = 24}) =>
      EdgeInsets.all(compact(context) ? 12 : normal);

  static EdgeInsets padding(BuildContext context, EdgeInsetsGeometry padding) {
    final resolved = padding.resolve(Directionality.of(context));
    if (!compact(context)) return resolved;
    double edge(double value) => value >= 16 ? 12 : value;
    return EdgeInsets.fromLTRB(
      edge(resolved.left),
      edge(resolved.top),
      edge(resolved.right),
      edge(resolved.bottom),
    );
  }
}

class AdaptiveUi extends StatelessWidget {
  final bool compact;
  final Widget child;
  const AdaptiveUi({super.key, required this.compact, required this.child});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final theme = compact
        ? base.copyWith(
            textTheme: base.textTheme.copyWith(
              headlineLarge: base.textTheme.headlineLarge?.copyWith(
                fontSize: 26,
              ),
              headlineMedium: base.textTheme.headlineMedium?.copyWith(
                fontSize: 22,
              ),
              headlineSmall: base.textTheme.headlineSmall?.copyWith(
                fontSize: 20,
              ),
              titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 18),
            ),
            inputDecorationTheme: base.inputDecorationTheme.copyWith(
              isDense: true,
              contentPadding: const EdgeInsets.all(12),
            ),
            cardTheme: base.cardTheme.copyWith(
              margin: const EdgeInsets.symmetric(vertical: 6),
            ),
            listTileTheme: base.listTileTheme.copyWith(
              minTileHeight: 56,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              minVerticalPadding: 4,
            ),
            expansionTileTheme: base.expansionTileTheme.copyWith(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            ),
            dialogTheme: base.dialogTheme.copyWith(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
            ),
          )
        : base;
    // Keep this tree identical across resizing so routes and form state survive.
    return _DensityScope(
      compact: compact,
      child: Theme(data: theme, child: child),
    );
  }
}

class _DensityScope extends InheritedWidget {
  final bool compact;
  const _DensityScope({required this.compact, required super.child});

  @override
  bool updateShouldNotify(_DensityScope oldWidget) =>
      compact != oldWidget.compact;
}

class AdaptivePadding extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final Widget child;
  const AdaptivePadding({
    super.key,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) =>
      Padding(padding: BreederLayout.padding(context, padding), child: child);
}

class AdaptiveGap extends StatelessWidget {
  final double height;
  const AdaptiveGap({super.key, required this.height});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: BreederLayout.compact(context) ? height * 2 / 3 : height,
  );
}

/// Summaries remain available without pushing phone records below the fold.
class AdaptiveOverview extends StatelessWidget {
  final String title;
  final Widget child;
  const AdaptiveOverview({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => BreederLayout.compact(context)
      ? ExpansionTile(
          key: PageStorageKey(title),
          title: Text(title),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [child],
        )
      : child;
}
