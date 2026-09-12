class CrashRateLimiter {
  final int maxCrashes;
  final Duration window;

  final List<DateTime> _timestamps = [];

  CrashRateLimiter({
    this.maxCrashes = 10,
    this.window = const Duration(minutes: 1),
  });

  bool allow() {
    final now = DateTime.now();

    _timestamps.removeWhere((time) => now.difference(time) >= window);

    if (_timestamps.length >= maxCrashes) {
      return false;
    }

    _timestamps.add(now);

    return true;
  }
}
