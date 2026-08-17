import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/shell/presentation/tab_placeholder_screen.dart';

// Phone-frame dimensions matching the design spec.
const _kWidth = 390.0;
const _kHeight = 844.0;

/// Wraps [TabPlaceholderScreen] in a self-contained, size-bounded [MaterialApp]
/// for use in golden tests. [MediaQuery] is injected so Scaffold safe-area
/// logic resolves correctly inside Alchemist's bare test wrapper.
Widget _buildApp(Brightness brightness) {
  return SizedBox(
    width: _kWidth,
    height: _kHeight,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(_kWidth, _kHeight)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lumenTheme(brightness),
        home: const TabPlaceholderScreen(heading: 'Hormones aren\'t here yet'),
      ),
    ),
  );
}

void main() {
  goldenTest(
    'TabPlaceholderScreen light theme',
    fileName: 'tab_placeholder_screen_light',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(name: 'Light', child: _buildApp(Brightness.light)),
      ],
    ),
  );

  goldenTest(
    'TabPlaceholderScreen dark theme',
    fileName: 'tab_placeholder_screen_dark',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(name: 'Dark', child: _buildApp(Brightness.dark)),
      ],
    ),
  );
}
