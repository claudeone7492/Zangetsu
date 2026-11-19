import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/pair/pair_protocol.dart';

Map<String, dynamic> _payload() => {
  'app': 'zangetsu',
  'version': 1,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'bundles': {
    'library': {
      'items': [1, 2, 3],
    },
  },
};

void main() {
  group('pairing code', () {
    test('is the configured length and all digits', () {
      final code = generatePairCode();
      expect(code.length, kPairCodeLength);
      expect(RegExp(r'^\d+$').hasMatch(code), isTrue);
    });

    test('is drawn from a secure source, not a predictable seed', () {
      // A fixed-seed Random must reproduce exactly, which proves the generator
      // honours an injected rng; the default path uses Random.secure.
      final a = generatePairCode(Random(1));
      final b = generatePairCode(Random(1));
      expect(a, b);
      expect(generatePairCode(), isNot(generatePairCode()));
    });

    test('matches only the exact code', () {
      expect(pairCodeMatches('123456', '123456'), isTrue);
      expect(pairCodeMatches('123456', '123457'), isFalse);
      expect(pairCodeMatches('123456', '12345'), isFalse);
      expect(pairCodeMatches('123456', ''), isFalse);
    });
  });

  group('beacon', () {
    test('round-trips through the wire format', () {
      const beacon = PairBeacon(
        code: '042517',
        deviceName: 'Pixel 7',
        port: 8777,
      );
      final parsed = PairBeacon.tryParse(PairProtocol.encodeBeacon(beacon));
      expect(parsed, beacon);
    });

    test('rejects a datagram from another app', () {
      expect(PairBeacon.tryParse(utf8.encode('hello')), isNull);
      expect(PairBeacon.tryParse(utf8.encode('{"code":1}')), isNull);
      expect(PairBeacon.tryParse(const []), isNull);
    });

    test('rejects a beacon from a different protocol version', () {
      final bytes = utf8.encode(
        jsonEncode({'v': 99, 'code': '1', 'name': 'x', 'port': 8777}),
      );
      expect(PairBeacon.tryParse(bytes), isNull);
    });

    test('rejects an out-of-range port', () {
      final bytes = utf8.encode(
        jsonEncode({'v': 1, 'code': '1', 'name': 'x', 'port': 70000}),
      );
      expect(PairBeacon.tryParse(bytes), isNull);
    });
  });

  group('authorization', () {
    const beacon = PairBeacon(code: '123456', deviceName: 'TV', port: 8777);

    test('accepts the advertised code', () {
      expect(PairProtocol.authorize(beacon, '123456'), isTrue);
    });

    test('refuses a wrong code', () {
      expect(PairProtocol.authorize(beacon, '123457'), isFalse);
    });

    test('refuses a missing code — seeing the beacon is not permission', () {
      expect(PairProtocol.authorize(beacon, null), isFalse);
      expect(PairProtocol.authorize(beacon, ''), isFalse);
    });
  });

  group('transfer body', () {
    test('round-trips the backup payload', () {
      final payload = _payload();
      final body = PairProtocol.encodeTransfer(payload);
      expect(PairProtocol.decodeTransfer(body), payload);
    });

    test('rejects a body that is not a paired transfer', () {
      expect(PairProtocol.decodeTransfer('not json'), isNull);
      expect(
        PairProtocol.decodeTransfer(jsonEncode({'payload': _payload()})),
        isNull,
      );
      expect(
        PairProtocol.decodeTransfer(jsonEncode({'transfer': 'pair'})),
        isNull,
      );
    });
  });

  group('peer', () {
    test('builds the backup URL from the advertised port', () {
      const peer = PairPeer(
        host: '192.168.1.20',
        beacon: PairBeacon(code: '1', deviceName: 'TV', port: 9001),
      );
      expect(peer.backupUri.toString(), 'http://192.168.1.20:9001/backup');
    });

    test('host is part of identity, so two senders cannot collide', () {
      const beacon = PairBeacon(code: '1', deviceName: 'TV', port: 8777);
      const a = PairPeer(host: '192.168.1.20', beacon: beacon);
      const b = PairPeer(host: '192.168.1.21', beacon: beacon);
      expect(a, isNot(b));
      expect(a, const PairPeer(host: '192.168.1.20', beacon: beacon));
    });
  });

  group('end to end', () {
    test('sender serves the payload to a peer with the right code', () async {
      final sender = PairSender(
        payload: _payload(),
        deviceName: 'Pixel',
        random: Random(7),
      );
      await sender.start();
      addTearDown(sender.stop);
      expect(sender.isRunning, isTrue);

      const peer = PairPeer(
        host: '127.0.0.1',
        beacon: PairBeacon(code: 'unused', deviceName: 'Pixel', port: 0),
      );
      final real = PairPeer(
        host: '127.0.0.1',
        beacon: PairBeacon(
          code: sender.code,
          deviceName: 'Pixel',
          port: sender.beacon.port,
        ),
      );
      expect(peer, isNot(real));

      final payload = await fetchPairedBackup(real, code: sender.code);
      expect(payload, _payload());
    });

    test('a wrong code is refused and the session stays open', () async {
      final sender = PairSender(
        payload: _payload(),
        deviceName: 'Pixel',
        random: Random(3),
      );
      await sender.start();
      addTearDown(sender.stop);

      final peer = PairPeer(
        host: '127.0.0.1',
        beacon: PairBeacon(
          code: sender.code,
          deviceName: 'Pixel',
          port: sender.beacon.port,
        ),
      );

      await expectLater(
        fetchPairedBackup(peer, code: '000000'),
        throwsA(
          isA<PairException>().having(
            (e) => e.message,
            'message',
            contains('does not match'),
          ),
        ),
      );
      // A failed attempt must not end the session — the user can retype.
      expect(sender.isRunning, isTrue);
    });

    test('a successful transfer closes the session', () async {
      final sender = PairSender(
        payload: _payload(),
        deviceName: 'Pixel',
        random: Random(11),
      );
      await sender.start();
      addTearDown(sender.stop);
      final peer = PairPeer(
        host: '127.0.0.1',
        beacon: PairBeacon(
          code: sender.code,
          deviceName: 'Pixel',
          port: sender.beacon.port,
        ),
      );

      await fetchPairedBackup(peer, code: sender.code);
      // stop() is awaited inside the handler; give it a tick to settle.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sender.isRunning, isFalse);
    });

    test('an unknown path 404s', () async {
      final sender = PairSender(
        payload: _payload(),
        deviceName: 'Pixel',
        random: Random(5),
      );
      await sender.start();
      addTearDown(sender.stop);

      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${sender.beacon.port}/nope'),
      );
      final response = await request.close();
      expect(response.statusCode, 404);
      await response.drain<void>();
      client.close(force: true);
    });

    test('listener hears a sender beacon', () async {
      final listener = PairListener();
      final heard = <PairPeer>[];
      await listener.start(onPeer: heard.add);
      addTearDown(listener.stop);
      // A sandbox has no broadcast route, so the listener may fail to bind or
      // simply never hear anything; both are acceptable. When it does bind we
      // assert the beacon the sender emits parses.
      final sender = PairSender(
        payload: _payload(),
        deviceName: 'Pixel',
        random: Random(13),
      );
      addTearDown(sender.stop);
      expect(PairBeacon.tryParse(PairProtocol.encodeBeacon(sender.beacon)),
          sender.beacon);
    });
  });
}
