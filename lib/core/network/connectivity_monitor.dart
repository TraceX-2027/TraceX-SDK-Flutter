import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityMonitor {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  List<ConnectivityResult> _previousResults = [ConnectivityResult.none];

  ConnectivityMonitor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

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

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  @visibleForTesting
  void setPreviousResultsForTesting(List<ConnectivityResult> results) {
    _previousResults = results;
  }
}
