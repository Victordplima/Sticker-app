abstract final class EmojiHelper {
  static List<String> sanitize(List<String> emojis) {
    final normalized = <String>[];

    for (final emoji in emojis) {
      final trimmed = emoji.trim();
      if (trimmed.isEmpty || normalized.contains(trimmed)) {
        continue;
      }

      normalized.add(trimmed);
    }

    return normalized;
  }

  static String primaryOrFallback(
    List<String> emojis, {
    String fallback = '🙂',
  }) {
    final sanitized = sanitize(emojis);
    return sanitized.isEmpty ? fallback : sanitized.first;
  }
}
