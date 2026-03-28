import 'package:intl/intl.dart';

/// Parses API/cache values: full ISO8601 or legacy `yyyy-MM-dd`.
DateTime? parseTransactionDate(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// Local wall-clock display for list subtitles and labels.
String formatTransactionDateForDisplay(dynamic raw) {
  final dt = parseTransactionDate(raw);
  if (dt == null) return raw?.toString() ?? '';
  return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
}
