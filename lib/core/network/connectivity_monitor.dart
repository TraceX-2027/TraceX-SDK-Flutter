import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Monitors device network connectivity state transitions and triggers callbacks on reconnection.
class ConnectivityMonitor {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  List<ConnectivityResult> _previousResults = [ConnectivityResult.none];

  /// Creates a [ConnectivityMonitor] with an optional custom [connectivity] instance.
  ConnectivityMonitor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  /// Starts listening for connectivity status changes, invoking [onReconnected] when returning online.
  void startListening({required VoidCallback onReconnected}) {
    _subscription?.cancel();

    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final wasDisconnected =
            _previousResults.isEmpty ||
            _previousResults.every((r) => r == ConnectivityResult.none);

        final isConnectedNow = results.any(
          (r) =>
              r == ConnectivityResult.wifi ||
              r == ConnectivityResult.mobile ||
              r == ConnectivityResult.ethernet ||
              r == ConnectivityResult.vpn,
        );

        if (wasDisconnected && isConnectedNow) {
          debugPrint(
            '[TraceX] Network connection restored. Triggering batch sync...',
          );
          onReconnected();
        }

        _previousResults = results;
      },
      onError: (error) {
        debugPrint('[TraceX] Connectivity monitoring error: $error');
      },
    );
  }

  /// Stops listening for connectivity changes and cleans up stream subscriptions.
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Sets previous connectivity results for test mocking.
  @visibleForTesting
  void setPreviousResultsForTesting(List<ConnectivityResult> results) {
    _previousResults = results;
  }
}
