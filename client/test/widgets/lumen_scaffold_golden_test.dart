import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_theme.dart';
import 'package:lumen/shared/widgets/lumen_scaffold.dart';

// Phone-frame dimensions used by the design system (portrait, standard).
const _kWidth = 390.0;
const _kHeight = 844.0;

/// Builds a self-contained, size-bounded app that renders [LumenScaffold].
///
/// [SizedBox] with explicit phone-frame dimensions gives the [Scaffold] and
/// [GoldenTestGroup]'s intrinsic-width table a bounded height constraint,
/// avoiding "RenderObject given an infinite size" errors.
/// [MediaQuery] is injected so [Scaffold]'s safe-area logic resolves
/// correctly inside Alchemist's bare test wrapper.
Widget _buildApp(Brightness brightness) {
  return SizedBox(
    width: _kWidth,
    height: _kHeight,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(_kWidth, _kHeight)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lumenTheme(brightness),
        home: LumenScaffold(
          appBar: AppBar(title: const Text('Lumen')),
          bottomNavigationBar: const LumenBottomNav(currentIndex: 0),
          padding: const EdgeInsets.all(16),
          body: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Today',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text('Cycle day 14 · Ovulatory phase'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  goldenTest(
    'LumenScaffold light theme',
    fileName: 'lumen_scaffold_light',
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
    'LumenScaffold dark theme',
    fileName: 'lumen_scaffold_dark',
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
