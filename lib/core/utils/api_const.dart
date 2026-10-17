/// Constants and URL endpoints used for TraceX API communication.
class ApiConst {
  ApiConst._();

  /// Cloudflare Edge Ingestion base URL for low-latency crash telemetry.
  static const String edgeBaseUrl =
      "https://tracex-edge-ingest.kareemadel10110.workers.dev/api/v1/";

  /// Origin API base URL for standard backend operations.
  static const String originBaseUrl = "https://api.tracex.dev/api/v1/";

  /// Active base URL currently configured for ingestion.
  static String baseUrl = edgeBaseUrl;

  /// Full endpoint URL for single crash telemetry ingestion.
  static String get crashUrl => "${baseUrl}crashes";

  /// Full endpoint URL for batch crash telemetry ingestion.
  static String get batchCrashUrl => "${baseUrl}crashes/batch";

  /// Fallback origin URL for single crash telemetry ingestion.
  static String get originCrashUrl => "${originBaseUrl}crashes";
}
