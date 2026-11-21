import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/net/dns_wire.dart';

Uint8List _response({bool truncated = false, bool answer = true}) {
  final b = BytesBuilder();
  void u16(int v) {
    b.add([(v >> 8) & 0xFF, v & 0xFF]);
  }

  void u32(int v) {
    b.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  }

  u16(0x1234);
  u16(0x8180 | (truncated ? 0x0200 : 0));
  u16(1);
  u16(answer ? 1 : 0);
  u16(0);
  u16(0);
  b.add([1, 0x78, 4, 0x74, 0x65, 0x73, 0x74, 0]);
  u16(1);
  u16(1);
  if (answer) {
    b.add([0xC0, 0x0C]);
    u16(1);
    u16(1);
    u32(60);
    u16(4);
    b.add([1, 2, 3, 4]);
  }
  return b.toBytes();
}

void main() {
  test('query encodes the name as labels', () {
    final bytes = DnsWire.query('x.test', 1);
    expect(bytes.length, greaterThan(12));
    expect(bytes[0], 0, reason: 'DoH queries need no transaction id');
    expect(bytes[2], 0x01, reason: 'recursion desired');
    expect(bytes[12], 1, reason: 'first label length');
    expect(bytes[13], 0x78);
  });

  test('queryUrlSafe drops the padding', () {
    expect(DnsWire.queryUrlSafe('x.test', 1), isNot(contains('=')));
  });

  test('reads an A answer', () {
    final addrs = DnsWire.parseAnswers(_response());
    expect(addrs, hasLength(1));
    expect(addrs.single.address, '1.2.3.4');
  });

  test('an empty answer is an empty list, not an error', () {
    expect(DnsWire.parseAnswers(_response(answer: false)), isEmpty);
  });

  test('detects the truncation bit', () {
    expect(DnsWire.isTruncated(_response(truncated: true)), isTrue);
    expect(DnsWire.isTruncated(_response()), isFalse);
  });
}
