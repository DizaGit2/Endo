// Unit tests for OidcConfig.serviceConfiguration.
//
// endSession must pass AppAuth EXPLICIT endpoints rather than an issuer, so the
// native layer does not fetch the discovery document — that fetch ignores
// allowInsecureConnections for endSession on Android and crashes the app over
// cleartext ("only https connections are permitted"). These tests pin the
// derived Keycloak endpoint URLs (pure logic; no platform channels).

import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/core/auth/oidc_client.dart';

void main() {
  group('OidcConfig.serviceConfiguration', () {
    test('derives the Keycloak endpoints from the issuer', () {
      const config = OidcConfig(issuer: 'http://10.0.2.2:8080/realms/lumen');
      final sc = config.serviceConfiguration;

      expect(
        sc.authorizationEndpoint,
        'http://10.0.2.2:8080/realms/lumen/protocol/openid-connect/auth',
      );
      expect(
        sc.tokenEndpoint,
        'http://10.0.2.2:8080/realms/lumen/protocol/openid-connect/token',
      );
      expect(
        sc.endSessionEndpoint,
        'http://10.0.2.2:8080/realms/lumen/protocol/openid-connect/logout',
      );
    });

    test('does not double the slash when the issuer has a trailing slash', () {
      const config =
          OidcConfig(issuer: 'https://auth.example.com/realms/lumen/');
      final sc = config.serviceConfiguration;

      expect(
        sc.endSessionEndpoint,
        'https://auth.example.com/realms/lumen/protocol/openid-connect/logout',
      );
    });
  });

  group('OidcConfig.postLogoutRedirectUrl', () {
    test('defaults to the app redirect scheme so logout returns to the app',
        () {
      const config = OidcConfig();
      expect(config.postLogoutRedirectUrl, 'com.lumen.app:/oauth2redirect');
    });
  });
}
