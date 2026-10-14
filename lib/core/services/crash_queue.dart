import 'dart:async';
import 'dart:collection';
import 'dart:math';

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
  bool _isUnauthorized = false;
  final int _maxSize = 20;
  final int _maxRetries = 3;
  Timer? _offlineRetryTimer;

  CrashQueue({required this.crashOffline, this.offlineBuffer = true});

  int get length => _queue.length;

  @visibleForTesting
  bool get isUnauthorized => _isUnauthorized;

  @visibleForTesting
  bool get isTelemetryPaused => _telemetryPaused;

  @visibleForTesting
  bool get isProcessing => _isProcessing;

  // -----------------------------------------
  // Add Crash
  // -----------------------------------------
  Future<void> add(Crash crash) async {
    if (_isUnauthorized) {
      debugPrint('TraceX: API key is unauthorized. Crash discarded.');
      return;
    }

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
    if (_telemetryPaused || _isProcessing || _isUnauthorized) return;

    _isProcessing = true;

    try {
      if (offlineBuffer) {
        await _processOfflineCrashes(sendCrash);
      }

      if (_isUnauthorized) {
        _queue.clear();
        return;
      }

      if (_telemetryPaused) {
        await _flushQueueToOffline();
        return;
      }

      while (_queue.isNotEmpty && !_telemetryPaused && !_isUnauthorized) {
        final crash = _queue.removeFirst();
        await _send(crash, sendCrash);

        if (_isUnauthorized) {
          _queue.clear();
          break;
        }

        if (_telemetryPaused) {
          await _flushQueueToOffline();
          break;
        }
      }
    } finally {
      _isProcessing = false;
      if (_queue.isNotEmpty && !_telemetryPaused && !_isUnauthorized) {
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
        return true;
      } catch (e) {
        debugPrint('TraceX: Send attempt $attempt/$_maxRetries failed: $e');

        // 401 Unauthorized -> Pause telemetry permanently, discard payload and clear queue (Do NOT save offline)
        if (e is DioException && e.response?.statusCode == 401) {
          _isUnauthorized = true;
          _telemetryPaused = true;
          _queue.clear();

          debugPrint(
            '[TraceX] Invalid API Key. Telemetry permanently paused and queue cleared.',
          );
          if (fromOffline) await crashOffline.deleteCrash(crash);
          return false;
        }

        // 429 Rate Limited -> Pause for Retry-After duration and buffer to offline
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

        // Non-retryable client errors (400, 403, 404, etc.) -> Discard immediately (Do NOT save offline)
        if (!_isRetryable(e)) {
          debugPrint('[TraceX] Non-retryable error ($e). Discarding crash.');
          if (fromOffline) await crashOffline.deleteCrash(crash);
          return false;
        }

        // Last attempt failed for retryable errors (5xx / timeouts) -> Save to offline buffer
        if (attempt == _maxRetries) {
          if (offlineBuffer && !fromOffline) await _saveOffline(crash);
          return false;
        }

        // Exponential backoff with randomized jitter (0-500ms) to prevent thundering herd spikes
        final delayMs = (1 << (attempt - 1)) * 1000 + Random().nextInt(500);
        await Future.delayed(Duration(milliseconds: delayMs));
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
    if (_telemetryPaused || _isUnauthorized || !offlineBuffer) return;

    final cachedCrashes = crashOffline.getCachedCrashes();
    for (final crash in cachedCrashes) {
      if (_telemetryPaused || _isUnauthorized) break;
      final success = await _send(crash, sendCrash, fromOffline: true);
      if (success) {
        await crashOffline.deleteCrash(crash);
      }
    }
  }

  Future<void> _flushQueueToOffline() async {
    if (_isUnauthorized || !offlineBuffer) {
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

  bool _isRetryable(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (code != null && code >= 400 && code <= 499) return false;
    }
    return true;
  }

  // داخل lib/core/services/crash_queue.dart

  static const int batchSize = 50;

  Future<void> flushOfflineInBatches(
    Future<void> Function(List<Crash> batch) sendBatch,
  ) async {
    if (_telemetryPaused ||
        _isUnauthorized ||
        !offlineBuffer ||
        _isProcessing) {
      return;
    }

    _isProcessing = true;

    try {
      final cachedCrashes = crashOffline.getCachedCrashes();
      if (cachedCrashes.isEmpty) return;

      for (var i = 0; i < cachedCrashes.length; i += batchSize) {
        if (_telemetryPaused || _isUnauthorized) break;

        final end = (i + batchSize < cachedCrashes.length)
            ? i + batchSize
            : cachedCrashes.length;
        final batch = cachedCrashes.sublist(i, end);

        final success = await _sendBatchWithRetry(batch, sendBatch);

        if (success) {
          for (final crash in batch) {
            await crashOffline.deleteCrash(crash);
          }
          debugPrint(
            '[TraceX] Flushed batch of ${batch.length} crashes successfully.',
          );
        } else {
          break;
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<bool> _sendBatchWithRetry(
    List<Crash> batch,
    Future<void> Function(List<Crash> batch) sendBatch,
  ) async {
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        await sendBatch(batch);
        return true;
      } catch (e) {
        debugPrint('[TraceX] Batch attempt $attempt/$_maxRetries failed: $e');

        if (e is DioException && e.response?.statusCode == 401) {
          _isUnauthorized = true;
          _telemetryPaused = true;
          _queue.clear();
          debugPrint('[TraceX] 401 Unauthorized: Halting batch flush.');
          return false;
        }

        if (!_isRetryable(e)) {
          return false;
        }

        if (attempt == _maxRetries) return false;

        final delayMs = (1 << (attempt - 1)) * 1000 + Random().nextInt(500);
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    return false;
  }

  void dispose() {
    _offlineRetryTimer?.cancel();
    _offlineRetryTimer = null;
    _queue.clear();
    _isProcessing = false;
    _telemetryPaused = false;
    _isUnauthorized = false;
  }
}
