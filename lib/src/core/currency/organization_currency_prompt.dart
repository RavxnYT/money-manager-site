import 'package:flutter/material.dart';

import '../ui/app_alert_dialog.dart';
import '../../data/app_repository.dart';
import 'currency_utils.dart';

/// Asks for this business workspace default currency (stored on [organizations]).
Future<void> promptChooseOrganizationCurrency({
  required BuildContext context,
  required AppRepository repository,
  required String organizationId,
}) async {
  String selected = 'USD';
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setInnerState) {
        return AppAlertDialog(
          title: const Text('Business default currency'),
          content: SizedBox(
            width: double.maxFinite,
            child: DropdownButton<String>(
              value: selected,
              isExpanded: true,
              hint: const Text('Currency'),
              items: supportedCurrencyCodes
                  .map(
                    (code) => DropdownMenuItem<String>(
                      value: code,
                      child: Text(code),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setInnerState(() => selected = value);
              },
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );

  if (ok == true && context.mounted) {
    await repository.updateOrganizationCurrency(
      organizationId: organizationId,
      currencyCode: selected,
    );
  }
}
