import 'package:flutter/material.dart';
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
/// client and validation is server-side (see `error_mapper.dart`'s
/// `ValidationFailure.fields`). A screen that needs per-field errors should
/// render them beside the field rather than reaching for Flutter's validator
/// machinery halfway.
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
/// node (name first, placeholder after: `"Name\nMaya"`). Do not "improve" it to
/// `Semantics(label:, textField: true)` — that makes the annotation a semantics
/// boundary and produces TWO nodes, an empty text-field container wrapping the
/// real field, which still announces the hint.
///
/// Props:
/// - [controller] — the caller owns it, and must dispose it.
/// - [label] — the field's accessible name; pass the same string the screen
///   renders above the field.
/// - [hint] — placeholder text; there is no floating label by design (the
///   design system puts the label above the field, see `_FieldLabel`).
/// - [obscure] — password entry.
/// - [keyboardType] — e.g. [TextInputType.emailAddress].
/// - [enabled] — pass `false` while a write is in flight.
class LumenInputField extends StatelessWidget {
  const LumenInputField({
    required this.controller,
    required this.label,
    required this.hint,
    super.key,
    this.obscure = false,
    this.keyboardType,
    this.enabled = true,
  });

  /// The text being edited. Owned (and disposed) by the caller.
  final TextEditingController controller;

  /// The field's accessible name — the same string the screen renders above it.
  final String label;

  /// Placeholder shown while the field is empty.
  final String hint;

  /// Whether to obscure the entered characters (password entry).
  final bool obscure;

  /// The soft-keyboard type to request.
  final TextInputType? keyboardType;

  /// Whether the field accepts input. `false` greys it out.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );

    return Semantics(
      label: label,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        enabled: enabled,
        style: TextStyle(fontSize: 14, color: c.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: c.muted.withValues(alpha: 0.6),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
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
        ),
      ),
    );
  }
}
