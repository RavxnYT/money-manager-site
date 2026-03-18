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

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(',', '').replaceAll(' ', '');
    if (raw.isEmpty) return const TextEditingValue();

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

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}
