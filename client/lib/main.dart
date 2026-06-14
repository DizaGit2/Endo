import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

// TODO(P3b): before LumenFormats date/time are first rendered, await
// initializeDateFormatting() (package:intl/date_symbol_data_local.dart) for the
// supported locales at startup (make main async). Not needed in P3a — the
// static screens (1/36/37) do not format dates/times.
void main() => runApp(const ProviderScope(child: LumenApp()));
