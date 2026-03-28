import 'package:supabase_flutter/supabase_flutter.dart';

/// Central entry for Supabase RPCs that mutate the transactions ledger and
/// account `current_balance` fields.
///
/// **Income, expense, and transfers** are all created via [createTransaction]
/// (`create_transaction`). **Transfers** use [transferAccountId] and optional
/// [transferCreditAmount] for cross-currency credits. Savings- and loan-linked
/// transfers use the Supabase RPC `execute_entity_transfer` instead of this API.
///
/// **Deletes** go through [deleteTransaction] (`delete_transaction`) so
/// balance reversals stay consistent with stored `amount` /
/// `transfer_credit_amount`.
///
/// Do not call `create_transaction` / `delete_transaction` from elsewhere;
/// routing everything here avoids duplicate or mismatched balance updates.
class TransactionLedgerService {
  TransactionLedgerService(this._client);

  final SupabaseClient _client;

  User _requireUser() {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('You must be signed in to change transactions.');
    }
    return user;
  }

  /// Inserts a transaction row and updates balances on the server.
  Future<void> createTransaction({
    required String accountId,
    String? categoryId,
    required String kind,
    required double amount,
    required DateTime transactionDate,
    String? note,
    String? transferAccountId,
    double? transferCreditAmount,
    String? organizationId,
  }) async {
    final user = _requireUser();

    final params = <String, dynamic>{
      'p_user_id': user.id,
      'p_organization_id': organizationId,
      'p_account_id': accountId,
      'p_category_id': categoryId,
      'p_kind': kind,
      'p_amount': amount,
      'p_transaction_date': transactionDate.toUtc().toIso8601String(),
      'p_note': note,
      'p_transfer_account_id': transferAccountId,
      'p_transfer_credit_amount': transferCreditAmount,
    };

    await _client.rpc('create_transaction', params: params);
  }

  /// Deletes the transaction row and reverses its balance effects on the server.
  Future<void> deleteTransaction(
    String transactionId, {
    String? organizationId,
  }) async {
    final user = _requireUser();
    await _client.rpc(
      'delete_transaction',
      params: {
        'p_user_id': user.id,
        'p_organization_id': organizationId,
        'p_transaction_id': transactionId,
      },
    );
  }

  /// Updates amount, category, note, and applies net balance deltas on the server.
  ///
  /// For **transfers**, pass [transferCreditAmount] when the destination currency
  /// differs from the source (same rule as [createTransaction]).
  Future<void> updateTransaction({
    required String transactionId,
    required double amount,
    String? categoryId,
    String? note,
    double? transferCreditAmount,
    String? organizationId,
  }) async {
    final user = _requireUser();
    final params = <String, dynamic>{
      'p_user_id': user.id,
      'p_organization_id': organizationId,
      'p_transaction_id': transactionId,
      'p_amount': amount,
      'p_category_id': categoryId,
      'p_note': note,
    };
    if (transferCreditAmount != null) {
      params['p_transfer_credit_amount'] = transferCreditAmount;
    }
    await _client.rpc('update_transaction', params: params);
  }
}
