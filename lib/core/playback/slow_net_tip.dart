/// Shows the "slow connection" tip once per host.
///
/// The stream probe already measures the connection; this decides whether the
/// player should explain the tuning, without repeating itself every episode.
class SlowNetTip {
  const SlowNetTip._();

  static final Set<String> _shown = {};

  static bool shouldShow(String key, {required bool slow}) {
    if (!slow) return false;
    return _shown.add(key);
  }

  static void reset() => _shown.clear();
}
