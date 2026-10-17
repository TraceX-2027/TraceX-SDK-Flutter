/// Rate limiter that prevents SDK flood by capping crash telemetry to at most 10 crashes per minute.
class CrashRateLimiter {
  /// Default constructor for [CrashRateLimiter].
  CrashRateLimiter();

  final List<DateTime> _timestamps = [];
  final int _maxCrashes = 10;
  final Duration _window = const Duration(minutes: 1);

  /// Checks if another crash can be transmitted under the current rate limit window.
  bool allow() {
    final now = DateTime.now();

    while (_timestamps.isNotEmpty &&
        now.difference(_timestamps.first) >= _window) {
      _timestamps.removeAt(0);
    }

    if (_timestamps.length >= _maxCrashes) {
      return false;
    }

    _timestamps.add(now);

    return true;
  }
}
