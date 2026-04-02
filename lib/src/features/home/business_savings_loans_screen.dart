import 'package:flutter/material.dart';

import '../../data/app_repository.dart';
import 'savings_loans_hub_screen.dart';

/// Business shell entry: savings + loans hub with workspace (green) chrome.
class BusinessSavingsLoansScreen extends StatelessWidget {
  const BusinessSavingsLoansScreen({
    super.key,
    required this.repository,
  });

  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    return SavingsLoansHubScreen(
      key: key,
      repository: repository,
      businessChrome: true,
    );
  }
}
