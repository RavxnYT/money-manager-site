/// Maps substrings in transaction notes (lowercase) to typical category *names*.
/// Resolved against the user\'s real categories with case-insensitive matching.
class MerchantKeywordHints {
  MerchantKeywordHints._();

  /// (note substring, preferred category name — matches user category if similar).
  static const List<(String, String)> expenseHints = [
    ('uber', 'Transport'),
    ('lyft', 'Transport'),
    ('doordash', 'Dining Out'),
    ('grubhub', 'Dining Out'),
    ('starbucks', 'Coffee'),
    ('netflix', 'Streaming'),
    ('spotify', 'Streaming'),
    ('hulu', 'Streaming'),
    ('disney+', 'Streaming'),
    ('youtube premium', 'Streaming'),
    ('amazon', 'Shopping'),
    ('walmart', 'Groceries'),
    ('target', 'Shopping'),
    ('costco', 'Groceries'),
    ('whole foods', 'Groceries'),
    ('shell ', 'Fuel'),
    ('exxon', 'Fuel'),
    ('chevron', 'Fuel'),
    ('pharmacy', 'Pharmacy'),
    ('cvs', 'Pharmacy'),
    ('walgreens', 'Pharmacy'),
    ('gym', 'Fitness'),
    ('planet fitness', 'Fitness'),
    ('rent', 'Rent'),
    ('mortgage', 'Rent'),
    ('electric', 'Utilities'),
    ('water bill', 'Utilities'),
    ('internet', 'Mobile & Internet'),
    ('phone bill', 'Mobile & Internet'),
    ('insurance', 'Insurance'),
    ('doctor', 'Health'),
    ('hospital', 'Health'),
    ('flight', 'Travel'),
    ('airline', 'Travel'),
    ('hotel', 'Travel'),
    ('stripe', 'Business'),
    ('paypal', 'Fees'),
  ];

  static const List<(String, String)> incomeHints = [
    ('salary', 'Salary'),
    ('payroll', 'Salary'),
    ('freelance', 'Freelance'),
    ('invoice', 'Freelance'),
    ('dividend', 'Dividends'),
    ('interest', 'Interest'),
    ('refund', 'Refund'),
    ('cashback', 'Cashback'),
  ];

  static List<(String, String)> hintsForKind(String kind) =>
      kind == 'income' ? incomeHints : expenseHints;

  /// Returns category id if a hint matches [noteNormalized] (already lowercased).
  static String? resolveCategoryId({
    required String noteLower,
    required String kind,
    required List<Map<String, dynamic>> categories,
  }) {
    if (noteLower.isEmpty) return null;
    for (final rule in hintsForKind(kind)) {
      if (!noteLower.contains(rule.$1)) continue;
      final want = rule.$2.toLowerCase();
      for (final c in categories) {
        final name = (c['name'] ?? '').toString().toLowerCase();
        if (name == want || name.contains(want) || want.contains(name)) {
          return c['id']?.toString();
        }
      }
    }
    return null;
  }
}
