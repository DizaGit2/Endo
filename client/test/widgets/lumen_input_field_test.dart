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
import 'package:flutter/rendering.dart';
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
  String? hint = 'you@example.com',
  bool obscure = false,
  bool enabled = true,
  String? errorText,
  TextInputType? keyboardType,
  String? suffixText,
  String text = '',
  Brightness brightness = Brightness.light,
  int? maxLines = 1,
  int? minLines,
  int? maxLength,
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
        maxLines: maxLines,
        minLines: minLines,
        maxLength: maxLength,
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

/// The style the placeholder is actually PAINTED with.
///
/// The hint is a `Text` this widget builds (P4b-T5d), so this is the whole
/// truth about it — there is no `hintStyle` left for the decorator to merge.
TextStyle _hintStyle(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(LumenInputField),
        matching: find.byType(Text),
      ),
    )
    .style!;

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
      // The placeholder arrives as a `hint` WIDGET rather than `hintText`
      // (P4b-T5d, so it can be excluded from the field's accessible name), and
      // `InputDecoration` asserts the two are never both given — so what is
      // pinned is the drawn Text, not the string handed to the decorator.
      expect(_decoration(tester).hintText, isNull);
      expect(_decoration(tester).hint, isNotNull);
      // The design system puts the field's label ABOVE the field (see
      // `LumenFieldLabel` on screen 2), so a Material floating label would be a
      // second, duplicate label — and `labelText` is also the exact ingredient
      // in the AlertDialog teardown crash this task fixes elsewhere.
      expect(_decoration(tester).labelText, isNull);
    });

    // -----------------------------------------------------------------------
    // hint: null vs hint: '' (P4b-T25a, fix-round-1)
    // -----------------------------------------------------------------------

    testWidgets('hint: null builds no hint widget at all', (tester) async {
      await _pumpField(tester, hint: null);

      // Not "an empty hint": no hint child. An empty one still lays out a
      // full-width paragraph box, which is both a solid block in a
      // blocked-text golden and the thing that pushes the input's paint
      // offset off the pixel grid. See the class doc's measurement.
      expect(_decoration(tester).hint, isNull);
      expect(_decoration(tester).hintText, isNull);
    });

    testWidgets('hint: null paints the input on the same pixel grid a real '
        'hint does, and an empty hint does not', (tester) async {
      Future<double> inputTop(String? hint) async {
        await _pumpField(tester, hint: hint, text: '165');
        RenderEditable? editable;
        void walk(RenderObject o) {
          if (o is RenderEditable) editable = o;
          o.visitChildren(walk);
        }

        walk(tester.renderObject(find.byType(TextField)));
        return editable!.localToGlobal(Offset.zero).dy;
      }

      // The measured discriminator behind rule 9 in `golden_app.dart`. An
      // empty hint reports a LARGER alphabetic baseline than a shaped one in
      // the identical style, so `InputDecorator` leaves
      // `hintBaseline - inputBaseline` in the input's paint offset; that
      // fraction is the one quantity two host font backends disagreed about,
      // and it reddened four goldens on this branch's first push.
      final double withRealHint = await inputTop('Maya');
      final double withNoHint = await inputTop(null);

      expect(withNoHint, withRealHint);
      // Whole or half pixels only — the property that makes a golden
      // reproducible on another host.
      expect((withNoHint * 2) % 1, 0);
    });

    test("hint: '' is rejected: pass null for no placeholder", () {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      expect(
        () => LumenInputField(controller: controller, label: 'L', hint: ''),
        throwsA(
          isA<AssertionError>().having(
            (AssertionError e) => e.message.toString(),
            'message',
            allOf(contains('hint: null'), contains('1.031421661376953')),
          ),
        ),
      );
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
              LumenInputField(controller: without, label: 'Name', hint: 'Maya'),
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
      // Read off the PAINTED Text, not off `decoration.hintStyle`. Since
      // P4b-T5d the placeholder is a `hint` widget this file builds, and
      // `hintStyle` would not reach it — a decoration property nothing renders
      // is exactly the assertion that keeps passing after the pixels move.
      final hint = _hintStyle(tester);

      expect(hint.color, lumenLight.muted.withValues(alpha: 0.6));
      expect(hint.fontSize, 14);
      expect(hint.fontWeight, FontWeight.w400);
    });

    testWidgets('the hint still inherits the text theme it used to inherit', (
      tester,
    ) async {
      // `InputDecorator` composes a hint's style from `bodyLarge` and applies
      // it only to the `Text` it builds itself (`_getInlineHintStyle`,
      // `input_decorator.dart:2199-2210`), so a hand-built `hint` widget that
      // forgot that base would draw the same string at a different tracking and
      // line height — a pixel move with no failing token assertion. These two
      // numbers come from `bodyLarge` and from nothing this widget sets.
      await _pumpField(tester);
      final hint = _hintStyle(tester);

      expect(hint.letterSpacing, 0.5);
      expect(hint.height, 1.5);
      expect(hint.fontFamily, 'Roboto');
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

    testWidgets('the hint takes the dark palette too', (tester) async {
      await _pumpField(tester, brightness: Brightness.dark);

      expect(_hintStyle(tester).color, lumenDark.muted.withValues(alpha: 0.6));
    });
  });

  // -------------------------------------------------------------------------
  // maxLines / minLines / maxLength (P4b-T19c) — screen 12's notes field
  // -------------------------------------------------------------------------

  group('multiline (P4b-T19c)', () {
    testWidgets(
      'maxLines defaults to 1 and minLines/maxLength default to null — the '
      'five existing call sites are unaffected',
      (tester) async {
        await _pumpField(tester);

        expect(_field(tester).maxLines, 1);
        expect(_field(tester).minLines, isNull);
        expect(_field(tester).maxLength, isNull);
      },
    );

    testWidgets('maxLines and minLines forward to the TextField', (
      tester,
    ) async {
      await _pumpField(tester, maxLines: 4, minLines: 4);

      expect(_field(tester).maxLines, 4);
      expect(_field(tester).minLines, 4);
    });

    testWidgets('maxLength forwards to the TextField', (tester) async {
      await _pumpField(tester, maxLines: 4, minLines: 4, maxLength: 2000);

      expect(_field(tester).maxLength, 2000);
    });

    testWidgets(
      'input is truncated at the cap — a raw client cap the contract\'s '
      'MaxNotesLength=2000 can never be exceeded by',
      (tester) async {
        final controller = await _pumpField(
          tester,
          maxLines: 4,
          minLines: 4,
          maxLength: 5,
        );

        await tester.enterText(find.byType(TextField), '1234567890');

        expect(
          controller.text.length,
          lessThanOrEqualTo(5),
          reason:
              'Flutter\'s default maxLengthEnforcement must actually be '
              'wired — without `maxLength` reaching the TextField, nothing '
              'stops more than the cap from landing in the controller.',
        );
      },
    );

    testWidgets(
      'the counter is styled from the design tokens, not Flutter\'s default',
      (tester) async {
        await _pumpField(tester, maxLines: 4, minLines: 4, maxLength: 2000);
        final style = _decoration(tester).counterStyle!;

        // Same 12/w400 scale the errorText/message treatment already uses in
        // this file, so the counter reads as part of the same field rather
        // than a stock Material addition.
        expect(style.fontSize, 12);
        expect(style.fontWeight, FontWeight.w400);
        expect(style.color, lumenLight.muted);
      },
    );

    testWidgets(
      'obscure with a multiline maxLines throws an assertion naming both '
      'parameters',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        expect(
          () => LumenInputField(
            controller: controller,
            label: 'Password',
            hint: '',
            obscure: true,
            maxLines: 4,
          ),
          throwsA(
            isA<AssertionError>().having(
              (e) => '${e.message}',
              'message',
              allOf(contains('obscure'), contains('maxLines')),
            ),
          ),
          reason:
              'obscure: true and a multiline maxLines have no sane rendering '
              '— Flutter\'s own TextField asserts the same combination for '
              'the same reason (obscureText == false || maxLines == 1).',
        );
      },
    );

    testWidgets(
      'obscure with maxLines left at its default of 1 does not throw — '
      'account_screen.dart\'s password field must keep working',
      (tester) async {
        // No expect(throwsA) here on purpose: a build that throws fails the
        // pump itself, so simply completing this pump IS the assertion.
        await _pumpField(tester, obscure: true);

        expect(_field(tester).obscureText, isTrue);
      },
    );
  });
}
