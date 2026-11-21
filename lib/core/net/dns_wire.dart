import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// DNS message wire format, ported from Hikari's `net/DnsWire.kt`.
///
/// Only what a resolver needs: build a single-question A/AAAA query, spot a
/// truncated reply, and read the addresses out of the answer section.
class DnsWire {
  const DnsWire._();

  /// Base64url, unpadded, of a `?name&type` query — the `dns=` parameter of a
  /// DoH GET.
  static String queryUrlSafe(String host, int type) =>
      base64Url.encode(query(host, type)).replaceAll('=', '');

  /// A single-question A (1) or AAAA (28) query message.
  static Uint8List query(String host, int type) {
    final out = BytesBuilder(copy: false);

    void u16(int value) {
      out.addByte((value >> 8) & 0xFF);
      out.addByte(value & 0xFF);
    }

    final labels = host
        .trim()
        .replaceFirst(RegExp(r'\.+$'), '')
        .split('.')
        .where((l) => l.isNotEmpty);

    u16(0); // transaction id — a DoH query needs none
    u16(0x0100); // opcode QUERY, recursion desired
    u16(1); // one question
    u16(0); // no answers
    u16(0); // no authority records
    u16(0); // no additional records
    for (final label in labels) {
      final bytes = utf8.encode(label);
      if (bytes.isEmpty || bytes.length > 63) continue;
      out.addByte(bytes.length);
      out.add(bytes);
    }
    out.addByte(0); // root label
    u16(type);
    u16(1); // class IN
    return out.toBytes();
  }

  /// True when the reply's TC bit is set — the server had more to say than
  /// would fit, and the answer section is not to be trusted on its own.
  static bool isTruncated(Uint8List response) =>
      response.length >= 4 && (response[2] & 0x02) != 0;

  static List<InternetAddress> parseAnswers(Uint8List response) {
    if (response.length < 12) return const [];
    final out = <InternetAddress>[];

    int u16(int offset) =>
        ((response[offset] & 0xFF) << 8) | (response[offset + 1] & 0xFF);

    final questions = u16(4);
    final answers = u16(6);
    var offset = 12;
    for (var q = 0; q < questions; q++) {
      offset = _skipName(response, offset);
      if (offset < 0) return out;
      offset += 4; // QTYPE + QCLASS
      if (offset > response.length) return out;
    }
    for (var a = 0; a < answers; a++) {
      offset = _skipName(response, offset);
      if (offset < 0 || offset + 10 > response.length) return out;
      final type = u16(offset);
      final length = u16(offset + 8);
      final rdata = offset + 10;
      if (rdata + length > response.length) return out;
      if ((type == 1 && length == 4) || (type == 28 && length == 16)) {
        final bytes = Uint8List.sublistView(response, rdata, rdata + length);
        out.add(
          InternetAddress.fromRawAddress(
            bytes,
            type: type == 1
                ? InternetAddressType.IPv4
                : InternetAddressType.IPv6,
          ),
        );
      }
      offset = rdata + length;
    }
    return out;
  }

  /// Length-prefixed labels, with the 0xC0 compression pointers answered.
  static int _skipName(Uint8List data, int start) {
    var offset = start;
    while (offset < data.length) {
      final length = data[offset] & 0xFF;
      if (length == 0) return offset + 1;
      if (length & 0xC0 == 0xC0) return offset + 2; // pointer ends the name
      offset += 1 + length;
    }
    return -1;
  }
}
