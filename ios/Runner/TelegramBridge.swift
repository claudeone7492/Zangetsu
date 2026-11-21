import Flutter

/// Native Telegram streaming seam.
///
/// Public channels are served by the Dart web preview; this bridge is the
/// place a TDLib client plugs in for private channels and full history. Until
/// one is linked, `available` is false and Dart falls back to the preview.
final class TelegramBridge {
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "available":
      result(false)
    case "resolveChannel":
      result(
        FlutterError(
          code: "unavailable",
          message: "Telegram streaming needs the TDLib native library",
          details: nil
        )
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
