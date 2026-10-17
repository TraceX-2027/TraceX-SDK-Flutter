# TraceX Flutter SDK Example

This example demonstrates how to integrate and use the `tracex_flutter` SDK for crash monitoring, breadcrumb navigation tracking, and diagnostic telemetry.

## Running the Example

1. Navigate to the example directory:
   ```bash
   cd example
   ```

2. Fetch dependencies:
   ```bash
   flutter pub get
   ```

3. Run on your connected emulator or device:
   ```bash
   flutter run
   ```

## Features Demonstrated

- **Initialization**: Initializing `TraceX.init(...)` with project API key.
- **Route Tracking**: Registering `TraceXNavigatorObserver` in `MaterialApp`.
- **Manual Error Recording**: Capturing non-fatal caught exceptions via `TraceX.recordError(...)`.
- **Automatic Crash Interception**: Uncaught errors caught by Flutter framework error handlers.
