import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/diagnostics/memory_report.dart';

void main() {
  test('formats bytes and hides an unavailable reading', () {
    expect(MemoryReport.format(-1), '—');
    expect(MemoryReport.format(0), '—');
    expect(MemoryReport.format(2 * 1024 * 1024), '2 MB');
  });

  test('short names the process readings', () {
    expect(MemoryReport.short, contains('rss'));
    expect(MemoryReport.short, contains('peak'));
  });
}
