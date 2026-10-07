# TraceX Flutter SDK

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Official Flutter SDK for **TraceX** — developer-first, AI-assisted crash observability with sub-50ms Cloudflare Edge Ingestion, intelligent origin failover, offline FIFO queuing, and automated root-cause analysis.

---

## Features

- ⚡ **Cloudflare Edge Ingestion**: Telemetry is routed through Anycast edge workers with low latency (<50ms) and automatic sticky failover to direct origin APIs on network failures.
- 🛡️ **Zero Telemetry Loss (Offline Queue)**: Unhandled crashes and breadcrumbs are cached locally using Hive in a 100-event FIFO buffer and automatically replayed when network connectivity is restored.
- 🎯 **5-Minute Fingerprint Deduplication**: In-memory micro-cooldown deduplicates storm bursts of repeated exceptions.
- 🧭 **Automatic Route Breadcrumbs**: Track user navigation paths across your application with `TraceXNavigatorObserver`.
- 🌐 **HTTP Network Breadcrumbs**: Track HTTP request durations, status codes, and network failures with `TraceXDioInterceptor`.
- 📱 **Hardware Environment Telemetry**: Captures battery level, total/free RAM, low-memory flags, OS version, device model, and app package metadata.

---

## Installation

Add `tracex` to your `pubspec.yaml` via Git repository:

### Option 1: Terminal Command

```bash
flutter pub add tracex --git-url=https://github.com/TraceX-2027/TraceX-SDK-Flutter.git
```

### Option 2: pubspec.yaml

Add the dependency under `dependencies` in your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  tracex:
    git: https://github.com/TraceX-2027/TraceX-SDK-Flutter.git
```

Then run:

```bash
flutter pub get
```

---

## Quickstart

### 1. Initialize TraceX in `main()`

Initialize TraceX before running `runApp()`. TraceX automatically hooks into `FlutterError.onError` and `PlatformDispatcher.instance.onError` to intercept unhandled exceptions.

```dart
import 'package:flutter/material.dart';
import 'package:tracex/tracex.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize TraceX SDK with your project API key
  await TraceX.init(
    projectKey: 'YOUR_PROJECT_API_KEY',
    enableLogging: true, // Optional: print internal SDK logs to console
  );

  runApp(const MyApp());
}
```

### 2. Add Navigation Route Breadcrumbs

Add `TraceXNavigatorObserver` to your `MaterialApp` to automatically record route pushes, pops, and replacements:

```dart
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My TraceX App',
      navigatorObservers: [
        TraceXNavigatorObserver(),
      ],
      home: const HomeScreen(),
    );
  }
}
```

### 3. Add HTTP Network Breadcrumbs (Dio)

If your app uses `dio` for HTTP networking, attach `TraceXDioInterceptor` to track outgoing requests and latency:

```dart
import 'package:dio/dio.dart';
import 'package:tracex/tracex.dart';

final dio = Dio();
dio.interceptors.add(TraceXDioInterceptor());
```

---

## Manual Error Reporting

### Record Caught Exceptions

Capture handled try-catch exceptions without crashing the user's interface:

```dart
try {
  await performCriticalCheckout();
} catch (error, stackTrace) {
  TraceX.recordError(
    error,
    stackTrace,
    reason: 'Payment gateway rejected customer card',
    fatal: false,
  );
}
```

### Run Within a Guarded Zone

Catch unhandled asynchronous exceptions in custom microtasks or isolates:

```dart
void main() {
  TraceX.runGuarded(() {
    runApp(const MyApp());
  });
}
```

---

## Configuration Options

| Parameter | Type | Default | Description |
|---|---|---|---|
| `projectKey` | `String` | **Required** | Your TraceX Project API Key (`tracex_live_...`). Can also use `apiKey`. |
| `enableLogging` | `bool` | `false` | When `true`, prints internal SDK diagnostic events via `debugPrint`. |
| `offlineBuffer` | `bool` | `true` | When `true`, caches crashes in offline storage if offline or rate-limited. |
| `captureBreadcrumbs` | `bool` | `true` | When `true`, records navigation and lifecycle breadcrumbs. |
| `endpoint` | `String?` | Edge Base URL | Custom ingestion gateway endpoint (defaults to Cloudflare Edge). |
| `fallbackEndpoint` | `String?` | Origin Base URL | Custom origin endpoint for fallback when edge is unreachable. |

---

## Testing Your Integration

To verify that your integration is streaming events to your TraceX dashboard:

```dart
ElevatedButton(
  onPressed: () {
    throw StateError('Simulated Test Crash from Flutter App');
  },
  child: const Text('Trigger Test Crash'),
)
```

Within seconds, check your **TraceX Incident Stream** at `/dashboard/issues` to inspect symbolicated stack frames, environment details, and AI root cause diagnosis!