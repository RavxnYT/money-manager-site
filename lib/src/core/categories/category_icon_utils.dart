import 'package:flutter/material.dart';

String _normalizeCategoryName(String? name) {
  return (name ?? '').trim().toLowerCase();
}

IconData categoryIconFor({
  required String? name,
  required String? type,
}) {
  final normalized = _normalizeCategoryName(name);
  final categoryType = (type ?? '').trim().toLowerCase();

  const exactIcons = <String, IconData>{
    'salary': Icons.work_rounded,
    'freelance': Icons.computer_rounded,
    'business': Icons.storefront_rounded,
    'investments': Icons.trending_up_rounded,
    'dividends': Icons.paid_rounded,
    'gift': Icons.card_giftcard_rounded,
    'gifts': Icons.card_giftcard_rounded,
    'rental income': Icons.home_work_rounded,
    'rent': Icons.home_rounded,
    'transport': Icons.directions_car_rounded,
    'transportation': Icons.directions_car_rounded,
    'food': Icons.restaurant_rounded,
    'groceries': Icons.shopping_cart_rounded,
    'shopping': Icons.shopping_bag_rounded,
    'health': Icons.favorite_rounded,
    'healthcare': Icons.local_hospital_rounded,
    'medical': Icons.local_hospital_rounded,
    'education': Icons.school_rounded,
    'entertainment': Icons.movie_rounded,
    'subscriptions': Icons.subscriptions_rounded,
    'travel': Icons.flight_rounded,
    'utilities': Icons.bolt_rounded,
    'electricity': Icons.electric_bolt_rounded,
    'water': Icons.water_drop_rounded,
    'internet': Icons.wifi_rounded,
    'phone': Icons.phone_android_rounded,
    'insurance': Icons.security_rounded,
    'tax': Icons.receipt_long_rounded,
    'charity': Icons.volunteer_activism_rounded,
    'loan payment': Icons.account_balance_rounded,
    'debt': Icons.account_balance_rounded,
    'pets': Icons.pets_rounded,
    'childcare': Icons.child_care_rounded,
    'beauty': Icons.face_retouching_natural_rounded,
    'fitness': Icons.fitness_center_rounded,
    'maintenance': Icons.build_rounded,
    'car maintenance': Icons.car_repair_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'home': Icons.house_rounded,
    'electronics': Icons.devices_rounded,
    'clothing': Icons.checkroom_rounded,
    'snacks': Icons.fastfood_rounded,
    'coffee': Icons.coffee_rounded,
  };

  final exact = exactIcons[normalized];
  if (exact != null) return exact;

  if (normalized.contains('salary') ||
      normalized.contains('bonus') ||
      normalized.contains('income')) {
    return Icons.account_balance_wallet_rounded;
  }
  if (normalized.contains('freelance') || normalized.contains('contract')) {
    return Icons.laptop_chromebook_rounded;
  }
  if (normalized.contains('invest') || normalized.contains('stock')) {
    return Icons.show_chart_rounded;
  }
  if (normalized.contains('food') ||
      normalized.contains('restaurant') ||
      normalized.contains('dining')) {
    return Icons.restaurant_rounded;
  }
  if (normalized.contains('grocery') || normalized.contains('supermarket')) {
    return Icons.local_grocery_store_rounded;
  }
  if (normalized.contains('shop') || normalized.contains('clothes')) {
    return Icons.shopping_bag_rounded;
  }
  if (normalized.contains('transport') ||
      normalized.contains('taxi') ||
      normalized.contains('uber') ||
      normalized.contains('bus')) {
    return Icons.directions_bus_rounded;
  }
  if (normalized.contains('fuel') || normalized.contains('gas')) {
    return Icons.local_gas_station_rounded;
  }
  if (normalized.contains('rent') || normalized.contains('mortgage')) {
    return Icons.home_rounded;
  }
  if (normalized.contains('bill') ||
      normalized.contains('utility') ||
      normalized.contains('electric') ||
      normalized.contains('water') ||
      normalized.contains('internet') ||
      normalized.contains('phone')) {
    return Icons.receipt_rounded;
  }
  if (normalized.contains('health') ||
      normalized.contains('medical') ||
      normalized.contains('doctor')) {
    return Icons.local_hospital_rounded;
  }
  if (normalized.contains('education') ||
      normalized.contains('school') ||
      normalized.contains('course')) {
    return Icons.school_rounded;
  }
  if (normalized.contains('entertainment') ||
      normalized.contains('movie') ||
      normalized.contains('game')) {
    return Icons.movie_rounded;
  }
  if (normalized.contains('gift')) {
    return Icons.card_giftcard_rounded;
  }
  if (normalized.contains('travel') ||
      normalized.contains('hotel') ||
      normalized.contains('flight')) {
    return Icons.flight_takeoff_rounded;
  }

  // Default icon for any user-created category with no known mapping.
  return categoryType == 'income'
      ? Icons.add_card_rounded
      : Icons.category_rounded;
}
