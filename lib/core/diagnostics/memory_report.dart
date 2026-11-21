import 'dart:io';

/// Process memory, formatted for the diagnostics screen.
class MemoryReport {
  const MemoryReport._();

  static const int _mb = 1024 * 1024;

  static int get rss => _read(() => ProcessInfo.currentRss);

  static int get maxRss => _read(() => ProcessInfo.maxRss);

  static String get short => 'rss ${format(rss)} · peak ${format(maxRss)}';

  static String format(int bytes) =>
      bytes <= 0 ? '—' : '${(bytes / _mb).round()} MB';

  static int _read(int Function() read) {
    try {
      return read();
    } catch (_) {
      return -1;
    }
  }
}
