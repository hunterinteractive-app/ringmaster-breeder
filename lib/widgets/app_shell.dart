import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Material(
    color: BreederColors.background,
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
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
  );
}
