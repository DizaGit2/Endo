import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'core/cache/hive_boot.dart';
import 'core/formatters/lumen_formats.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Warms intl's locale data (all locales — `initializeDateFormatting` ignores
  // its locale argument) before the first frame, so the ~1 MB symbol-table
  // build happens during startup rather than inside the first `build` that
  // renders a date.
  //
  // Through LumenFormats rather than `initializeDateFormatting` directly, so
  // there is ONE entry point and one latch: calling intl's function here would
  // leave `LumenFormats._localeDataLoaded` false, and the two mechanisms would
  // be unaware of each other. Not a prerequisite either way — every date/time
  // formatter calls this itself.
  LumenFormats.ensureLocaleData();

  // Online-only encrypted cache: init Hive at the Flutter default path, open the
  // encrypted box, and expose it via a root ProviderScope override of
  // cacheStoreProvider before any /me read.
  await Hive.initFlutter();
  final store = await initHive();

  runApp(
    ProviderScope(
      overrides: [cacheStoreProvider.overrideWithValue(store)],
      child: const LumenApp(),
    ),
  );
}
