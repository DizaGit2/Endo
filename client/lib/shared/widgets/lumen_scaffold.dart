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
/// **Theming (P4b-T5).** The mockups (screens 8/10/11) draw the bar flat:
///
/// ```css
/// .nav{ display:flex; border-top:1px solid var(--bd); padding-top:8px; }
/// .nb { flex:1; text-align:center; font-size:9px; color:var(--mut); }
/// .nb.on{ color:var(--ac); font-weight:500; }
/// ```
///
/// An unthemed M3 [NavigationBar] gets none of that: its indicator is
/// `ColorScheme.secondaryContainer`, its unselected items are
/// `onSurfaceVariant`, its background is a tinted `surfaceContainer` and it
/// carries an elevation shadow — four colours that are not Lumen tokens and do
/// not become them by adjusting the [ColorScheme], because those roles are
/// derived. So the bar is themed explicitly here, in the one place it is
/// built, rather than in `lumenTheme` where it would also restyle any other
/// navigation bar the app grows.
///
/// Departures from the CSS, all stated so a reviewer does not have to guess:
///
/// - **Label size is 11, not 9 — which is the proportional scale, not a
///   judgement call.** The mockups are drawn inside a 300 px-wide browser
///   frame and the app renders at 390 logical px: 9 x 390/300 = 11.7, so 11 is
///   what the mockup's 9 px *is* at this width.
/// - **The selection indicator is kept**, on [LumenColors.accentSoft]. The
///   mockups show no pill because CSS has no such affordance, but accent-soft
///   behind an accent glyph is exactly how the mockups draw every other
///   selected chip (screen 9's mood tiles: `.m.on{background:var(--acs)}`), and
///   dropping the indicator would also drop M3's touch/focus feedback.
/// - **Icon size 22**, matching the icon size the settings screens already use
///   (`profile_screen.dart`'s chevrons) rather than the mockup's 14 px glyph,
///   which is a text-rendered dingbat and not a comparable measurement.
/// - **The mockup's `.nav{padding-top:8px}` is not reproduced.** [NavigationBar]
///   supplies its own height and centres its items in it; adding 8 px on top of
///   that would offset the row rather than reproduce the CSS box.
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
    final c = Theme.of(context).extension<LumenColors>()!;

    Color itemColor(Set<WidgetState> states) =>
        states.contains(WidgetState.selected) ? c.accent : c.muted;

    return DecoratedBox(
      // The bar paints its own surface and the mockups' hairline; the
      // NavigationBar inside it is transparent so the border is not covered.
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          indicatorColor: c.accentSoft,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w500
                  : FontWeight.w400,
              color: itemColor(states),
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(size: 22, color: itemColor(states)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: _destinations,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
        ),
      ),
    );
  }
}
