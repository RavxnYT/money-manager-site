import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/app_alert_dialog.dart';
import '../../core/billing/business_entitlement_service.dart';
import '../../core/config/business_features_config.dart';
import '../../core/currency/organization_currency_prompt.dart';
import '../../data/app_repository.dart';

class BusinessModeFlow {
  static const _createBusinessChoice = '__create_business__';
  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.ravxn.moneymanagement';

  /// RevenueCat paywalls only run on Android / iOS; desktop opens this hint instead.
  static Future<void> showDesktopBusinessProHint(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: const Text('Get Business Pro on mobile'),
        content: const Text(
          'Purchases use Google Play or the App Store. Install this app on your '
          'Android phone or iPhone, sign in with the same account, then subscribe '
          'there. Billing screens are not available on Windows, macOS, or Linux.\n\n'
          'You can open the Play Store listing below on this PC.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              final uri = Uri.parse(_playStoreUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Google Play'),
          ),
        ],
      ),
    );
  }

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

    if (!context.mounted) return false;

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

    if (!context.mounted) return false;

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
        builder: (context, setInnerState) => AppAlertDialog(
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

    final billing = BusinessEntitlementService.instance;
    if (!billing.canPresentNativePaywall) {
      if (billing.isDesktopWithoutStoreSdk && context.mounted) {
        await showDesktopBusinessProHint(context);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              billing.lastError ?? 'Billing is not configured on this device.',
            ),
          ),
        );
      }
      return false;
    }

    await billing.presentPaywallForExplicitUpgrade();
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
      builder: (dialogContext) => AppAlertDialog(
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
