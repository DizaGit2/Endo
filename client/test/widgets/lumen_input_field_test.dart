// Tests for LumenInputField — the promoted `_InputField` (P4b-T5).
//
// TDD (RED first): this widget did not exist. It was `_InputField`, private to
// `account_screen.dart`, and screens 3-7, 12, 13 and 32 all need the same
// field. Promotion is only safe if it is byte-for-byte the same decoration, so
// every assertion below pins one property the private copy set — screen 2's
// golden is the fidelity bar and must pass unmodified.
//
// The one deliberate difference: the private copy took `LumenColors colors` as
// a constructor argument; the promoted one reads the extension off the ambient
// theme. Every former call site passed exactly what `Theme.of(context)
// .extension<LumenColors>()!` returns for the same subtree, so the rendered
// result is identical — and thirteen new screens do not have to thread a
// parameter that has one possible value.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';

import '../support/harness.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<TextEditingController> _pumpField(
  WidgetTester tester, {
  String label = 'Email',
  String hint = 'you@example.com',
  bool obscure = false,
  bool enabled = true,
  TextInputType? keyboardType,
  Brightness brightness = Brightness.light,
}) async {
  final controller = TextEditingController();
  addTearDown(controller.dispose);

  await pumpApp(
    tester,
    brightness: brightness,
    home: Scaffold(
      body: LumenInputField(
        controller: controller,
        label: label,
        hint: hint,
        obscure: obscure,
        enabled: enabled,
        keyboardType: keyboardType,
      ),
    ),
  );
  return controller;
}

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

InputDecoration _decoration(WidgetTester tester) => _field(tester).decoration!;

/// The single [BorderSide] of an [OutlineInputBorder], plus its radius.
({Color color, double radius}) _border(InputBorder? border) {
  final outline = border! as OutlineInputBorder;
  return (
    color: outline.borderSide.color,
    radius: (outline.borderRadius.topLeft).x,
  );
}

void main() {
  // -------------------------------------------------------------------------
  // Behaviour
  // -------------------------------------------------------------------------

  group('behaviour', () {
    testWidgets('writes what the user types into the controller it was given', (
      tester,
    ) async {
      final controller = await _pumpField(tester);

      await tester.enterText(find.byType(TextField), 'maya@example.com');

      expect(controller.text, 'maya@example.com');
    });

    testWidgets('renders the hint as a placeholder, not a floating label', (
      tester,
    ) async {
      await _pumpField(tester, hint: 'Maya');

      expect(find.text('Maya'), findsOneWidget);
      expect(_decoration(tester).hintText, 'Maya');
      // The design system puts the field's label ABOVE the field (see
      // `_FieldLabel` on screen 2), so a Material floating label would be a
      // second, duplicate label — and `labelText` is also the exact ingredient
      // in the AlertDialog teardown crash this task fixes elsewhere.
      expect(_decoration(tester).labelText, isNull);
    });

    testWidgets('obscure: true hides the entered text', (tester) async {
      await _pumpField(tester, obscure: true);

      expect(_field(tester).obscureText, isTrue);
    });

    testWidgets('obscure defaults to false', (tester) async {
      await _pumpField(tester);

      expect(_field(tester).obscureText, isFalse);
    });

    testWidgets('enabled: false makes the field non-editable', (tester) async {
      final controller = await _pumpField(tester, enabled: false);

      expect(_field(tester).enabled, isFalse);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'nope');

      expect(controller.text, isEmpty);
    });

    testWidgets('forwards the keyboard type', (tester) async {
      await _pumpField(tester, keyboardType: TextInputType.emailAddress);

      expect(_field(tester).keyboardType, TextInputType.emailAddress);
    });
  });

  // -------------------------------------------------------------------------
  // Decoration — the exact treatment `_InputField` shipped with
  // -------------------------------------------------------------------------

  group('decoration (light)', () {
    testWidgets('is filled with the input token, not the surface', (
      tester,
    ) async {
      await _pumpField(tester);
      final decoration = _decoration(tester);

      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, lumenLight.input);
    });

    testWidgets('rests on the border token and focuses onto the accent', (
      tester,
    ) async {
      await _pumpField(tester);
      final decoration = _decoration(tester);

      expect(_border(decoration.border).color, lumenLight.border);
      expect(_border(decoration.enabledBorder).color, lumenLight.border);
      expect(_border(decoration.disabledBorder).color, lumenLight.border);
      expect(_border(decoration.focusedBorder).color, lumenLight.accent);
    });

    testWidgets('every border corner is 12', (tester) async {
      await _pumpField(tester);
      final decoration = _decoration(tester);

      for (final border in <InputBorder?>[
        decoration.border,
        decoration.enabledBorder,
        decoration.disabledBorder,
        decoration.focusedBorder,
      ]) {
        expect(_border(border).radius, 12);
      }
    });

    testWidgets('content padding is 14 horizontal / 13 vertical', (
      tester,
    ) async {
      await _pumpField(tester);

      expect(
        _decoration(tester).contentPadding,
        const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      );
    });

    testWidgets('the hint is muted at 60% alpha, 14/w400', (tester) async {
      await _pumpField(tester);
      final hint = _decoration(tester).hintStyle!;

      expect(hint.color, lumenLight.muted.withValues(alpha: 0.6));
      expect(hint.fontSize, 14);
      expect(hint.fontWeight, FontWeight.w400);
    });

    testWidgets('the entered text is ink at 14', (tester) async {
      await _pumpField(tester);
      final style = _field(tester).style!;

      expect(style.color, lumenLight.ink);
      expect(style.fontSize, 14);
    });
  });

  // -------------------------------------------------------------------------
  // Dark theme — the tokens must actually be read from the theme
  // -------------------------------------------------------------------------

  group('decoration (dark)', () {
    testWidgets('takes its colours from the dark palette', (tester) async {
      await _pumpField(tester, brightness: Brightness.dark);
      final decoration = _decoration(tester);

      expect(decoration.fillColor, lumenDark.input);
      expect(_border(decoration.enabledBorder).color, lumenDark.border);
      expect(_border(decoration.focusedBorder).color, lumenDark.accent);
      expect(_field(tester).style!.color, lumenDark.ink);
    });
  });
}
