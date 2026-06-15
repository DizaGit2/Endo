// Tests for dioProvider.
//
// The online-only / stale-while-revalidate design depends on the network call
// eventually failing with a Dio timeout so cachedRead can fall back to cache.
// Because a pre-built Dio is handed to the generated client, the generator's
// default timeouts are bypassed — so the shared Dio MUST set its own.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/network/dio_provider.dart';

void main() {
  test('shared Dio sets explicit connect and receive timeouts', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dio = container.read(dioProvider);

    expect(dio.options.connectTimeout, isNotNull,
        reason: 'a hung connect must time out, not hang forever');
    expect(dio.options.receiveTimeout, isNotNull,
        reason: 'a server that never responds must time out so SWR can fall '
            'back to cache');
    expect(dio.options.connectTimeout! > Duration.zero, isTrue);
    expect(dio.options.receiveTimeout! > Duration.zero, isTrue);
  });

  test('base URL comes from the LUMEN_API_BASE dart-define (emulator default)',
      () {
    // Same key + default as production: equal with no --dart-define (both the
    // emulator default), and equal under a --dart-define override ONLY if the
    // shared Dio actually reads the key. Run with
    //   flutter test --dart-define=LUMEN_API_BASE=http://host:port
    // to prove the override propagates.
    const expected = String.fromEnvironment(
      'LUMEN_API_BASE',
      defaultValue: 'http://10.0.2.2:8085',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(dioProvider).options.baseUrl, expected);
  });
}
