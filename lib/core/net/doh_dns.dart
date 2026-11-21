import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'dns_providers.dart';
import 'dns_wire.dart';

/// The app's resolver, ported from Hikari's `net/DohDns.kt`.
///
/// Order of business for a name, exactly as in Hikari:
///  1. cache (positive, or a remembered refusal),
///  2. the chosen provider (DoH wire query, or plain UDP for a `plain` entry),
///  3. the phone's own resolver,
///  4. the JSON DoH endpoints, reached by IP so they need no DNS.
///
/// A provider that fails at the transport level is skipped for a minute, so a
/// bad address costs one slow lookup instead of every lookup.
class DohDns {
  const DohDns._();

  static const Duration ttl = Duration(minutes: 5);

  /// How long "the provider says this name has no address" is remembered.
  static const Duration negativeTtl = Duration(minutes: 1);

  /// How long a provider that failed at the transport level is skipped.
  static const Duration downFor = Duration(minutes: 1);

  /// How long a plain-DNS server gets to answer one datagram.
  static const Duration plainTimeout = Duration(seconds: 4);

  /// JSON DoH endpoints, reached BY IP so resolving them needs no DNS.
  static const List<String> jsonEndpoints = [
    'https://1.1.1.1/dns-query',
    'https://8.8.8.8/resolve',
  ];

  static final Map<String, _Entry> _cache = <String, _Entry>{};
  static final Map<String, HttpClient> _clients = <String, HttpClient>{};
  static DateTime? _providerDownUntil;
  static String _stamp = '';

  static final RegExp _v4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
  static final RegExp _v6 = RegExp(r'^[0-9a-fA-F:]{2,45}$');

  /// Forget every cached name and client — the setting changed.
  static void invalidate() {
    _cache.clear();
    _clients.clear();
    _providerDownUntil = null;
    _stamp = _stampOf();
  }

  static String _stampOf() =>
      '${DnsProviders.choice}|${DnsProviders.customUrl}|'
      '${DnsProviders.active?.url ?? ''}';

  /// Resolves [hostname] through the chosen provider, falling back as above.
  ///
  /// Throws [SocketException] when nothing can resolve it — the same thing
  /// the platform resolver throws.
  static Future<List<InternetAddress>> lookup(String hostname) async {
    final host = hostname.trim().toLowerCase();
    // IP literals and single-label names (localhost, a LAN host, …) are the
    // platform resolver's business — there is nothing for DoH to add.
    if (host.isEmpty ||
        _v4.hasMatch(host) ||
        _v6.hasMatch(host) ||
        !host.contains('.')) {
      return InternetAddress.lookup(hostname);
    }

    final fresh = _currentProvider();
    final cached = _cache[host];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      if (cached.refused) throw _unknown(hostname);
      return cached.addresses;
    }

    final down = _providerDownUntil;
    final providerReady = down == null || down.isBefore(DateTime.now());
    if (fresh != null && providerReady) {
      List<InternetAddress>? viaProvider;
      try {
        viaProvider = await _providerLookup(fresh, host);
      } catch (_) {
        // Unreachable (not a refusal): stand aside for a minute.
        _providerDownUntil = DateTime.now().add(downFor);
        viaProvider = null;
      }
      if (viaProvider != null) {
        if (viaProvider.isEmpty) {
          _cache[host] = _Entry(const [], DateTime.now().add(negativeTtl), true);
          throw _unknown(hostname);
        }
        _cache[host] = _Entry(viaProvider, DateTime.now().add(ttl), false);
        return viaProvider;
      }
    }

    try {
      final resolved = await InternetAddress.lookup(hostname);
      if (resolved.isNotEmpty) {
        _cache[host] = _Entry(resolved, DateTime.now().add(ttl), false);
        return resolved;
      }
    } on SocketException {
      // fall through to DoH
    }

    final viaJson = await _tryJson(host);
    if (viaJson.isNotEmpty) {
      _cache[host] = _Entry(viaJson, DateTime.now().add(ttl), false);
      return viaJson;
    }
    throw _unknown(hostname);
  }

  static DnsProvider? _currentProvider() {
    final stamp = _stampOf();
    if (stamp != _stamp) {
      _stamp = stamp;
      _cache.clear();
      _clients.clear();
      _providerDownUntil = null;
    }
    return DnsProviders.active;
  }

  static SocketException _unknown(String hostname) => SocketException(
    'Unable to resolve host "$hostname": no address',
    osError: const OSError('no address', 7),
  );

  /// Asks [provider] whether it answers at all, for the Settings "Test" line.
  /// Returns null when it works, else a short reason. Never throws.
  static Future<String?> probe(DnsProvider? provider) async {
    const target = 'example.com';
    if (provider == null) {
      try {
        final found = await InternetAddress.lookup(target);
        return found.isEmpty ? 'The phone returned no address.' : null;
      } catch (e) {
        return "The phone couldn't resolve it (${_cause(e)}).";
      }
    }
    if (!provider.usable) return 'No address given.';
    try {
      final found = await _providerLookup(provider, target);
      return found.isNotEmpty
          ? null
          : '$target came back without an address — the server refused the query.';
    } catch (e) {
      return "Didn't answer — ${_cause(e)}. Check the address.";
    }
  }

  /// A short, human-sized cause for the Settings test line.
  static String _cause(Object e) {
    if (e is SocketException) return "its own hostname wouldn't resolve";
    if (e is TimeoutException) return 'it timed out';
    if (e is HandshakeException) return 'the secure connection failed';
    if (e is HttpException) return 'the network refused the request';
    return e.runtimeType.toString();
  }

  static Future<List<InternetAddress>> _providerLookup(
    DnsProvider provider,
    String host,
  ) => provider.url.isNotEmpty
      ? _dohLookup(provider, host)
      : _plainLookup(provider, host);

  static Future<List<InternetAddress>> _dohLookup(
    DnsProvider provider,
    String host,
  ) async {
    final client = _clientFor(provider);
    final found = <String, InternetAddress>{};
    var answered = false;
    Object? failure;
    for (final type in const [1, 28]) {
      try {
        final body = await _wireQuery(client, provider, host, type);
        answered = true;
        for (final addr in DnsWire.parseAnswers(body)) {
          found[addr.address] = addr;
        }
      } catch (e) {
        failure = e;
      }
    }
    if (!answered) throw failure ?? HttpException('no query went out');
    return found.values.toList();
  }

  static Future<Uint8List> _wireQuery(
    HttpClient client,
    DnsProvider provider,
    String host,
    int type,
  ) async {
    final separator = provider.url.contains('?') ? '&' : '?';
    final uri = Uri.parse(
      '${provider.url}$separator'
      'dns=${DnsWire.queryUrlSafe(host, type)}',
    );
    final request = await client.getUrl(uri).timeout(
      const Duration(seconds: 8),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/dns-message');
    final response = await request.close().timeout(
      const Duration(seconds: 8),
    );
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('provider answered ${response.statusCode}');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    final bytes = builder.toBytes();
    if (bytes.isEmpty) throw HttpException('provider answered with no body');
    return bytes;
  }

  static Future<List<InternetAddress>> _plainLookup(
    DnsProvider provider,
    String host,
  ) async {
    final found = <String, InternetAddress>{};
    var answered = false;
    Object? failure;
    for (final server in provider.plain) {
      var serverAnswered = false;
      for (final type in const [1, 28]) {
        try {
          final body = await _udpQuery(server, host, type);
          if (DnsWire.isTruncated(body) &&
              DnsWire.parseAnswers(body).isEmpty) {
            failure = HttpException('$server truncated the reply');
            continue;
          }
          serverAnswered = true;
          for (final addr in DnsWire.parseAnswers(body)) {
            found[addr.address] = addr;
          }
        } catch (e) {
          failure = e;
        }
      }
      if (serverAnswered) {
        answered = true;
        if (found.isNotEmpty) break;
      }
    }
    if (!answered) throw failure ?? HttpException('no server answered');
    return found.values.toList();
  }

  static Future<Uint8List> _udpQuery(String server, String host, int type) async {
    final query = DnsWire.query(host, type);
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      final address = InternetAddress(server);
      socket.send(query, address, 53);
      final completer = Completer<Uint8List>();
      final subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null || completer.isCompleted) return;
        completer.complete(
          Uint8List.fromList(
            datagram.data.sublist(0, datagram.data.length.clamp(0, 1400)),
          ),
        );
      });
      try {
        return await completer.future.timeout(plainTimeout);
      } finally {
        await subscription.cancel();
      }
    } finally {
      socket.close();
    }
  }

  /// One client per provider, since the addresses it dials through are fixed
  /// at build time.
  static HttpClient _clientFor(DnsProvider provider) =>
      _clients.putIfAbsent('${provider.key}|${provider.url}', () {
        final pinned = <InternetAddress>[];
        for (final ip in provider.bootstrap) {
          final parsed = InternetAddress.tryParse(ip);
          if (parsed != null) pinned.add(parsed);
        }
        final endpointHost = Uri.tryParse(provider.url)?.host;
        return _client((uri) async {
          if (pinned.isNotEmpty &&
              endpointHost != null &&
              uri.host.toLowerCase() == endpointHost.toLowerCase()) {
            return pinned;
          }
          if (_v4.hasMatch(uri.host) || _v6.hasMatch(uri.host)) {
            return [InternetAddress(uri.host)];
          }
          final viaSystem = await _systemOrJson(uri.host);
          if (viaSystem.isNotEmpty) return viaSystem;
          throw _unknown(uri.host);
        });
      });

  /// The phone first, then the endpoints reachable with no DNS at all.
  static Future<List<InternetAddress>> _systemOrJson(String host) async {
    try {
      final viaSystem = await InternetAddress.lookup(host);
      if (viaSystem.isNotEmpty) return viaSystem;
    } on SocketException {
      // fall through
    }
    return _tryJson(host);
  }

  static Future<List<InternetAddress>> _tryJson(String host) async {
    final name = Uri.encodeQueryComponent(host);
    for (final base in jsonEndpoints) {
      final found = <String, InternetAddress>{};
      for (final type in const ['A', 'AAAA']) {
        for (final addr in await _jsonQuery('$base?name=$name&type=$type')) {
          found[addr.address] = addr;
        }
      }
      if (found.isNotEmpty) return found.values.toList();
    }
    return const [];
  }

  static Future<List<InternetAddress>> _jsonQuery(String url) async {
    final client = _bareClient();
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(
        const Duration(seconds: 8),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return const [];
      }
      final body = await response.transform(utf8.decoder).join();
      return _parseJson(body);
    } catch (_) {
      return const [];
    }
  }

  static List<InternetAddress> _parseJson(String body) {
    final out = <InternetAddress>[];
    final Object? root;
    try {
      root = jsonDecode(body);
    } catch (_) {
      return out;
    }
    if (root is! Map) return out;
    if ((root['Status'] as num?)?.toInt() != 0) return out;
    final answers = root['Answer'];
    if (answers is! List) return out;
    for (final answer in answers) {
      if (answer is! Map) continue;
      final type = (answer['type'] as num?)?.toInt() ?? -1;
      if (type != 1 && type != 28) continue;
      final data = (answer['data'] as String? ?? '').trim();
      if (!(_v4.hasMatch(data) || _v6.hasMatch(data))) continue;
      final parsed = InternetAddress.tryParse(data);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  /// A bare client (no proxy, no interception) so a DoH request can never
  /// recurse back into this resolver.
  static HttpClient _bareClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 5)
    ..findProxy = ((_) => 'DIRECT');

  /// A client whose connections go to the addresses [resolve] returns, while
  /// TLS still validates the name the URI asked for.
  static HttpClient _client(
    Future<List<InternetAddress>> Function(Uri) resolve,
  ) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..idleTimeout = const Duration(seconds: 10)
      ..findProxy = ((_) => 'DIRECT');
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final addresses = await resolve(
        proxyHost == null ? uri : Uri(host: proxyHost),
      );
      if (addresses.isEmpty) throw _unknown(uri.host);
      final port = proxyPort ?? uri.port;
      Object? lastError;
      for (final address in addresses) {
        try {
          final socket = await Socket.connect(
            address,
            port,
            timeout: const Duration(seconds: 5),
          );
          if (uri.scheme == 'https' && proxyHost == null) {
            final secure = await SecureSocket.secure(
              socket,
              host: uri.host,
              supportedProtocols: const ['http/1.1'],
            );
            return ConnectionTask.fromSocket(Future<Socket>.value(secure), () {});
          }
          return ConnectionTask.fromSocket(Future<Socket>.value(socket), () {});
        } catch (e) {
          lastError = e;
        }
      }
      throw lastError ?? _unknown(uri.host);
    };
    return client;
  }

  /// An [HttpClient] for the app's own traffic, or null when the phone's
  /// resolver is in charge (nothing to change).
  static HttpClient? appHttpClient() {
    final provider = _currentProvider();
    if (provider == null) return null;
    return _client((uri) async {
      final found = await lookup(uri.host);
      return found;
    });
  }

  /// Points [dio] at the chosen provider. No-op while the setting is
  /// "Automatic", so the default path is byte-for-byte what it was.
  static void applyTo(Dio dio) {
    final client = appHttpClient();
    if (client == null) return;
    dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => client);
  }
}

class _Entry {
  _Entry(this.addresses, this.expiresAt, this.refused);

  final List<InternetAddress> addresses;
  final DateTime expiresAt;
  final bool refused;
}
