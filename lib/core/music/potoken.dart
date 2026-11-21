/// YouTube PoToken seam. No stable public mint endpoint exists, so this reports
/// unavailable rather than pretending a YouTube source works.
class YouTubePoToken {
  const YouTubePoToken._();

  static bool get isAvailable => false;

  static Future<String?> mint({required String videoId}) async => null;
}
