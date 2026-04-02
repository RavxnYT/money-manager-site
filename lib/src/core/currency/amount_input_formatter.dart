import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Parses user-entered money text like `1,234.56` into a number.
double? parseFormattedAmount(String? value) {
  final normalized = (value ?? '').replaceAll(',', '').replaceAll(' ', '').trim();
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

/// Formats amount input live with thousand separators while typing.
class AmountInputFormatter extends TextInputFormatter {
  AmountInputFormatter() : _numberFormat = NumberFormat('#,##0', 'en_US');

  final NumberFormat _numberFormat;

  /// Digits and decimal point before [offset] in [text] (ignores commas / spaces).
  static int _rawCharCountBefore(String text, int offset) {
    final end = offset.clamp(0, text.length);
    var n = 0;
    for (var i = 0; i < end; i++) {
      final c = text[i];
      if (c != ',' && c != ' ') n++;
    }
    return n;
  }

  /// Offset in [formatted] after [rawCount] meaningful characters (digits or `.`).
  static int _formattedOffsetAfterRawCount(String formatted, int rawCount) {
    if (rawCount <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      final c = formatted[i];
      if (c != ',' && c != ' ') {
        seen++;
        if (seen >= rawCount) return i + 1;
      }
    }
    return formatted.length;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(',', '').replaceAll(' ', '');
    if (raw.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Accept digits and a single decimal point only.
    final valid = RegExp(r'^\d*\.?\d*$');
    if (!valid.hasMatch(raw)) return oldValue;

    final parts = raw.split('.');
    if (parts.length > 2) return oldValue;

    final integerRaw = parts.first;
    final decimalRaw = parts.length == 2 ? parts[1] : null;

    final integerValue = integerRaw.isEmpty ? 0 : int.tryParse(integerRaw);
    if (integerValue == null) return oldValue;

    final formattedInteger = _numberFormat.format(integerValue);
    final formattedText =
        decimalRaw == null ? formattedInteger : '$formattedInteger.$decimalRaw';

    final cursor = newValue.selection.isValid
        ? newValue.selection.extentOffset
        : newValue.text.length;
    final rawBefore =
        _rawCharCountBefore(newValue.text, cursor).clamp(0, raw.length);
    final newOffset =
        _formattedOffsetAfterRawCount(formattedText, rawBefore).clamp(
      0,
      formattedText.length,
    );

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
