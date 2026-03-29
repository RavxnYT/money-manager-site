import 'package:flutter/material.dart';

import '../../core/billing/business_entitlement_service.dart';
import '../../core/config/business_features_config.dart';
import '../../core/currency/organization_currency_prompt.dart';
import '../../data/app_repository.dart';

class BusinessModeFlow {
  static const _createBusinessChoice = '__create_business__';

  static Future<bool> enableBusinessMode({
    required BuildContext context,
    required AppRepository repository,
  }) async {
    if (!BusinessFeaturesConfig.isEnabled) return false;
    final entitled = await _ensureEntitled(
      context: context,
      repository: repository,
    );
    if (!entitled || !context.mounted) return false;

    final workspaces = await repository.fetchWorkspaces();
    final organizations = workspaces
        .where(
          (row) =>
              (row['kind'] ?? '').toString().toLowerCase() == 'organization',
        )
        .toList();

    if (organizations.isEmpty) {
      return createBusinessWorkspace(
        context: context,
        repository: repository,
      );
    }

    if (organizations.length == 1) {
      final organizationId = organizations.first['organization_id']?.toString();
      if (organizationId == null || organizationId.isEmpty) return false;
      return activateBusinessWorkspace(
        context: context,
        repository: repository,
        organizationId: organizationId,
      );
    }

    final selection = await _pickBusinessWorkspace(
      context: context,
      organizations: organizations,
    );
    if (!context.mounted || selection == null) return false;

    if (selection == _createBusinessChoice) {
      return createBusinessWorkspace(
        context: context,
        repository: repository,
      );
    }

    return activateBusinessWorkspace(
      context: context,
      repository: repository,
      organizationId: selection,
    );
  }

  static Future<bool> activateBusinessWorkspace({
    required BuildContext context,
    required AppRepository repository,
    required String organizationId,
  }) async {
    if (!BusinessFeaturesConfig.isEnabled) return false;
    final entitled = await _ensureEntitled(
      context: context,
      repository: repository,
    );
    if (!entitled) return false;

    await repository.setActiveWorkspace(
      kind: 'organization',
      organizationId: organizationId,
    );
    await repository.setBusinessModeEnabled(true);
    if (!context.mounted) return true;
    final workspaces = await repository.fetchWorkspaces();
    final row = workspaces.cast<Map<String, dynamic>?>().firstWhere(
          (w) => w?['organization_id']?.toString() == organizationId,
          orElse: () => null,
        );
    if (row != null &&
        ((row['has_selected_currency'] as bool?) ?? false) != true &&
        context.mounted) {
      await promptChooseOrganizationCurrency(
        context: context,
        repository: repository,
        organizationId: organizationId,
      );
    }
    return true;
  }

  static Future<bool> createBusinessWorkspace({
    required BuildContext context,
    required AppRepository repository,
  }) async {
    if (!BusinessFeaturesConfig.isEnabled) return false;
    final entitled = await _ensureEntitled(
      context: context,
      repository: repository,
    );
    if (!entitled || !context.mounted) return false;

    final name = await promptForBusinessName(context: context);
    if (!context.mounted || name == null) return false;

    final organizationId = await repository.createBusinessWorkspace(name: name);
    if (!context.mounted || organizationId.isEmpty) return false;
    await promptChooseOrganizationCurrency(
      context: context,
      repository: repository,
      organizationId: organizationId,
    );
    return true;
  }

  static Future<bool> disableBusinessMode({
    required AppRepository repository,
  }) async {
    await repository.setBusinessModeEnabled(false);
    await repository.setActiveWorkspace(kind: 'personal');
    return true;
  }

  static Future<String?> promptForBusinessName({
    required BuildContext context,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: const Text('Create Business'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Business name',
              hintText: 'Acme Studio',
            ),
            onChanged: (_) => setInnerState(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        controller.text.trim(),
                      ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    // The route (and [TextField]) can rebuild once more after pop while the
    // IME closes; disposing immediately triggers "used after disposed" and
    // cascades to InheritedWidget / build-scope asserts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    return result;
  }

  static Future<bool> _ensureEntitled({
    required BuildContext context,
    required AppRepository repository,
  }) async {
    await repository.refreshBusinessEntitlement();
    var access = await repository.fetchBusinessAccessState();
    if (access.entitlementActive) return true;

    await BusinessEntitlementService.instance.presentPaywallForExplicitUpgrade();
    await repository.refreshBusinessEntitlement();
    access = await repository.fetchBusinessAccessState();
    if (access.entitlementActive) return true;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Business access requires an active subscription.',
          ),
        ),
      );
    }
    return false;
  }

  static Future<String?> _pickBusinessWorkspace({
    required BuildContext context,
    required List<Map<String, dynamic>> organizations,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose Business'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final workspace in organizations)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.apartment_rounded),
                    title: Text((workspace['label'] ?? 'Business').toString()),
                    subtitle: Text(
                      'Role: ${(workspace['role'] ?? 'owner').toString()}',
                    ),
                    onTap: () => Navigator.pop(
                      dialogContext,
                      workspace['organization_id']?.toString(),
                    ),
                  ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_business_rounded),
                  title: const Text('Create another business'),
                  onTap: () => Navigator.pop(
                    dialogContext,
                    _createBusinessChoice,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
