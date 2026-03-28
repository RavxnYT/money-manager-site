import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_management_app/src/core/categories/category_branding.dart';
import 'package:money_management_app/src/core/categories/category_icon_utils.dart';

void main() {
  group('businessCategoryIconForKey', () {
    test('returns a known icon for explicit business branding', () {
      expect(
        businessCategoryIconForKey('briefcase'),
        equals(Icons.work_rounded),
      );
    });
  });

  group('normalizeCategoryColorHex', () {
    test('normalizes valid colors and rejects invalid values', () {
      expect(normalizeCategoryColorHex('3bd188'), '#3BD188');
      expect(normalizeCategoryColorHex('#ff6b86'), '#FF6B86');
      expect(normalizeCategoryColorHex('not-a-color'), isNull);
    });
  });

  group('categoryIconFor', () {
    test('prefers the explicit icon key over the name mapping', () {
      expect(
        categoryIconFor(
          name: 'Food',
          type: 'expense',
          iconKey: 'briefcase',
        ),
        equals(Icons.work_rounded),
      );
    });
  });
}
