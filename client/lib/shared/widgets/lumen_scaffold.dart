import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// A themed [Scaffold] wrapper that applies the Lumen design-system background.
///
/// Background colour is taken from [LumenColors.bg] registered on the ambient
/// [Theme] as a [ThemeExtension]. If the extension is unavailable (e.g. in a
/// bare [MaterialApp]), [Theme.of(context).scaffoldBackgroundColor] is used as
/// a fallback so the widget is always safe to render.
///
/// Props:
/// - [body] — required content area.
/// - [appBar] — optional [PreferredSizeWidget] (e.g. [AppBar]).
/// - [bottomNavigationBar] — optional bottom bar widget (e.g. [LumenBottomNav]).
/// - [padding] — optional [EdgeInsets] applied to [body] via a [Padding] widget.
class LumenScaffold extends StatelessWidget {
  const LumenScaffold({
    required this.body,
    super.key,
    this.appBar,
    this.bottomNavigationBar,
    this.padding,
  });

  /// The primary content of the scaffold.
  final Widget body;

  /// An optional app bar displayed at the top of the scaffold.
  final PreferredSizeWidget? appBar;

  /// An optional widget displayed at the bottom of the scaffold.
  final Widget? bottomNavigationBar;

  /// Optional padding applied around [body].
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final lumenColors = Theme.of(context).extension<LumenColors>();
    final bgColor =
        lumenColors?.bg ?? Theme.of(context).scaffoldBackgroundColor;

    final effectiveBody =
        padding != null ? Padding(padding: padding!, child: body) : body;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      body: effectiveBody,
    );
  }
}

/// Lumen's 5-destination bottom navigation bar.
///
/// Uses Material 3 [NavigationBar] with the five tabs defined by the Lumen
/// design: Home, Cycle, Hormones, Body, More. **The destination order is
/// load-bearing** — it is the branch order of the `StatefulShellRoute` in
/// `lumenRoutes()`, which addresses its branches by index. Reordering here
/// without reordering there sends taps to the wrong tab.
///
/// It holds no state: since P4b-T2 the router is the selected-tab state, and
/// the shell passes [currentIndex] down and turns [onDestinationSelected] into
/// `StatefulNavigationShell.goBranch`.
///
/// Props:
/// - [currentIndex] — currently selected tab index (0–4).
/// - [onDestinationSelected] — optional callback when a destination is tapped.
class LumenBottomNav extends StatelessWidget {
  const LumenBottomNav({
    required this.currentIndex,
    super.key,
    this.onDestinationSelected,
  });

  /// The index of the currently selected destination (0–4).
  final int currentIndex;

  /// Called when the user taps a destination. May be null.
  final ValueChanged<int>? onDestinationSelected;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.calendar_month_outlined),
      selectedIcon: Icon(Icons.calendar_month),
      label: 'Cycle',
    ),
    NavigationDestination(
      icon: Icon(Icons.science_outlined),
      selectedIcon: Icon(Icons.science),
      label: 'Hormones',
    ),
    NavigationDestination(
      icon: Icon(Icons.monitor_weight_outlined),
      selectedIcon: Icon(Icons.monitor_weight),
      label: 'Body',
    ),
    NavigationDestination(
      icon: Icon(Icons.more_horiz_outlined),
      selectedIcon: Icon(Icons.more_horiz),
      label: 'More',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: _destinations,
    );
  }
}
