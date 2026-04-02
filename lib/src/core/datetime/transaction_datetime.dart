import 'package:intl/intl.dart';

bool _isoHasExplicitTimeZone(String s) {
  if (s.isEmpty) return false;
  final last = s.codeUnitAt(s.length - 1);
  if (last == 0x5a || last == 0x7a) return true; // Z z
  return RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(s) ||
      RegExp(r'[+-]\d{4}$').hasMatch(s);
}

/// Parses API/cache values: full ISO8601 or legacy `yyyy-MM-dd`.
///
/// Postgres `timestamptz` is stored in UTC; some JSON payloads omit a `Z` /
/// offset. Dart would parse those as *local* time, which skews list display.
DateTime? parseTransactionDate(dynamic raw) {
  if (raw == null) return null;
  var s = raw.toString().trim();
  if (s.isEmpty) return null;
  // Rare Postgres / driver style `yyyy-MM-dd hh:mm:ss` (space, not `T`)
  s = s.replaceFirst(RegExp(r'(\d{4}-\d{2}-\d{2})\s+'), r'$1T');
  if (!s.contains('T')) {
    return DateTime.tryParse(s);
  }
  if (_isoHasExplicitTimeZone(s)) {
    return DateTime.tryParse(s);
  }
  final suffixed = s.endsWith('T') ? '${s}00:00:00.000Z' : '${s}Z';
  return DateTime.tryParse(suffixed) ?? DateTime.tryParse(s);
}

/// Local wall-clock display for list subtitles and labels.
String formatTransactionDateForDisplay(dynamic raw) {
  final dt = parseTransactionDate(raw);
  if (dt == null) return raw?.toString() ?? '';
  return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
}
