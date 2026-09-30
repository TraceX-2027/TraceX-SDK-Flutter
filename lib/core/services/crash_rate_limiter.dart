class CrashRateLimiter {
  final List<DateTime> _timestamps = [];
  final int _maxCrashes = 10;
  final Duration _window = Duration(minutes: 1);

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
