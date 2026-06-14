import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';
import 'core/cache/hive_boot.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Locale data for LumenFormats date/time (D-05: es-ES primary, en-US second).
  await initializeDateFormatting('es_ES');
  await initializeDateFormatting('en_US');

  // Online-only encrypted cache: init Hive at the Flutter default path, open the
  // encrypted box, and expose it via cacheStoreProvider before any /me read.
  await Hive.initFlutter();
  setCacheStore(await initHive());

  runApp(const ProviderScope(child: LumenApp()));
}
