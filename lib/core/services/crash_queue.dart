import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:tracex/domain/entities/crash.dart';

class CrashQueue {
  final int maxSize;
  final int maxRetries;

  final Queue<Crash> _queue = Queue<Crash>();

  bool _isProcessing = false;

  CrashQueue({this.maxSize = 20, this.maxRetries = 3});

  int get length => _queue.length;

  bool get isEmpty => _queue.isEmpty;

  bool get isFull => _queue.length >= maxSize;

  void add(Crash crash) {
    if (isFull) {
      debugPrint('TraceX: Crash queue is full. Crash dropped.');
      return;
    }

    _queue.addLast(crash);

    debugPrint('TraceX: Crash added to queue (size: ${_queue.length})');
  }

  Crash? removeFirst() {
    if (_queue.isEmpty) {
      return null;
    }

    return _queue.removeFirst();
  }

  Future<void> process(Future<void> Function(Crash crash) sendCrash) async {
    if (_isProcessing) {
      return;
    }

    _isProcessing = true;

    try {
      while (_queue.isNotEmpty) {
        final crash = removeFirst();

        if (crash == null) {
          break;
        }

        final success = await _sendWithRetry(crash, sendCrash);

        if (!success) {
          debugPrint(
            'TraceX: Crash could not be sent after '
            '$maxRetries retries.',
          );
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<bool> _sendWithRetry(
    Crash crash,
    Future<void> Function(Crash crash) sendCrash,
  ) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await sendCrash(crash);

        debugPrint('TraceX: Crash sent successfully.');

        return true;
      } catch (e) {
        debugPrint(
          'TraceX: Failed to send crash '
          '(attempt $attempt/$maxRetries): $e',
        );

        if (attempt < maxRetries) {
          final delaySeconds = 1 << (attempt - 1);

          await Future.delayed(Duration(seconds: delaySeconds));
        }
      }
    }

    return false;
  }

  void clear() {
    _queue.clear();
  }
}
