import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// The Lumen text field: a filled [TextField] on [LumenColors.input] with a
/// 12 px rounded outline that turns [LumenColors.accent] on focus.
///
/// Promoted verbatim from `account_screen.dart`'s private `_InputField`
/// (P4b-T5). Screens 3-7, 12, 13 and 32 all take free text, and thirteen
/// copies of an `InputDecoration` this long is thirteen chances for one of
/// them to drift off the tokens.
///
/// One thing changed in the promotion: the private copy took `LumenColors
/// colors` as a required argument. This one reads the extension off the
/// ambient [Theme], because every call site passed exactly what
/// `Theme.of(context).extension<LumenColors>()!` answers for the same subtree
/// — a parameter with one possible value is a parameter that can be passed
/// wrongly.
///
/// Deliberately NOT a `TextFormField`: there is no `Form` anywhere in the
/// client and the rules live outside the widget tree (see `error_mapper.dart`'s
/// `ValidationFailure.fields`, and `account_validation.dart` for the
/// client-side mirror of them). A screen that needs per-field errors passes
/// [errorText] rather than reaching for Flutter's validator machinery halfway —
/// the same string arrives whether the device rejected the form or the server
/// did, so there is one rendering path for both.
///
/// **Accessible name (P4b-T5b).** [label] is required and is what a screen
/// reader announces for the field. It has to be: the design system draws the
/// label as a separate `Text` ABOVE the field, and Flutter has no
/// `aria-labelledby` to associate the two — so a field with only hint text
/// announces its PLACEHOLDER ("Maya"), and the "Name" above it is a decorative
/// string associated with nothing. Passing the same string twice is the price
/// of that; a field nobody can name is not.
///
/// Implemented as a bare `Semantics(label:)`, which MERGES into the field's own
/// node. Do not "improve" it to `Semantics(label:, textField: true)` — that
/// makes the annotation a semantics boundary and produces TWO nodes, an empty
/// text-field container wrapping the real field.
///
/// **The placeholder is drawn, never announced (P4b-T5d).** It used to merge
/// into the name as well, so an empty field announced `"Name\nMaya"` — and
/// screen 2's password field, whose placeholder is eight U+2022 bullets
/// (`account_screen.dart:173`), announced *"Password, bullet bullet bullet
/// bullet bullet bullet bullet bullet, secure text field"*. A placeholder is a
/// hint about what goes in the box; it is not what the control is called.
///
/// The fix costs no pixels: `InputDecorator` prefers `decoration.hint` over the
/// `Text` it would build from `decoration.hintText`
/// (`input_decorator.dart:2333-2335`), so the same string is drawn by an
/// [ExcludeSemantics]-wrapped [Text] of this widget's own. The catch is that a
/// supplied `hint` gets **no** style applied — `hintStyle` only ever reaches the
/// `Text` the decorator builds itself — so the style is composed here exactly
/// as `_getInlineHintStyle` (`:2199-2210`) composes it: the M3 text theme's
/// `bodyLarge`, merged with the field's own `style` (the decorator's
/// `baseStyle`), merged with what `hintStyle` used to carry. The one term left
/// out is `_InputDecoratorDefaultsM3.hintStyle` (`:5956-5961`), which sets a
/// colour and nothing else, and that colour is overridden either way.
///
/// The proof that it costs no pixels is the committed golden pair, which draws
/// this field's placeholder in both themes; a mutation to the hint's font size
/// reddens both, so they are watching it.
///
/// Props:
/// - [controller] — the caller owns it, and must dispose it.
/// - [label] — the field's accessible name; pass the same string the screen
///   renders above the field.
/// - [hint] — placeholder text, drawn but not announced; there is no floating
///   label by design (the design system puts the label above the field, see
///   `LumenFieldLabel`).
/// - [obscure] — password entry.
/// - [errorText] — the rejection to draw under the field; `null` when clean.
/// - [keyboardType] — e.g. [TextInputType.emailAddress].
/// - [enabled] — pass `false` while a write is in flight.
/// - [inputFormatters] — what the field will accept at all (P4b-T10).
/// - [onChanged] — every edit, for a screen whose state is not the controller.
/// - [suffixText] — a unit drawn inside the field, painted in every state.
class LumenInputField extends StatelessWidget {
  const LumenInputField({
    required this.controller,
    required this.label,
    required this.hint,
    super.key,
    this.obscure = false,
    this.errorText,
    this.keyboardType,
    this.enabled = true,
    this.inputFormatters,
    this.onChanged,
    this.suffixText,
  });

  /// The text being edited. Owned (and disposed) by the caller.
  final TextEditingController controller;

  /// The field's accessible name — the same string the screen renders above it.
  final String label;

  /// Placeholder shown while the field is empty.
  ///
  /// Drawn, never announced — it is not part of the field's accessible name.
  /// See the class doc.
  final String hint;

  /// Whether to obscure the entered characters (password entry).
  final bool obscure;

  /// Why this field was rejected, drawn under it in the error colour, or
  /// `null` when there is nothing wrong with it.
  ///
  /// Typically `ValidationFailure.messageFor(<wire field name>)` — which is
  /// already `null` for a field the failure did not name, so a screen can pass
  /// it straight through.
  ///
  /// **It is not announced automatically.** Flutter renders the message as its
  /// own semantics node beside the field, not as part of the field's name, so
  /// a screen reader reaches it by swiping rather than on rejection. Pair it
  /// with a `LumenErrorBanner`, whose live region announces that the submit
  /// failed at the moment it does.
  final String? errorText;

  /// The soft-keyboard type to request.
  final TextInputType? keyboardType;

  /// Whether the field accepts input. `false` greys it out.
  final bool enabled;

  /// What the field will accept at all — refusing a keystroke rather than
  /// correcting the value afterwards.
  ///
  /// Added by P4b-T10 for screen 4's weight, where the backend **rejects**
  /// more than one decimal place instead of rounding it, and rounding it away
  /// client-side would store a number the user did not type.
  final List<TextInputFormatter>? inputFormatters;

  /// Called on every edit.
  ///
  /// A screen whose source of truth is a Riverpod controller rather than this
  /// [TextEditingController] needs the parsed value as it is typed; without
  /// this it would have to add its own listener and remember to remove it.
  final ValueChanged<String>? onChanged;

  /// A unit drawn inside the field, after the value — the mockups' `.fu` span.
  ///
  /// **Not the hint.** A hint disappears the moment the field has content,
  /// including on a prefilled one, so a returning user editing a stored height
  /// would see `165` with nothing saying centimetres. The mockups draw the unit
  /// beside the value in every state, and so does this — but only because of
  /// [InputDecoration.floatingLabelBehavior] below, which is why that line is
  /// not decoration.
  ///
  /// **Material paints a suffix at opacity 0 on an empty, unfocused field.**
  /// `_AffixText` wraps it in `AnimatedOpacity(opacity: labelIsFloating ? 1.0 :
  /// 0.0)` (`input_decorator.dart:1827-1830`) and the suffix is built with
  /// `labelIsFloating: labelShouldWithdraw` (`:2434`), which is `!isEmpty ||
  /// (isFocused && enabled)` (`:1969`). So a unit added here alone would be
  /// invisible in exactly the state a first-time user starts in — laid out,
  /// reserving its strip, and painted at zero. `FloatingLabelBehavior.always`
  /// forces `labelShouldWithdraw` true (`:2076-2078`) and is a no-op for
  /// everything else, because this decoration passes no `labelText`/`label`.
  ///
  /// Pinned by opacity, never by presence: `find.text('cm')` passes against a
  /// zero-opacity widget, and that is how the gap shipped once. See
  /// `test/widgets/lumen_input_field_test.dart`'s `suffixText` group.
  final String? suffixText;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;
    // The design system has no error token of its own (`LumenColors` is the
    // mockups' palette and the mockups draw no error state), so the field
    // borrows the theme's — set explicitly in `lumenTheme`, not a Material
    // default that could drift.
    final errorColor = Theme.of(context).colorScheme.error;

    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );

    final inputStyle = TextStyle(fontSize: 14, color: c.ink);
    final hintStyle = TextStyle(
      color: c.muted.withValues(alpha: 0.6),
      fontSize: 14,
      fontWeight: FontWeight.w400,
    );

    return Semantics(
      label: label,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        enabled: enabled,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        style: inputStyle,
        decoration: InputDecoration(
          // A `hint` WIDGET, not `hintText` — see the class doc. The two cannot
          // both be given (`InputDecoration`'s own assert), and the style has
          // to be composed here because `InputDecorator` applies `hintStyle`
          // only to the `Text` it builds itself.
          hint: ExcludeSemantics(
            child: Text(
              hint,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge!.merge(inputStyle).merge(hintStyle),
              textAlign: TextAlign.start,
            ),
          ),
          suffixText: suffixText,
          suffixStyle: TextStyle(fontSize: 10, color: c.muted),
          // Load-bearing for [suffixText] and inert for everything else — see
          // its doc. Without it the unit is painted at opacity 0 until the
          // field is focused or typed into.
          floatingLabelBehavior: FloatingLabelBehavior.always,
          filled: true,
          fillColor: c.input,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: border(c.border),
          enabledBorder: border(c.border),
          focusedBorder: border(c.accent),
          disabledBorder: border(c.border),
          errorText: errorText,
          // Both error borders are spelled out because Material's defaults are
          // NOT this design system's: leaving them unset swaps the 12 px
          // outline every other state draws for the theme's 4 px one the
          // moment a field goes red.
          errorBorder: border(errorColor),
          focusedErrorBorder: border(errorColor),
          errorStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: errorColor,
          ),
        ),
      ),
    );
  }
}
