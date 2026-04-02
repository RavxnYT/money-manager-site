import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ExchangeRateService {
  ExchangeRateService._();

  static final ExchangeRateService instance = ExchangeRateService._();
  static const int _monthlyRequestQuota = 1000;

  Future<double> getRate({
    required String fromCurrency,
    required String toCurrency,
  }) async {
    final from = fromCurrency.toUpperCase();
    final to = toCurrency.toUpperCase();
    if (from == to) return 1;
    final rates = await _getUsdBaseRates();
    final fromRate = rates[from];
    final toRate = rates[to];
    if (fromRate == null || fromRate <= 0 || toRate == null || toRate <= 0) {
      throw Exception('Exchange rate not available for $from->$to');
    }
    return toRate / fromRate;
  }

  Future<Map<String, double>> _getUsdBaseRates() async {
    final prefs = await SharedPreferences.getInstance();
    const tsKey = 'rates_usd_ts';
    const jsonKey = 'rates_usd_json';
    final cacheTtl = _cacheTtlForCurrentMonth();

    final cachedTs = prefs.getInt(tsKey);
    final cachedJson = prefs.getString(jsonKey);
    if (cachedTs != null && cachedJson != null && cachedJson.isNotEmpty) {
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedTs);
      if (DateTime.now().difference(cachedAt) < cacheTtl) {
        final map = jsonDecode(cachedJson) as Map<String, dynamic>;
        return map
            .map((k, v) => MapEntry(k.toUpperCase(), (v as num).toDouble()));
      }
    }

    final appId = (dotenv.env['OPEN_EXCHANGE_RATES_APP_ID'] ?? '').trim();
    if (appId.isEmpty) {
      throw Exception('Missing OPEN_EXCHANGE_RATES_APP_ID in .env');
    }

    final uri = Uri.https(
      'openexchangerates.org',
      '/api/latest.json',
      {'app_id': appId},
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Could not fetch exchange rates');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rates = body['rates'] as Map<String, dynamic>?;
    if (rates == null || rates.isEmpty) {
      throw Exception('Invalid exchange rate response');
    }

    rates['USD'] = 1.0;

    await prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(jsonKey, jsonEncode(rates));
    final normalized =
        rates.map((k, v) => MapEntry(k.toUpperCase(), (v as num).toDouble()));
    if (normalized.containsKey('USD')) {
      return normalized;
    }
    return {'USD': 1.0, ...normalized};
  }

  Duration _cacheTtlForCurrentMonth() {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final requestsPerDayRaw = (_monthlyRequestQuota / daysInMonth).floor();
    final requestsPerDay = requestsPerDayRaw < 1 ? 1 : requestsPerDayRaw;
    final intervalMinutesRaw =
        (Duration.minutesPerDay / requestsPerDay).floor();
    final intervalMinutes =
        intervalMinutesRaw.clamp(1, Duration.minutesPerDay);
    return Duration(minutes: intervalMinutes);
  }

  Future<void> clearRateCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('rates_usd_ts');
    await prefs.remove('rates_usd_json');
  }
}
