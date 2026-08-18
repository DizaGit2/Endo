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
  String? errorText,
  TextInputType? keyboardType,
  String? suffixText,
  String text = '',
  Brightness brightness = Brightness.light,
}) async {
  final controller = TextEditingController(text: text);
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
        errorText: errorText,
        keyboardType: keyboardType,
        suffixText: suffixText,
      ),
    ),
  );
  return controller;
}

/// What the suffix is actually PAINTED at.
///
/// Material renders `suffixText` through `_AffixText`, which wraps it in
/// `AnimatedOpacity(opacity: labelIsFloating ? 1.0 : 0.0)`
/// (`input_decorator.dart:1827-1830`) — so the widget is in the tree, laid out
/// and reserving its strip, at zero opacity. `find.text('cm')` cannot tell the
/// two states apart; this can.
double _suffixOpacity(WidgetTester tester, String suffix) {
  return tester
      .widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.text(suffix),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;
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
  // Per-field errors (P4b-T7) — what screen 2 binds `ValidationFailure.fields`
  // to. The widget dartdoc has always said a screen needing per-field errors
  // "should render them beside the field"; this is that, once, instead of
  // thirteen screens each inventing a Text under a box.
  // -------------------------------------------------------------------------

  group('errorText', () {
    testWidgets('renders the message it is given, and none when given none', (
      tester,
    ) async {
      // Both fields in ONE tree. "This field shows no error" is also true of
      // every field that has never been told about one, so the erroring field
      // beside it is the control: same widget, same theme, same pump.
      final withError = TextEditingController();
      final without = TextEditingController();
      addTearDown(withError.dispose);
      addTearDown(without.dispose);

      await pumpApp(
        tester,
        home: Scaffold(
          body: Column(
            children: [
              LumenInputField(
                controller: withError,
                label: 'Email',
                hint: 'you@example.com',
                errorText: 'Enter a valid email address.',
              ),
              LumenInputField(
                controller: without,
                label: 'Name',
                hint: 'Maya',
              ),
            ],
          ),
        ),
      );

      final fields = find.byType(TextField);
      expect(
        tester.widget<TextField>(fields.at(0)).decoration!.errorText,
        'Enter a valid email address.',
      );
      expect(
        tester.widget<TextField>(fields.at(1)).decoration!.errorText,
        isNull,
      );
      // Rendered, not merely configured.
      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });

    testWidgets('the error borders keep the 12 px radius the rest of the '
        'field uses', (tester) async {
      // Material's default error border is not the one this design system
      // draws: leaving `errorBorder` unset swaps the 12 px outline for the
      // theme's 4 px one the moment a field goes red.
      await _pumpField(tester, errorText: 'Nope.');
      final decoration = _decoration(tester);

      for (final border in <InputBorder?>[
        decoration.errorBorder,
        decoration.focusedErrorBorder,
      ]) {
        expect(_border(border).radius, 12);
        expect(_border(border).color, const Color(0xFFB3261E));
      }
    });

    testWidgets('the message is drawn at 12 / w400, on the error colour', (
      tester,
    ) async {
      // Two weights only (CLAUDE.md); 12 is the size the label above the field
      // uses, so the box reads as one unit rather than three type scales.
      await _pumpField(tester, errorText: 'Nope.');
      final style = _decoration(tester).errorStyle!;

      expect(style.fontSize, 12);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.color, const Color(0xFFB3261E));
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
  // The suffix — drawn, and drawn when the field is EMPTY (P4b-T10, round 2)
  // -------------------------------------------------------------------------

  group('suffixText', () {
    testWidgets('it is painted on an EMPTY, unfocused field', (tester) async {
      await _pumpField(tester, suffixText: 'cm');

      // The state a first-time onboarding user starts screen 4 in. Material
      // gates prefix/suffix opacity on `labelShouldWithdraw`
      // (`input_decorator.dart:2434`), which is `!isEmpty || (isFocused &&
      // enabled)` (`:1969`) — so without `FloatingLabelBehavior.always`
      // (`:2076-2078`) the unit is laid out and painted at opacity 0.
      //
      // Presence is NOT the assertion. `find.text('cm')` passes against a
      // zero-opacity widget, which is exactly how this shipped once: a
      // presence check sold as a visibility check.
      expect(find.text('cm'), findsOneWidget);
      expect(_suffixOpacity(tester, 'cm'), 1.0);
    });

    testWidgets('it is still painted once the field has content', (
      tester,
    ) async {
      // The control for the row above, and the case a hint could never serve:
      // a prefilled field is non-empty from its first frame, so a hint has
      // already gone by the time the user reads it.
      await _pumpField(tester, suffixText: 'cm', text: '165');

      expect(_suffixOpacity(tester, 'cm'), 1.0);
    });

    testWidgets('a field with no suffix draws none', (tester) async {
      // The control that keeps the two rows above about the SUFFIX rather
      // than about any text the decoration happens to contain.
      await _pumpField(tester, hint: 'kg');

      expect(find.text('cm'), findsNothing);
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
