import 'package:flutter/material.dart';
import 'package:tracex_flutter/tracex_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize TraceX crash capture and forensic telemetry
  await TraceX.init(
    projectKey: 'tracex_live_dd047b660d19e79baf7ebba87dd55429',
    enableLogging: true,
  );

  runApp(const TraceXExampleApp());
}

class TraceXExampleApp extends StatelessWidget {
  const TraceXExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TraceX Flutter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      navigatorObservers: [TraceXNavigatorObserver()],
      home: const ExampleHomeScreen(),
    );
  }
}

class ExampleHomeScreen extends StatefulWidget {
  const ExampleHomeScreen({super.key});

  @override
  State<ExampleHomeScreen> createState() => _ExampleHomeScreenState();
}

class _ExampleHomeScreenState extends State<ExampleHomeScreen> {
  String _status = 'TraceX initialized. Press a button to test.';

  void _triggerCaughtError() {
    try {
      throw const FormatException('Example caught exception from user action');
    } catch (e, stack) {
      TraceX.recordError(e, stack, reason: 'User triggered test error');
      setState(() {
        _status = 'Recorded caught error in TraceX!';
      });
    }
  }

  void _triggerUncaughtError() {
    setState(() {
      _status = 'Triggering unhandled StateError...';
    });
    throw StateError('Example unhandled exception captured by TraceX');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TraceX Example')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _triggerCaughtError,
                icon: const Icon(Icons.bug_report),
                label: const Text('Record Caught Exception'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _triggerUncaughtError,
                icon: const Icon(Icons.error_outline),
                label: const Text('Trigger Uncaught StateError'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
