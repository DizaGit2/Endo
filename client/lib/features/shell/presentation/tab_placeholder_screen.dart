import 'package:flutter/material.dart';
import 'package:lumen/core/theme/lumen_tokens.dart';

/// The destination a bottom-nav tab shows while its feature does not exist yet.
///
/// One screen, five call sites: the route table passes the [heading] for the
/// tab it is standing in for. Sharing one widget (rather than five near-copies)
/// is what keeps the wording identical across tabs — the only thing that varies
/// is the subject of the sentence, because "Hormones **aren't**" and "More
/// **isn't**" cannot be composed from a feature name without inventing a
/// grammar engine.
///
/// **Why it exists at all (ruling R-10).** The five-tab nav is a design
/// constant of Lumen (CLAUDE.md), and screens 8/10/11 mount inside it, so the
/// shell has to ship before those screens do. That leaves tabs whose feature is
/// not built. Hiding them would misrepresent the app's shape and force a nav
/// rebuild later; leaving a tab that navigates nowhere would be a promise the
/// app cannot keep. So the tab renders and its destination states the absence
/// plainly:
///
/// - **no date and no version** — nothing here can be missed or broken;
/// - **no "coming soon"** — that is a promise, and this screen makes none;
/// - **no progress indicator** — there is nothing in flight to report;
/// - **no button** — an affordance pointing at nothing is the exact thing R-10
///   forbids. `tab_placeholder_screen_semantics_test.dart` walks the semantics
///   tree and fails if any node is flagged as a button.
///
/// A later task replaces the tab's `builder:` in [lumenRoutes] with the real
/// screen; nothing else changes, and this screen simply loses a call site.
class TabPlaceholderScreen extends StatelessWidget {
  const TabPlaceholderScreen({required this.heading, super.key});

  /// The full first line, e.g. `Hormones aren't here yet`.
  final String heading;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<LumenColors>()!;

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // header: true — the heading IS the message on this screen, so a
              // screen-reader user should be able to jump straight to it
              // instead of swiping through the chrome.
              Semantics(
                header: true,
                child: Text(
                  heading,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This part of Lumen arrives in a later release.',
                style: TextStyle(fontSize: 14, height: 1.5, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
