import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_management_app/src/core/categories/category_icon_utils.dart';

void main() {
  group('categoryIconFor', () {
    test('maps exact known expense categories', () {
      expect(
        categoryIconFor(name: 'Food', type: 'expense'),
        equals(Icons.restaurant_rounded),
      );
      expect(
        categoryIconFor(name: 'Rent', type: 'expense'),
        equals(Icons.home_rounded),
      );
      expect(
        categoryIconFor(name: 'Transport', type: 'expense'),
        equals(Icons.directions_car_rounded),
      );
    });

    test('maps exact known income categories', () {
      expect(
        categoryIconFor(name: 'Salary', type: 'income'),
        equals(Icons.work_rounded),
      );
      expect(
        categoryIconFor(name: 'Freelance', type: 'income'),
        equals(Icons.computer_rounded),
      );
    });

    test('uses keyword matching when exact match does not exist', () {
      expect(
        categoryIconFor(name: 'Stock Profit', type: 'income'),
        equals(Icons.show_chart_rounded),
      );
      expect(
        categoryIconFor(name: 'Dining Out', type: 'expense'),
        equals(Icons.restaurant_rounded),
      );
    });

    test('returns default income icon for unknown user category', () {
      expect(
        categoryIconFor(name: 'My Side Project', type: 'income'),
        equals(Icons.add_card_rounded),
      );
    });

    test('returns default expense icon for unknown user category', () {
      expect(
        categoryIconFor(name: 'Misc Custom Stuff', type: 'expense'),
        equals(Icons.category_rounded),
      );
    });

    test('handles case-insensitive and trimmed names', () {
      expect(
        categoryIconFor(name: '   sAlArY   ', type: 'income'),
        equals(Icons.work_rounded),
      );
    });
  });
}
