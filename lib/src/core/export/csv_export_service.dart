import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CsvExportService {
  CsvExportService._();

  static final CsvExportService instance = CsvExportService._();

  Future<void> shareTransactionsCsv({
    required List<Map<String, dynamic>> rows,
    required String fileStem,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final safeStem = fileStem
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final fileName =
        '${safeStem.isEmpty ? 'money_manager_export' : safeStem}.csv';
    final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(_buildTransactionsCsv(rows));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Money Manager CSV export',
        text: 'CSV export generated from Money Manager.',
      ),
    );
  }

  String _buildTransactionsCsv(List<Map<String, dynamic>> rows) {
    final buffer = StringBuffer();
    buffer.writeln(
      [
        'Date',
        'Kind',
        'Account',
        'Transfer Account',
        'Category',
        'Source Currency',
        'Original Amount',
        'Display Amount',
        'Note',
      ].map(_escapeCsvCell).join(','),
    );

    for (final row in rows) {
      final account = _relationField(row['account'], 'name', fallback: '—');
      final transferAccount =
          _relationField(row['transfer_account'], 'name', fallback: '');
      final category = _relationField(row['categories'], 'name', fallback: '');
      final sourceCurrency =
          _relationField(row['account'], 'currency_code', fallback: '');
      final rawAmount = ((row['amount'] as num?) ?? 0).toDouble();
      final displayAmount =
          ((row['display_amount'] as num?) ?? rawAmount).toDouble();
      final transactionDate = DateTime.tryParse(
        (row['transaction_date'] ?? '').toString(),
      );
      final dateLabel = transactionDate == null
          ? ''
          : DateFormat('yyyy-MM-dd HH:mm').format(transactionDate.toLocal());

      buffer.writeln(
        [
          dateLabel,
          (row['kind'] ?? '').toString(),
          account,
          transferAccount,
          category,
          sourceCurrency,
          rawAmount.toStringAsFixed(2),
          displayAmount.toStringAsFixed(2),
          (row['note'] ?? '').toString().trim(),
        ].map(_escapeCsvCell).join(','),
      );
    }

    return buffer.toString();
  }

  String _relationField(
    dynamic relation,
    String field, {
    required String fallback,
  }) {
    if (relation is Map) {
      return (relation[field] ?? fallback).toString();
    }
    if (relation is List && relation.isNotEmpty && relation.first is Map) {
      return ((relation.first as Map)[field] ?? fallback).toString();
    }
    return fallback;
  }

  String _escapeCsvCell(String value) {
    final normalized = value.replaceAll('"', '""');
    if (normalized.contains(',') ||
        normalized.contains('"') ||
        normalized.contains('\n')) {
      return '"$normalized"';
    }
    return normalized;
  }
}
