import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/features/settings/presentation/privacy_screen.dart';

// Phone-frame dimensions matching the design spec.
const _kWidth = 390.0;
const _kHeight = 844.0;

/// Wraps [PrivacyScreen] in a self-contained, size-bounded [MaterialApp] for
/// use in golden tests.
Widget _buildApp(Brightness brightness) {
  return SizedBox(
    width: _kWidth,
    height: _kHeight,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(_kWidth, _kHeight)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lumenTheme(brightness),
        home: const PrivacyScreen(),
      ),
    ),
  );
}

void main() {
  goldenTest(
    'PrivacyScreen light theme',
    fileName: 'privacy_screen_light',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'Light',
          child: _buildApp(Brightness.light),
        ),
      ],
    ),
  );

  goldenTest(
    'PrivacyScreen dark theme',
    fileName: 'privacy_screen_dark',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'Dark',
          child: _buildApp(Brightness.dark),
        ),
      ],
    ),
  );
}
