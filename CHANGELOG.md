## 1.0.0

* Initial release of the official TraceX Flutter SDK.
* Real-time crash capture and forensic telemetry.
* Circular ring buffer breadcrumb harvesting (navigation, user interactions, network requests).
* Dio HTTP interceptor with automatic path truncation and Bearer token redaction.
* Offline crash buffer with FIFO eviction (up to 100 crashes).
* Intelligent edge routing with automatic fallback to origin API.
* Data sanitizer with Luhn algorithm for PCI compliance and sensitive parameter redaction.
