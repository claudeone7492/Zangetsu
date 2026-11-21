import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/net/dns_providers.dart';

void main() {
  setUp(DnsProviders.resetForTest);
  tearDown(DnsProviders.resetForTest);

  test('a bare host becomes an HTTPS endpoint with /dns-query', () {
    expect(
      DnsProviders.customEndpoint('1.1.1.1')?.url,
      'https://1.1.1.1/dns-query',
    );
    expect(
      DnsProviders.customEndpoint('dns.example.com')?.url,
      'https://dns.example.com/dns-query',
    );
  });

  test('pasted query strings and fragments are stripped', () {
    expect(
      DnsProviders.customEndpoint(
        'https://dns.example.com/resolve?dns=abc#frag',
      )?.url,
      'https://dns.example.com/resolve',
    );
  });

  test('junk is rejected', () {
    expect(DnsProviders.customEndpoint('   '), isNull);
    expect(DnsProviders.customEndpoint('https://'), isNull);
  });

  test('an unknown key falls back to the system resolver', () {
    expect(DnsProviders.byKey('nope').key, DnsProviders.system);
    expect(DnsProviders.byKey(null).key, DnsProviders.system);
  });

  test('active is null for the system resolver', () {
    DnsProviders.resetForTest();
    expect(DnsProviders.active, isNull);
  });

  test('every provider is listed once with a label and a url', () {
    final keys = DnsProviders.all.map((p) => p.key).toList();
    expect(keys.toSet(), hasLength(keys.length));
    for (final provider in DnsProviders.all) {
      expect(provider.label, isNotEmpty);
      final expectsUrl =
          provider.key != DnsProviders.system &&
          provider.key != DnsProviders.custom &&
          provider.plain.isEmpty;
      if (expectsUrl) {
        expect(provider.url, startsWith('https://'), reason: provider.key);
      }
      if (provider.key != DnsProviders.system &&
          provider.key != DnsProviders.custom) {
        expect(
          provider.url.isNotEmpty || provider.plain.isNotEmpty,
          isTrue,
          reason: '${provider.key} has neither a DoH nor a plain address',
        );
      }
    }
  });
}
