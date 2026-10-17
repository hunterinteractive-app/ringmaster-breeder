import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import 'adaptive_layout.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Material(
    color: BreederColors.background,
    child: LayoutBuilder(
      builder: (context, constraints) => AdaptiveUi(
        compact:
            constraints.maxWidth < 600 ||
            constraints.maxHeight - MediaQuery.viewInsetsOf(context).bottom <
                500,
        child: Column(
          children: [
            Expanded(child: child),
            if (MediaQuery.viewInsetsOf(context).bottom == 0 &&
                constraints.maxHeight >= 400)
              SafeArea(
                top: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  child: const Text(
                    'Version ${AppConfig.version}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: BreederColors.text, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
