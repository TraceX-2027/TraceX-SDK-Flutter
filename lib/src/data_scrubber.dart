/// Data scrubber for redacting sensitive credentials, payment details,
/// and local user directory paths before telemetry serialization and transit.
class DataScrubber {
  DataScrubber._();

  // 1. Bearer Token Regex (per spec: Bearer\s+[A-Za-z0-9\-\._~\+\/]+=*)
  static final RegExp _bearerRegex = RegExp(
    r'Bearer\s+[A-Za-z0-9\-\._~\+\/]+=*',
    caseSensitive: false,
  );

  // N1: Sensitive URL Query Parameters Regex
  static final RegExp _urlQueryParamRegex = RegExp(
    r'([?&](?:password|token|api_?key|secret|auth)=)[^&\s]+',
    caseSensitive: false,
  );

  // M1: Sensitive Keys Regex supporting camelCase transitions (userPassword, authToken, accountSecret)
  // Matching boundary or lowercase prefix, sensitive root, followed by uppercase transition, boundary or non-alphanumeric
  static final RegExp _sensitiveKeyRegex = RegExp(
    r'(^|[a-z_]|[^a-zA-Z0-9])(password|secret|token|api_?key|auth|credit_?card|access_?token|cvv|cvc|pin|private_?key|secret_?key|ssn)([A-Z_]|$|[^a-zA-Z0-9])',
  );

  // N2: File System Absolute Paths Regex (supports \ and / on Windows, Unix, and Mobile Sandboxes)
  static final RegExp _filePathRegex = RegExp(
    r'([a-zA-Z]:[/\\]Users[/\\][^/\\]+|/(Users|home|data/user/\d+|data/data|var/mobile(?:/Containers/Data/Application)?)/[^/\s]+)',
    caseSensitive: false,
  );

  // 4. Candidate Credit Card 13-19 digit sequences (with optional hyphens or spaces)
  static final RegExp _creditCardCandidateRegex = RegExp(
    r'\b(?:\d[ -]*?){13,19}\b',
  );

  // N3: Pre-compiled regex for stripping non-digit characters
  static final RegExp _nonDigitsRegex = RegExp(r'\D');

  /// Redacts sensitive patterns in a string (bearer tokens, credit cards, user paths, query params).
  static String scrubString(String text) {
    if (text.isEmpty) return text;

    // 1. Redact Bearer tokens
    var scrubbed = text.replaceAll(_bearerRegex, 'Bearer [REDACTED]');

    // N1. Redact Sensitive URL Query Parameters
    scrubbed = scrubbed.replaceAllMapped(_urlQueryParamRegex, (match) {
      return '${match.group(1)}[REDACTED]';
    });

    // N2. Redact file system user directories and mobile sandboxes
    scrubbed = scrubbed.replaceAll(_filePathRegex, '[PATH_REDACTED]');

    // 3. Redact Credit Cards using Luhn algorithm
    scrubbed = scrubbed.replaceAllMapped(_creditCardCandidateRegex, (match) {
      final raw = match.group(0)!;
      final digitsOnly = raw.replaceAll(_nonDigitsRegex, '');
      if (digitsOnly.length >= 13 &&
          digitsOnly.length <= 19 &&
          _isValidLuhn(digitsOnly)) {
        return '[CARD_REDACTED]';
      }
      return raw;
    });

    return scrubbed;
  }

  /// Sanitizes key-value maps recursively, masking sensitive keys and scrubbing values.
  static Map<String, dynamic> scrubMap(Map<dynamic, dynamic> map) {
    return map.map((key, value) {
      final stringKey = key.toString();

      if (_isSensitiveKey(stringKey)) {
        return MapEntry(stringKey, '[REDACTED]');
      }

      if (value is Map) {
        final stringKeyed = value.map((k, v) => MapEntry(k.toString(), v));
        return MapEntry(stringKey, scrubMap(stringKeyed));
      } else if (value is List) {
        return MapEntry(stringKey, _scrubList(value));
      } else if (value is String) {
        return MapEntry(stringKey, scrubString(value));
      }
      return MapEntry(stringKey, value);
    });
  }

  static bool _isSensitiveKey(String key) {
    // Check both standard case and camelCase matching
    if (_sensitiveKeyRegex.hasMatch(key)) return true;
    // Lowercase fallback for compound keys with delimiters
    final lower = key.toLowerCase();
    return _sensitiveKeyRegex.hasMatch(lower);
  }

  static List<dynamic> _scrubList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map) {
        final stringKeyed = item.map((k, v) => MapEntry(k.toString(), v));
        return scrubMap(stringKeyed);
      } else if (item is List) {
        return _scrubList(item);
      } else if (item is String) {
        return scrubString(item);
      }
      return item;
    }).toList();
  }

  /// Validates credit card sequence using the Luhn checksum algorithm.
  static bool _isValidLuhn(String number) {
    int sum = 0;
    bool alternate = false;
    for (int i = number.length - 1; i >= 0; i--) {
      int digit = int.parse(number[i]);
      if (alternate) {
        digit *= 2;
        if (digit > 9) {
          digit -= 9;
        }
      }
      sum += digit;
      alternate = !alternate;
    }
    return (sum % 10 == 0);
  }
}
