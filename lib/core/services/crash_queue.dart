import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tracex/domain/entities/crash.dart';
import 'package:tracex/domain/usecases/save_offline_crash.dart';

class CrashQueue {
  final CrashOffline crashOffline;
  final bool offlineBuffer;

  final Queue<Crash> _queue = Queue<Crash>();

  bool _isProcessing = false;
  bool _telemetryPaused = false;
  final int _maxSize = 20;
  final int _maxRetries = 3;
  Timer? _offlineRetryTimer;

  CrashQueue({required this.crashOffline, this.offlineBuffer = true});

  int get length => _queue.length;

  // -----------------------------------------
  // Add Crash
  // -----------------------------------------
  Future<void> add(Crash crash) async {
    if (_telemetryPaused) {
      if (offlineBuffer) await _saveOffline(crash);
      return;
    }

    if (_queue.length >= _maxSize) {
      debugPrint('TraceX: Crash queue is full. Crash dropped.');
      return;
    }

    _queue.addLast(crash);
  }

  // -----------------------------------------
  // Process Queue
  // -----------------------------------------
  Future<void> process(Future<void> Function(Crash crash) sendCrash) async {
    if (_telemetryPaused || _isProcessing) return;

    _isProcessing = true;

    try {
      if (offlineBuffer) {
        await _processOfflineCrashes(sendCrash);
      }

      if (_telemetryPaused) {
        await _flushQueueToOffline();
        return;
      }

      while (_queue.isNotEmpty && !_telemetryPaused) {
        final crash = _queue.removeFirst();
        await _send(crash, sendCrash);

        if (_telemetryPaused) {
          await _flushQueueToOffline();
          break;
        }
      }
    } finally {
      _isProcessing = false;
      if (_queue.isNotEmpty && !_telemetryPaused) {
        unawaited(process(sendCrash));
      }
    }
  }

  // -----------------------------------------
  // Send with Retry & Backoff
  // -----------------------------------------
  Future<bool> _send(
    Crash crash,
    Future<void> Function(Crash crash) sendCrash, {
    bool fromOffline = false,
  }) async {
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        await sendCrash(crash);

        await crashOffline.saveCrash(crash);
        debugPrint("TraceX:Save offline Done! ");

        return true;
      } catch (e) {
        debugPrint('TraceX: Send attempt $attempt/$_maxRetries failed: $e');

        // 401 Unauthorized -> Pause telemetry indefinitely

        if (e is DioException && e.response?.statusCode == 401) {
          _telemetryPaused = true;

          debugPrint('[TraceX] Invalid API Key. Telemetry paused.');

          if (offlineBuffer && !fromOffline) await _saveOffline(crash);

          return false;
        }

        // 429 Rate Limited -> Pause for Retry-After duration
        if (e is DioException && e.response?.statusCode == 429) {
          final retryAfter =
              int.tryParse(e.response?.headers.value('Retry-After') ?? '') ??
              60;

          _telemetryPaused = true;

          debugPrint('[TraceX] Rate limited. Pausing for $retryAfter seconds.');

          if (offlineBuffer && !fromOffline) await _saveOffline(crash);

          unawaited(_resumeAfterRateLimit(retryAfter, sendCrash));

          return false;
        }

        // Non-retryable error (4xx) or Last Attempt
        if (!_isRetryable(e) || attempt == _maxRetries) {
          if (offlineBuffer && !fromOffline) await _saveOffline(crash);
          return false;
        }

        // Exponential backoff delay (1s, 2s, 4s...)
        await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    }
    return false;
  }

  // -----------------------------------------
  // Offline Handlers
  // -----------------------------------------
  Future<void> _processOfflineCrashes(
    Future<void> Function(Crash crash) sendCrash,
  ) async {
    if (_telemetryPaused || !offlineBuffer) return;

    final cachedCrashes = crashOffline.getCachedCrashes();
    for (final crash in cachedCrashes) {
      if (_telemetryPaused) break;
      final success = await _send(crash, sendCrash, fromOffline: true);
      if (success) {
        await crashOffline.deleteCrash(crash);
      }
    }
  }

  Future<void> _flushQueueToOffline() async {
    if (!offlineBuffer) {
      _queue.clear();
      return;
    }
    while (_queue.isNotEmpty) {
      await _saveOffline(_queue.removeFirst());
    }
  }

  Future<void> _saveOffline(Crash crash) async {
    if (!offlineBuffer) return;
    try {
      await crashOffline.saveCrash(crash);
    } catch (e) {
      debugPrint('TraceX: Failed to save crash offline: $e');
    }
  }

  Future<void> _resumeAfterRateLimit(
    int seconds,
    Future<void> Function(Crash crash) sendCrash,
  ) async {
    await Future.delayed(Duration(seconds: seconds));
    _telemetryPaused = false;
    debugPrint('[TraceX] Telemetry resumed.');
    await process(sendCrash);
  }

  void startOfflineRetry(Future<void> Function(Crash crash) sendCrash) {
    if (!offlineBuffer) return;
    _offlineRetryTimer?.cancel();
    _offlineRetryTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!_telemetryPaused && !_isProcessing) {
        await _processOfflineCrashes(sendCrash);
      }
    });
  }

  bool _isRetryable(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code != null && code >= 400 && code <= 499) return false;
    }
    return true;
  }

  void dispose() {
    _offlineRetryTimer?.cancel();
    _offlineRetryTimer = null;
    _queue.clear();
  }
}
