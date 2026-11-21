import 'dart:convert';

/// Parsing half of the BotGuard / PO token flow.
///
/// A direct port of Hikari's `dub`-adjacent `potoken/PoTokenJs.kt` (itself from
/// NewPipe's `org.schabi.newpipe.util.potoken`), kept pure so the wire formats
/// can be read without a JavaScript runtime in the room.
class BotGuardChallenge {
  const BotGuardChallenge({
    required this.messageId,
    required this.interpreterHash,
    required this.interpreterScript,
    required this.program,
    required this.globalName,
    required this.clientExperimentsStateBlob,
  });

  final String messageId;
  final String interpreterHash;

  /// The VM loader, as a script to be evaluated before [program] runs.
  final String interpreterScript;

  /// The BotGuard program, handed to the VM's `a()` entry point.
  final String program;

  /// Global the VM installs itself under, e.g. `VMx`.
  final String globalName;

  final String clientExperimentsStateBlob;

  Map<String, Object?> toJson() => {
    'messageId': messageId,
    'interpreterHash': interpreterHash,
    'interpreterJavascript': {
      'privateDoNotAccessOrElseSafeScriptWrappedValue': interpreterScript,
    },
    'program': program,
    'globalName': globalName,
    'clientExperimentsStateBlob': clientExperimentsStateBlob,
  };

  /// The JSON the BotGuard glue script expects.
  String get json => jsonEncode(toJson());
}

/// Reads the `Create` endpoint's answer.
///
/// The challenge arrives either as `[challenge]` or as `[ignored, scrambled]`
/// where the second element is the base64 of the challenge with every byte
/// shifted by 97 — hence [descramble].
BotGuardChallenge parseChallengeData(String raw) {
  final scrambled = jsonDecode(raw);
  if (scrambled is! List || scrambled.isEmpty) {
    throw const FormatException('BotGuard challenge is not a list');
  }
  final dynamic inner;
  if (scrambled.length > 1 && scrambled[1] is String) {
    inner = jsonDecode(descramble(scrambled[1] as String));
  } else {
    inner = scrambled[0];
  }
  if (inner is! List) {
    throw const FormatException('BotGuard challenge has no fields');
  }

  String at(int index) {
    if (index >= inner.length) return '';
    final v = inner[index];
    return v is String ? v : '';
  }

  /// Fields 1 and 2 are lists whose first string is the one worth having.
  String firstString(int index) {
    if (index >= inner.length) return '';
    final arr = inner[index];
    if (arr is! List) return '';
    for (final v in arr) {
      if (v is String && v.isNotEmpty) return v;
    }
    return '';
  }

  return BotGuardChallenge(
    messageId: at(0),
    interpreterHash: at(3),
    interpreterScript: firstString(1),
    program: at(4),
    globalName: at(5),
    clientExperimentsStateBlob: at(7),
  );
}

/// Reads the `GenerateIT` endpoint's answer: the integrity token as a
/// `Uint8Array(...)` literal, and how many seconds it stays valid.
({String tokenJs, Duration lifetime}) parseIntegrityTokenData(String raw) {
  final data = jsonDecode(raw);
  if (data is! List || data.length < 2) {
    throw const FormatException('BotGuard integrity token is not a pair');
  }
  final seconds = data[1];
  return (
    tokenJs: newUint8Array(base64ToBytes(data[0] as String)),
    lifetime: Duration(
      seconds: seconds is int ? seconds : int.tryParse('$seconds') ?? 0,
    ),
  );
}

/// A JS `Uint8Array(...)` literal holding [identifier]'s UTF-8 bytes.
String stringToU8(String identifier) =>
    newUint8Array(utf8.encode(identifier));

/// A JS `Uint8Array(...)` literal holding [contents].
String newUint8Array(List<int> contents) =>
    'new Uint8Array([${contents.map((b) => b & 0xFF).join(',')}])';

/// `"97,98,99"` — what a `Uint8Array` prints as — to YouTube's URL-safe base64.
String u8ToBase64(String poToken) {
  final bytes = <int>[
    for (final part in poToken.split(','))
      if (part.trim().isNotEmpty) int.parse(part.trim()) & 0xFF,
  ];
  return base64Encode(bytes).replaceAll('+', '-').replaceAll('/', '_');
}

/// The scrambled challenge back to plain JSON text.
String descramble(String scrambled) {
  final bytes = base64ToBytes(scrambled);
  return utf8.decode([for (final b in bytes) (b + 97) & 0xFF]);
}

/// Base64 with the URL-safe alphabet and `.` padding accepted, which is what
/// both BotGuard and YouTube hand out.
List<int> base64ToBytes(String base64Text) {
  final fixed = base64Text
      .replaceAll('-', '+')
      .replaceAll('_', '/')
      .replaceAll('.', '=');
  return base64Decode(fixed);
}
