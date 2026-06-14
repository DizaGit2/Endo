import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumen/api/api.dart';
import 'package:lumen/api/api/lumen_api_api.dart';
import 'package:lumen/core/network/dio_provider.dart';

// ---------------------------------------------------------------------------
// API client providers
// ---------------------------------------------------------------------------

/// Provides the generated [Lumen] client, constructed with the app-wide [Dio]
/// instance so that AuthInterceptor, PII-safe logging, and base URL are
/// inherited from [dioProvider].
final lumenClientProvider = Provider<Lumen>((ref) {
  final dio = ref.watch(dioProvider);
  // Pass an empty interceptors list so the Lumen constructor does NOT add its
  // own OAuthInterceptor/BearerAuthInterceptor chain — those are already wired
  // inside the shared Dio instance by dioProvider.
  return Lumen(dio: dio, interceptors: <Interceptor>[]);
});

/// Exposes [LumenApiApi] (the concrete endpoint class) built from the shared
/// [Lumen] client.
final lumenApiProvider = Provider<LumenApiApi>((ref) {
  return ref.watch(lumenClientProvider).getLumenApiApi();
});
