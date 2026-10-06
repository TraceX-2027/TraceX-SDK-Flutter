class DataScrubber {
  DataScrubber._();

  // 1. Bearer Token Regex (per spec: Bearer\s+[A-Za-z0-9\-\._~\+\/]+=*)
  static final RegExp _bearerRegex = RegExp(
    r'Bearer\s+[A-Za-z0-9\-\._~\+\/]+=*',
    caseSensitive: false,
  );

  // 2. Sensitive Keys Regex (password, secret, token, api_key, auth, etc.)
  static final RegExp _sensitiveKeyRegex = RegExp(
    r'(password|secret|token|api_?key|auth|credit_?card|access_?token)',
    caseSensitive: false,
  );

  // 3. File System Absolute Paths Regex (Windows and Unix/macOS user paths)
  // e.g. C:\Users\Username\... or /Users/username/... or /home/username/...
  static final RegExp _windowsUserPathRegex = RegExp(
    r'[a-zA-Z]:\\Users\\[^\\]+',
    caseSensitive: false,
  );
  static final RegExp _unixUserPathRegex = RegExp(
    r'/(Users|home)/[^/]+',
    caseSensitive: false,
  );

  // 4. Candidate Credit Card 13-19 digit sequences (with optional hyphens or spaces)
  static final RegExp _creditCardCandidateRegex = RegExp(
    r'\b(?:\d[ -]*?){13,19}\b',
  );

  /// Redacts sensitive patterns in a string (bearer tokens, credit cards, user paths).
  static String scrubString(String text) {
    if (text.isEmpty) return text;

    // 1. Redact Bearer tokens
    var scrubbed = text.replaceAll(_bearerRegex, 'Bearer [REDACTED]');

    // 2. Redact file system user directories
    scrubbed = scrubbed.replaceAll(_windowsUserPathRegex, '[PATH_REDACTED]');
    scrubbed = scrubbed.replaceAll(_unixUserPathRegex, '[PATH_REDACTED]');

    // 3. Redact Credit Cards using Luhn algorithm
    scrubbed = scrubbed.replaceAllMapped(_creditCardCandidateRegex, (match) {
      final raw = match.group(0)!;
      final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
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
  static Map<String, dynamic> scrubMap(Map<String, dynamic> map) {
    return map.map((key, value) {
      if (_sensitiveKeyRegex.hasMatch(key)) {
        return MapEntry(key, '[REDACTED]');
      }

      if (value is Map<String, dynamic>) {
        return MapEntry(key, scrubMap(value));
      } else if (value is Map) {
        final converted = Map<String, dynamic>.from(value);
        return MapEntry(key, scrubMap(converted));
      } else if (value is List) {
        return MapEntry(key, _scrubList(value));
      } else if (value is String) {
        return MapEntry(key, scrubString(value));
      }
      return MapEntry(key, value);
    });
  }

  static List<dynamic> _scrubList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map<String, dynamic>) {
        return scrubMap(item);
      } else if (item is Map) {
        return scrubMap(Map<String, dynamic>.from(item));
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
