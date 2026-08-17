import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';
import 'package:lumen/shared/widgets/lumen_input_field.dart';

import '../support/harness.dart';

/// Declared once at file scope rather than inside the builder: `builder:` runs
/// per brightness, and a controller created there would be built twice and
/// disposed never.
final _controllers = <String, TextEditingController>{
  'Name': TextEditingController(),
  'Email': TextEditingController(text: 'maya@example.com'),
  'Password': TextEditingController(),
  'Clinic': TextEditingController(),
};

/// The field in the three states a screen puts it in — empty, filled and
/// disabled — under the label the design system draws above it.
///
/// `obscureText: true` means the image never shows the strings, so what this
/// pins is the treatment: the input fill, the 12 px outline, the resting border
/// colour, and that a disabled field is visibly the same box rather than a
/// different control.
Widget _form(Brightness brightness) {
  final c = brightness == Brightness.light ? lumenLight : lumenDark;

  Widget field(
    String label,
    String hint, {
    bool enabled = true,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 6),
        LumenInputField(
          controller: _controllers[label]!,
          label: label,
          hint: hint,
          enabled: enabled,
          obscure: obscure,
        ),
      ],
    );
  }

  return ColoredBox(
    color: c.bg,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 44, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          field('Name', 'Maya'),
          const SizedBox(height: 14),
          field('Email', 'you@example.com'),
          const SizedBox(height: 14),
          field('Password', '••••••••', obscure: true),
          const SizedBox(height: 14),
          field('Clinic', 'Not set', enabled: false),
        ],
      ),
    ),
  );
}

void main() {
  goldenTestLightAndDark(
    subject: 'LumenInputField',
    fileName: 'lumen_input_field',
    build: (brightness) =>
        goldenApp(home: _form(brightness), brightness: brightness),
  );
}
