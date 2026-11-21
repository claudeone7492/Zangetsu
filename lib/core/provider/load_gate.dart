import 'dart:async';

/// Thrown when no load slot frees up in time.
class LoadQueueBusy implements Exception {
  const LoadQueueBusy(this.waited);
  final Duration waited;
  @override
  String toString() => 'The plugin loader is busy (no slot after ${waited.inSeconds}s)';
}

/// Caps how many extension archives load at once.
///
/// Hikari's `LoadGate` stops a burst of plugin installs from exhausting the
/// process. The Dart side needs the same cap: a home refresh can ask ten
/// sources to load simultaneously.
class LoadGate {
  LoadGate({this.maxConcurrent = 6, this.slotWait = const Duration(seconds: 45)});

  final int maxConcurrent;
  final Duration slotWait;

  int _active = 0;
  final List<Completer<void>> _waiters = [];

  int get active => _active;

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    try {
      await completer.future.timeout(slotWait);
    } on TimeoutException {
      _waiters.remove(completer);
      throw LoadQueueBusy(slotWait);
    }
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
      return;
    }
    _active--;
  }

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }
}
