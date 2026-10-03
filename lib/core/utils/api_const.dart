class ApiConst {
  static const String edgeBaseUrl =
      "https://tracex-edge-ingest.kareemadel10110.workers.dev/api/v1/";
  static const String originBaseUrl =
      "https://tracex-api.kareemadel.com/api/v1/";

  static String baseUrl = edgeBaseUrl;

  static String get crashUrl => "${baseUrl}crashes";
  static String get batchCrashUrl => "${baseUrl}crashes/batch";
  static String get originCrashUrl => "${originBaseUrl}crashes";
}
