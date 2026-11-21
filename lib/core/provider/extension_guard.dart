/// Shared checks for third-party extension calls.
///
/// Hikari wraps extension invocation in a UI guard and a verify guard. Without
/// one, a plugin that returns `javascript:` or `file:` URLs can reach the
/// player, and a throwing plugin takes the whole screen down.
class ExtensionGuard {
  const ExtensionGuard._();

  static const Set<String> allowedSchemes = {'http', 'https'};

  static bool isSafeUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    if (uri.scheme.isEmpty) return false;
    return allowedSchemes.contains(uri.scheme.toLowerCase());
  }

  /// Runs [body], turning a throw into null and reporting it. The caller keeps
  /// its UI; the failure is logged once.
  static Future<T?> guard<T>(
    String label,
    Future<T> Function() body, {
    void Function(String label, Object error, StackTrace stack)? onError,
  }) async {
    try {
      return await body();
    } catch (error, stack) {
      onError?.call(label, error, stack);
      return null;
    }
  }

  /// A manifest must name the extension and carry a reachable http(s) base.
  static String? checkManifest({
    String? name,
    String? version,
    String? baseUrl,
  }) {
    if (name == null || name.trim().isEmpty) return 'missing name';
    if (version == null || version.trim().isEmpty) return 'missing version';
    if (baseUrl == null || !isSafeUrl(baseUrl)) return 'unsafe base url';
    return null;
  }
}
