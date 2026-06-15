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
}
