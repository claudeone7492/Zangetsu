import 'package:flutter/services.dart';

/// Exports a finished download to the public Downloads folder.
class MediaExport {
  const MediaExport._();

  static const MethodChannel _channel = MethodChannel('zangetsu/media_export');

  /// Returns the public path, or null when the platform has no handler.
  static Future<String?> save({
    required String path,
    required String displayName,
    required String mime,
  }) async {
    try {
      return await _channel.invokeMethod<String>('save', {
        'path': path,
        'name': displayName,
        'mime': mime,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
