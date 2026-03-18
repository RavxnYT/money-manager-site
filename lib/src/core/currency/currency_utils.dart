import 'package:intl/intl.dart';

const List<String> supportedCurrencyCodes = [
  'USD',
  'EUR',
  'GBP',
  'INR',
  'AED',
  'LBP',
  'AUD',
  'CAD',
  'CHF',
  'CNY',
  'JPY',
  'KRW',
  'SGD',
  'HKD',
  'NZD',
  'SEK',
  'NOK',
  'DKK',
  'PLN',
  'CZK',
  'HUF',
  'TRY',
  'ZAR',
  'BRL',
  'MXN',
  'ARS',
  'CLP',
  'COP',
  'IDR',
  'MYR',
  'THB',
  'PHP',
  'VND',
  'PKR',
  'BDT',
  'SAR',
  'QAR',
  'KWD',
  'BHD',
  'OMR',
  'RUB',
];

String formatMoney(
  num amount, {
  required String currencyCode,
}) {
  final upperCode = currencyCode.toUpperCase();
  final symbol = upperCode == 'LBP' ? 'LBP ' : null;
  try {
    return NumberFormat.currency(
      name: upperCode,
      symbol: symbol,
    ).format(amount);
  } catch (_) {
    return NumberFormat.currency(symbol: '${symbol ?? '$upperCode '}').format(amount);
  }
}
