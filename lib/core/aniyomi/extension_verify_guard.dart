import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

/// Pins an extension's signing certificate and refuses a swap.
///
/// A repo index has no hash to check an APK against, so the trust anchor is
/// the key that signed the copy already installed: the first install records
/// the certificate digest, and every later update must be signed by the same
/// key. That is the property that matters — a repo takeover or a mirrored
/// index cannot hand the app different code under the same package name.
///
/// An unsigned APK, or a platform that cannot report one, is allowed through
/// (the loader rejects what it cannot load anyway); the guard only blocks a
/// *changed* signer.
class ExtensionVerifyGuard {
  ExtensionVerifyGuard({MethodChannel? channel, Box<dynamic>? box})
    : _channel = channel ?? const MethodChannel('zangetsu/aniyomi'),
      _box = box;

  static const String boxName = 'extension_signers';

  final MethodChannel _channel;
  Box<dynamic>? _box;

  Box<dynamic>? get _store {
    if (_box != null) return _box;
    if (!Hive.isBoxOpen(boxName)) return null;
    return _box = Hive.box<dynamic>(boxName);
  }

  /// The certificate digest recorded for [pkg], if any.
  String? pinned(String pkg) => _store?.get(pkg) as String?;

  /// Verifies [apkPath] against the pinned signer for [pkg] and pins it on
  /// first sight. Returns null when the APK may be installed, or the reason
  /// it may not.
  Future<String?> check(String pkg, String apkPath) async {
    if (!File(apkPath).existsSync()) return 'apk missing';
    final String? digest;
    try {
      digest = await _channel.invokeMethod<String>('apkSigner', {
        'apkPath': apkPath,
      });
    } on PlatformException catch (e) {
      debugPrint('[extension-verify] signer read failed for $pkg: ${e.message}');
      return null;
    } on MissingPluginException {
      // Non-Android (tests, desktop): nothing to verify against.
      return null;
    }
    if (digest == null || digest.isEmpty) return null;

    final known = pinned(pkg);
    if (known == null) {
      await _store?.put(pkg, digest);
      return null;
    }
    if (known != digest) {
      return 'signing certificate changed for $pkg';
    }
    return null;
  }
}
