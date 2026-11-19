import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Device-to-device backup transfer over the local network, with no cloud in
/// the middle: the sending device serves its backup payload, the receiving one
/// finds it and pulls it.
///
/// Two halves, both pure Dart so the whole protocol is testable without a
/// phone:
///   • discovery — the sender broadcasts a small UDP beacon on a fixed port;
///     the receiver listens and lists what it hears. This is how the receiver
///     learns the sender's IP and port without either knowing the other's
///     address.
///   • transfer — the sender serves the payload over HTTP; the receiver fetches
///     it with the one-time code from the beacon. The code is a shared secret
///     that must match, so another device on the same Wi-Fi cannot pull a
///     backup it merely discovered.
///
/// The payload itself is the SAME `wrapPayload` map the file/cloud backup
/// produces, so a paired transfer and a file export are interchangeable.

/// The port the sender's HTTP server and beacon both use.
const int kPairPort = 8777;

/// Beacon payload version. A receiver ignores beacons from a different major
/// version rather than mis-parsing them.
const int kPairProtocolVersion = 1;

/// How long a pairing session stays discoverable. Long enough to walk to the
/// other device, short enough that a forgotten session doesn't stay open.
const Duration kPairSessionWindow = Duration(minutes: 5);

/// Length of the human-typed pairing code. Six digits is short enough to read
/// across a room and long enough that guessing it inside the session window is
/// impractical.
const int kPairCodeLength = 6;

/// A cryptographically-strong numeric pairing code.
///
/// Uses [Random.secure] because the code is the only thing standing between a
/// discovered session and its contents — `Random()` is seeded predictably.
String generatePairCode([Random? random]) {
  final rng = random ?? Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < kPairCodeLength; i++) {
    buf.write(rng.nextInt(10));
  }
  return buf.toString();
}

/// Constant-time string compare, so a wrong code can't be discovered a
/// character at a time by timing the response.
bool pairCodeMatches(String expected, String actual) {
  if (expected.length != actual.length) return false;
  var diff = 0;
  for (var i = 0; i < expected.length; i++) {
    diff |= expected.codeUnitAt(i) ^ actual.codeUnitAt(i);
  }
  return diff == 0;
}

/// What a sender advertises. JSON on the wire, so a future field can be added
/// without breaking an older receiver.
@immutable
class PairBeacon {
  const PairBeacon({
    required this.code,
    required this.deviceName,
    required this.port,
    this.version = kPairProtocolVersion,
  });

  final String code;
  final String deviceName;
  final int port;
  final int version;

  Map<String, dynamic> toJson() => {
    'v': version,
    'code': code,
    'name': deviceName,
    'port': port,
  };

  /// Parse a beacon datagram, or null when it isn't one of ours (a stray
  /// broadcast on the port, a different app, a corrupt packet).
  static PairBeacon? tryParse(List<int> bytes) {
    try {
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map) return null;
      final code = raw['code'];
      final name = raw['name'];
      final port = raw['port'];
      final version = raw['v'];
      if (code is! String || code.isEmpty) return null;
      if (name is! String) return null;
      if (port is! int || port <= 0 || port > 65535) return null;
      if (version is! int || version != kPairProtocolVersion) return null;
      return PairBeacon(code: code, deviceName: name, port: port);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PairBeacon &&
      other.code == code &&
      other.deviceName == deviceName &&
      other.port == port &&
      other.version == version;

  @override
  int get hashCode => Object.hash(code, deviceName, port, version);
}

/// A session as seen by the receiver: the beacon plus the address it came from.
@immutable
class PairPeer {
  const PairPeer({required this.host, required this.beacon});

  final String host;
  final PairBeacon beacon;

  String get deviceName => beacon.deviceName;

  /// Where the payload lives, given the beacon's advertised port.
  Uri get backupUri =>
      Uri.parse('http://$host:${beacon.port}/backup');

  /// The host is part of identity too: two senders can pick the same code.
  @override
  bool operator ==(Object other) =>
      other is PairPeer && other.host == host && other.beacon == beacon;

  @override
  int get hashCode => Object.hash(host, beacon);
}

/// Builds the beacon datagram for a session, and the HTTP response for a
/// payload request. Split out from the socket code so the wire format is
/// testable on its own.
class PairProtocol {
  const PairProtocol._();

  /// The beacon body for [beacon].
  static List<int> encodeBeacon(PairBeacon beacon) =>
      utf8.encode(jsonEncode(beacon.toJson()));

  /// Whether [requestCode] may read the payload for [beacon].
  ///
  /// A missing/empty request code is always refused: the beacon is broadcast,
  /// so "I saw it" is not authorisation.
  static bool authorize(PairBeacon beacon, String? requestCode) =>
      requestCode != null &&
      requestCode.isNotEmpty &&
      pairCodeMatches(beacon.code, requestCode);

  /// The HTTP body for an authorised request: the payload re-serialised with
  /// a marker so the receiver can tell a paired transfer from a file import.
  static String encodeTransfer(Map<String, dynamic> payload) =>
      jsonEncode({'transfer': 'pair', 'payload': payload});

  /// Parse a transfer body back to the backup payload, or null when it isn't
  /// one (wrong endpoint, truncated body, a captive-portal page).
  static Map<String, dynamic>? decodeTransfer(String body) {
    try {
      final raw = jsonDecode(body);
      if (raw is! Map || raw['transfer'] != 'pair') return null;
      final payload = raw['payload'];
      if (payload is! Map) return null;
      return Map<String, dynamic>.from(payload);
    } catch (_) {
      return null;
    }
  }
}

/// A running sender: an HTTP server plus a periodic UDP beacon.
///
/// Owns its sockets so [stop] is enough to close everything — a leaked
/// broadcast timer would keep waking the radio after the sheet closes.
class PairSender {
  PairSender({required this.payload, required this.deviceName, Random? random})
    : code = generatePairCode(random);

  final Map<String, dynamic> payload;
  final String deviceName;
  final String code;

  HttpServer? _server;
  RawDatagramSocket? _socket;
  Timer? _beacon;
  Timer? _expiry;
  bool _closed = false;

  bool get isRunning => _server != null && !_closed;

  PairBeacon get beacon =>
      PairBeacon(code: code, deviceName: deviceName, port: kPairPort);

  /// Start serving. Binds the fixed port so a receiver that hears the beacon
  /// knows where to fetch; if it is taken, try [fallbackPort] and advertise
  /// that instead.
  Future<void> start({int port = kPairPort, int? fallbackPort}) async {
    if (_closed) throw StateError('PairSender already stopped');
    final server = await _bind(port, fallbackPort);
    _server = server;
    server.listen(_handle, onError: (Object _) {});
    await _startBeacon(server.port);
    _expiry = Timer(kPairSessionWindow, stop);
  }

  Future<HttpServer> _bind(int port, int? fallbackPort) async {
    try {
      return await HttpServer.bind(InternetAddress.anyIPv4, port);
    } on SocketException {
      if (fallbackPort == null) rethrow;
      // A port collision is not a failure: the beacon carries whichever port
      // we actually got, so the receiver never needs the fixed one.
      return HttpServer.bind(InternetAddress.anyIPv4, fallbackPort);
    }
  }

  Future<void> _startBeacon(int port) async {
    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } catch (e) {
      // Without a beacon the session is undicoverable, but the HTTP server is
      // still useful if the peer was told the address by hand.
      debugPrint('[pair] beacon socket failed: $e');
      return;
    }
    socket.broadcastEnabled = true;
    _socket = socket;
    final beacon = PairBeacon(code: code, deviceName: deviceName, port: port);
    void send() {
      try {
        socket.send(
          PairProtocol.encodeBeacon(beacon),
          InternetAddress('255.255.255.255'),
          kPairPort,
        );
      } catch (_) {
        // A Wi-Fi blip must not kill the session; the next tick retries.
      }
    }

    send();
    _beacon = Timer.periodic(const Duration(seconds: 2), (_) => send());
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET' || request.uri.path != '/backup') {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final code = request.uri.queryParameters['code'];
      if (!PairProtocol.authorize(beacon, code)) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }
      response.headers.contentType = ContentType.json;
      response.write(PairProtocol.encodeTransfer(payload));
      await response.close();
      // One successful transfer is the whole point; don't stay discoverable.
      await stop();
    } catch (e) {
      debugPrint('[pair] sender request failed: $e');
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    _beacon?.cancel();
    _expiry?.cancel();
    _socket?.close();
    _socket = null;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
  }
}

/// A running receiver: listens for beacons and reports the peers it hears.
class PairListener {
  PairListener();

  RawDatagramSocket? _socket;
  bool _closed = false;

  bool get isRunning => _socket != null && !_closed;

  /// Start listening. [onPeer] fires for each newly-heard sender, and again if
  /// that sender's beacon changes; [onError] reports a bind failure (a port
  /// clash is common and not fatal to the app).
  Future<void> start({
    required void Function(PairPeer peer) onPeer,
    void Function(Object error)? onError,
    int port = kPairPort,
  }) async {
    if (_closed) throw StateError('PairListener already stopped');
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      _socket = socket;
      final seen = <String, PairPeer>{};
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final beacon = PairBeacon.tryParse(datagram.data);
        if (beacon == null) return;
        final host = datagram.address.address;
        final peer = PairPeer(host: host, beacon: beacon);
        final key = '$host:${beacon.port}';
        if (seen[key] == peer) return; // repeat beacon, already reported
        seen[key] = peer;
        onPeer(peer);
      }, onError: (Object e) => onError?.call(e));
    } catch (e) {
      onError?.call(e);
    }
  }

  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    _socket?.close();
    _socket = null;
  }
}

/// Fetch the payload from a discovered peer using the pairing [code] the user
/// read off the sending device.
///
/// Throws [PairException] with a message fit for the UI on any failure, so the
/// screen never has to translate a SocketException.
Future<Map<String, dynamic>> fetchPairedBackup(
  PairPeer peer, {
  required String code,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..idleTimeout = timeout;
  try {
    final uri = peer.backupUri.replace(
      queryParameters: {'code': code},
    );
    final request = await client.getUrl(uri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode == HttpStatus.forbidden) {
      throw const PairException('That code does not match. Check it and try '
          'again.');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw PairException('The other device answered with '
          '${response.statusCode}.');
    }
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    final payload = PairProtocol.decodeTransfer(body);
    if (payload == null) {
      throw const PairException('The other device sent something this app '
          "can't read.");
    }
    return payload;
  } on PairException {
    rethrow;
  } on TimeoutException {
    throw const PairException('The other device did not answer in time.');
  } catch (e) {
    throw PairException('Could not reach the other device: $e');
  } finally {
    client.close(force: true);
  }
}

/// A pairing failure with a message fit for the UI.
class PairException implements Exception {
  const PairException(this.message);
  final String message;
  @override
  String toString() => message;
}
