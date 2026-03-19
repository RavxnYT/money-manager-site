import 'package:flutter/material.dart';

import '../../core/categories/category_icon_utils.dart';
import '../../core/friendly_error.dart';
import '../../core/ui/app_page_scaffold.dart';
import '../../core/ui/glass_panel.dart';
import '../../data/app_repository.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String _type = 'expense';
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchCategories(_type);
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.repository.fetchCategories(_type);
    });
  }

  Future<void> _createCategory() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:
            Text('New ${_type[0].toUpperCase()}${_type.substring(1)} Category'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      await widget.repository
          .createCategory(name: controller.text.trim(), type: _type);
      _reload();
    }
  }

  Future<void> _editCategory(Map<String, dynamic> category) async {
    final controller =
        TextEditingController(text: (category['name'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Category'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      await widget.repository.updateCategory(
        categoryId: category['id'].toString(),
        name: controller.text.trim(),
      );
      _reload();
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
      appBar: AppBar(
        title: const Text('Manage Categories'),
      ),
      body: AppPageScaffold(
        child: Column(
          children: [
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
                        final icon = categoryIconFor(
                          name: item['name']?.toString(),
                          type: itemType,
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
                                color: (_type == 'expense'
                                        ? const Color(0xFFFF6B86)
                                        : const Color(0xFF3BD188))
                                    .withOpacity(0.2),
                              ),
                              child: Icon(
                                icon,
                                color: _type == 'expense'
                                    ? const Color(0xFFFF6B86)
                                    : const Color(0xFF3BD188),
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
                                color: Colors.white.withOpacity(0.08),
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
