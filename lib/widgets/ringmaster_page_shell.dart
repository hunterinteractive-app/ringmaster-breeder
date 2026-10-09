// lib/widgets/ringmaster_page_shell.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RingMasterPageShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;

  final bool showHomeButton;
  final bool showBackButton;
  final VoidCallback? onBack;

  final List<Widget>? actions;
  final Widget? leading;
  final Widget? logo;

  final bool useScrollView;
  final EdgeInsetsGeometry bodyPadding;
  final Color? backgroundColor;
  final Color? headerColor;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  const RingMasterPageShell({
    super.key,
    required this.title,
    required this.body,
    this.subtitle = 'RingMaster Breeder',
    this.showHomeButton = true,
    this.showBackButton = true,
    this.onBack,
    this.actions,
    this.leading,
    this.logo,
    this.useScrollView = false,
    this.bodyPadding = EdgeInsets.zero,
    this.backgroundColor,
    this.headerColor,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  bool _canPop(BuildContext context) {
    return Navigator.of(context).canPop();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    final isMobile = screenWidth < 700;
    final isTablet = screenWidth >= 700 && screenWidth < 1100;

    final topColor = headerColor ?? BreederColors.header;
    final pageBg = backgroundColor ?? BreederColors.background;

    final horizontalPadding = isMobile
        ? 16.0
        : isTablet
        ? 20.0
        : 24.0;

    final topPadding = isMobile ? 12.0 : 16.0;
    final bottomRadius = isMobile ? 24.0 : 28.0;

    final logoSize = isMobile
        ? 64.0
        : isTablet
        ? 78.0
        : 88.0;

    // Mobile header size
    final titleSize = isMobile
        ? 24.0
        : isTablet
        ? 34.0
        : 38.0;

    final subtitleSize = isMobile
        ? 15.0
        : isTablet
        ? 17.0
        : 18.0;

    final iconSize = isMobile ? 22.0 : 24.0;

    final shouldShowBack =
        leading != null || (showBackButton && _canPop(context));

    final paddedBody = useScrollView
        ? SingleChildScrollView(padding: bodyPadding, child: body)
        : Padding(padding: bodyPadding, child: body);

    final resolvedBody = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: SizedBox(width: double.infinity, child: paddedBody),
      ),
    );
    final resolvedLogo =
        logo ??
        Image.asset(
          'assets/images/ringmaster_breeder_logo_transparent.png',
          semanticLabel: 'RingMaster Breeder logo',
        );
    final resolvedActions = <Widget>[
      if (showHomeButton)
        IconButton(
          tooltip: 'Home',
          icon: const Icon(Icons.home_outlined),
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      ...(actions ?? const []),
    ];

    return Scaffold(
      backgroundColor: topColor,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              color: topColor,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                topPadding,
                horizontalPadding,
                18,
              ),
              child: isMobile
                  ? _MobileHeader(
                      title: title,
                      subtitle: subtitle,
                      logo: resolvedLogo,
                      leading: leading,
                      showBack: shouldShowBack,
                      onBack: onBack,
                      actions: resolvedActions,
                      topColor: topColor,
                      logoSize: logoSize,
                      titleSize: titleSize,
                      subtitleSize: subtitleSize,
                      iconSize: iconSize,
                    )
                  : _WideHeader(
                      title: title,
                      subtitle: subtitle,
                      logo: resolvedLogo,
                      leading: leading,
                      showBack: shouldShowBack,
                      onBack: onBack,
                      actions: resolvedActions,
                      topColor: topColor,
                      logoSize: logoSize,
                      titleSize: titleSize,
                      subtitleSize: subtitleSize,
                      iconSize: iconSize,
                    ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: pageBg,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(bottomRadius),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(bottomRadius),
                  ),
                  child: Material(color: pageBg, child: resolvedBody),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? logo;
  final Widget? leading;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Color topColor;
  final double logoSize;
  final double titleSize;
  final double subtitleSize;
  final double iconSize;

  const _MobileHeader({
    required this.title,
    required this.subtitle,
    required this.logo,
    required this.leading,
    required this.showBack,
    required this.onBack,
    required this.actions,
    required this.topColor,
    required this.logoSize,
    required this.titleSize,
    required this.subtitleSize,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final canShowLogo = logo != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showBack)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child:
                    leading ??
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: iconSize,
                      ),
                      onPressed:
                          onBack ?? () => Navigator.of(context).maybePop(),
                    ),
              ),
            if (canShowLogo)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: logoSize,
                  height: logoSize,
                  child: FittedBox(fit: BoxFit.contain, child: logo),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .9),
                          fontSize: subtitleSize,
                          fontWeight: FontWeight.w400,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: actions
                .map((action) => _HeaderActionContainer(child: action))
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _WideHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? logo;
  final Widget? leading;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Color topColor;
  final double logoSize;
  final double titleSize;
  final double subtitleSize;
  final double iconSize;

  const _WideHeader({
    required this.title,
    required this.subtitle,
    required this.logo,
    required this.leading,
    required this.showBack,
    required this.onBack,
    required this.actions,
    required this.topColor,
    required this.logoSize,
    required this.titleSize,
    required this.subtitleSize,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child:
                leading ??
                IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: iconSize,
                  ),
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                ),
          ),
        if (logo != null)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: logoSize,
              height: logoSize,
              child: FittedBox(fit: BoxFit.contain, child: logo),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .9),
                    fontSize: subtitleSize,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions
                .map((action) => _HeaderActionContainer(child: action))
                .toList(),
          ),
      ],
    );
  }
}

class _HeaderActionContainer extends StatelessWidget {
  final Widget child;

  const _HeaderActionContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return IconTheme(
      data: const IconThemeData(color: Colors.white),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: child,
      ),
    );
  }
}
