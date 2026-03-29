import 'package:flutter/material.dart';

import '../../core/billing/business_access.dart';
import '../../core/config/business_features_config.dart';
import '../../core/categories/category_branding.dart';
import '../../core/categories/category_icon_utils.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';
import '../settings/business_mode_flow.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
    super.key,
    required this.repository,
    this.showAppBar = true,
  });

  final AppRepository repository;
  final bool showAppBar;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String _type = 'expense';
  late Future<List<Map<String, dynamic>>> _future;
  BusinessAccessState _businessAccess = const BusinessAccessState();

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchCategories(_type);
    _loadBusinessAccess();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.repository.fetchCategories(_type);
    });
  }

  Future<_CategoryDraft?> _showCategoryDialog({
    Map<String, dynamic>? initialCategory,
  }) async {
    final controller = TextEditingController(
      text: (initialCategory?['name'] ?? '').toString(),
    );
    var selectedIconKey = initialCategory?['icon']?.toString();
    var selectedColorHex =
        normalizeCategoryColorHex(initialCategory?['color_hex']?.toString());

    return showDialog<_CategoryDraft>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setInnerState) => AlertDialog(
          title: Text(
            initialCategory == null
                ? 'New ${_type[0].toUpperCase()}${_type.substring(1)} Category'
                : 'Edit Category',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  onChanged: (_) => setInnerState(() {}),
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 14),
                if (_businessAccess.canCustomizeCategoryBranding) ...[
                  Text(
                    'Business branding',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: businessCategoryIconChoices.entries.map((entry) {
                      final selected = selectedIconKey == entry.key;
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setInnerState(() {
                          selectedIconKey =
                              selected ? null : entry.key;
                        }),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: selected
                                ? const Color(0xFF8EA2FF).withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.06),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF8EA2FF)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Icon(
                            entry.value,
                            color: selected
                                ? const Color(0xFF8EA2FF)
                                : Colors.white,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Color',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ...businessCategoryColorPalette.map((hex) {
                        final color = categoryColorFromHex(hex)!;
                        final selected = selectedColorHex == hex;
                        return InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => setInnerState(() {
                            selectedColorHex = selected ? null : hex;
                          }),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                              border: Border.all(
                                color: selected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.24),
                                width: selected ? 2.5 : 1,
                              ),
                            ),
                            child: selected
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        );
                      }),
                      OutlinedButton(
                        onPressed: () => setInnerState(() {
                          selectedColorHex = null;
                        }),
                        child: const Text('Default'),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    BusinessFeaturesConfig.isEnabled
                        ? 'Business Pro unlocks custom category icons and colors.'
                        : 'Custom icons and colors are not available in this version of the app.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                        context,
                        _CategoryDraft(
                          name: controller.text.trim(),
                          iconKey: _businessAccess.canCustomizeCategoryBranding
                              ? selectedIconKey
                              : null,
                          colorHex: _businessAccess.canCustomizeCategoryBranding
                              ? selectedColorHex
                              : null,
                        ),
                      ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadBusinessAccess() async {
    final access = await widget.repository.fetchBusinessAccessState();
    if (!mounted) return;
    setState(() => _businessAccess = access);
  }

  Future<void> _enableBusinessMode() async {
    await BusinessModeFlow.enableBusinessMode(
      context: context,
      repository: widget.repository,
    );
    await _loadBusinessAccess();
  }

  Future<void> _createCategory() async {
    final draft = await _showCategoryDialog();
    if (draft == null) return;

    try {
      await widget.repository.createCategory(
        name: draft.name,
        type: _type,
        iconKey: draft.iconKey,
        colorHex: draft.colorHex,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }

  Future<void> _editCategory(Map<String, dynamic> category) async {
    final draft = await _showCategoryDialog(initialCategory: category);
    if (draft == null) return;

    try {
      await widget.repository.updateCategory(
        categoryId: category['id'].toString(),
        name: draft.name,
        iconKey: draft.iconKey,
        colorHex: draft.colorHex,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> category) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Delete "${category['name']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await widget.repository.deleteCategory(
        categoryId: category['id'].toString(),
      );
      _reload();
    }
  }

  Future<void> _showCategoryActions(Map<String, dynamic> category) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit category'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete category'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'edit') {
      await _editCategory(category);
    } else if (action == 'delete') {
      await _deleteCategory(category);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Manage Categories'),
            )
          : null,
      body: AppPageScaffold(
        child: Column(
          children: [
            if (BusinessFeaturesConfig.isEnabled &&
                !_businessAccess.canCustomizeCategoryBranding)
              GlassPanel(
                margin: const EdgeInsets.fromLTRB(2, 12, 2, 0),
                child: ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text('Business Pro feature'),
                  subtitle: const Text(
                    'Custom category icons and colors unlock with Business Pro.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _enableBusinessMode,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Expense')),
                  ButtonSegment(value: 'income', label: Text('Income')),
                ],
                selected: {_type},
                onSelectionChanged: (selected) {
                  _type = selected.first;
                  _reload();
                },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return ListView(children: [
                        Center(
                            child: Text(friendlyErrorMessage(snapshot.error)))
                      ]);
                    }
                    final items = snapshot.data ?? [];
                    if (items.isEmpty) {
                      return ListView(children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No categories'))
                      ]);
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 108),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final itemType =
                            (item['type'] ?? _type).toString().toLowerCase();
                        final accent = categoryColorFromHex(
                              item['color_hex']?.toString(),
                            ) ??
                            (itemType == 'expense'
                                ? const Color(0xFFFF6B86)
                                : const Color(0xFF3BD188));
                        final icon = categoryIconFor(
                          name: item['name']?.toString(),
                          type: itemType,
                          iconKey: item['icon']?.toString(),
                        );
                        return GlassPanel(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 2, vertical: 6),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            leading: Container(
                              height: 36,
                              width: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(11),
                                color: accent.withValues(alpha: 0.2),
                              ),
                              child: Icon(
                                icon,
                                color: accent,
                              ),
                            ),
                            title: Text(item['name'] as String? ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(30),
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                              child: Text(_type.toUpperCase(),
                                  style: const TextStyle(fontSize: 11)),
                            ),
                            onTap: () => _editCategory(item),
                            onLongPress: () => _showCategoryActions(item),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCategory,
        label: const Text('Add'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class _CategoryDraft {
  const _CategoryDraft({
    required this.name,
    this.iconKey,
    this.colorHex,
  });

  final String name;
  final String? iconKey;
  final String? colorHex;
}
