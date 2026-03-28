import 'package:flutter/material.dart';

const Map<String, IconData> businessCategoryIconChoices = {
  'briefcase': Icons.work_rounded,
  'store': Icons.storefront_rounded,
  'chart': Icons.show_chart_rounded,
  'wallet': Icons.account_balance_wallet_rounded,
  'receipt': Icons.receipt_long_rounded,
  'cart': Icons.shopping_cart_rounded,
  'restaurant': Icons.restaurant_rounded,
  'car': Icons.directions_car_rounded,
  'home': Icons.home_rounded,
  'health': Icons.favorite_rounded,
  'bolt': Icons.bolt_rounded,
  'school': Icons.school_rounded,
  'flight': Icons.flight_rounded,
  'gift': Icons.card_giftcard_rounded,
  'fitness': Icons.fitness_center_rounded,
  'pets': Icons.pets_rounded,
  'build': Icons.build_rounded,
  'coffee': Icons.coffee_rounded,
  'movie': Icons.movie_rounded,
  'savings': Icons.savings_rounded,
};

const List<String> businessCategoryColorPalette = [
  '#3BD188',
  '#4F7CFF',
  '#8EA2FF',
  '#FF6B86',
  '#FF9F43',
  '#FFD166',
  '#06D6A0',
  '#118AB2',
  '#8338EC',
  '#EF476F',
  '#F72585',
  '#73C2FB',
];

IconData? businessCategoryIconForKey(String? key) {
  final normalized = (key ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return null;
  return businessCategoryIconChoices[normalized];
}

String? normalizeCategoryColorHex(String? raw) {
  final value = (raw ?? '').trim().toUpperCase();
  if (value.isEmpty) return null;
  final sanitized = value.startsWith('#') ? value.substring(1) : value;
  if (sanitized.length != 6) return null;
  final isHex = RegExp(r'^[0-9A-F]{6}$').hasMatch(sanitized);
  if (!isHex) return null;
  return '#$sanitized';
}

Color? categoryColorFromHex(String? raw) {
  final normalized = normalizeCategoryColorHex(raw);
  if (normalized == null) return null;
  final hex = normalized.substring(1);
  final value = int.tryParse('FF$hex', radix: 16);
  if (value == null) return null;
  return Color(value);
}
