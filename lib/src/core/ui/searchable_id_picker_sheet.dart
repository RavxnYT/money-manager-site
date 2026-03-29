import 'package:flutter/material.dart';

/// Full-screen-ish bottom sheet: search field + scrollable list; returns chosen id.
Future<String?> showSearchableIdPickerSheet(
  BuildContext context, {
  required String title,
  required String searchHint,
  required List<Map<String, dynamic>> items,
  required String Function(Map<String, dynamic> row) itemTitle,
  required bool Function(Map<String, dynamic> row, String query) matches,
  String? selectedId,
  Widget? Function(Map<String, dynamic> row)? leadingForRow,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.58,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (ctx, scrollController) {
          return _SearchableIdPickerBody(
            title: title,
            searchHint: searchHint,
            items: items,
            itemTitle: itemTitle,
            matches: matches,
            selectedId: selectedId,
            leadingForRow: leadingForRow,
            scrollController: scrollController,
          );
        },
      );
    },
  );
}

class _SearchableIdPickerBody extends StatefulWidget {
  const _SearchableIdPickerBody({
    required this.title,
    required this.searchHint,
    required this.items,
    required this.itemTitle,
    required this.matches,
    required this.scrollController,
    this.selectedId,
    this.leadingForRow,
  });

  final String title;
  final String searchHint;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic> row) itemTitle;
  final bool Function(Map<String, dynamic> row, String query) matches;
  final ScrollController scrollController;
  final String? selectedId;
  final Widget? Function(Map<String, dynamic> row)? leadingForRow;

  @override
  State<_SearchableIdPickerBody> createState() =>
      _SearchableIdPickerBodyState();
}

class _SearchableIdPickerBodyState extends State<_SearchableIdPickerBody> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      setState(() => _query = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((row) {
      if (_query.isEmpty) return true;
      return widget.matches(row, _query);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            TextField(
              controller: _search,
              autofocus: false,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search, size: 22),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No matches',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final row = filtered[index];
                        final id = row['id']?.toString() ?? '';
                        final selected = id == widget.selectedId;
                        final leading = widget.leadingForRow?.call(row);
                        return ListTile(
                          dense: true,
                          leading: leading,
                          title: Text(widget.itemTitle(row)),
                          trailing: selected
                              ? Icon(
                                  Icons.check,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picker for plain string values (e.g. currency codes).
Future<String?> showSearchableStringPickerSheet(
  BuildContext context, {
  required String title,
  required String searchHint,
  required List<String> values,
  required bool Function(String value, String query) matches,
  String? selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.58,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (ctx, scrollController) {
          return _SearchableStringPickerBody(
            title: title,
            searchHint: searchHint,
            values: values,
            matches: matches,
            selected: selected,
            scrollController: scrollController,
          );
        },
      );
    },
  );
}

class _SearchableStringPickerBody extends StatefulWidget {
  const _SearchableStringPickerBody({
    required this.title,
    required this.searchHint,
    required this.values,
    required this.matches,
    required this.scrollController,
    this.selected,
  });

  final String title;
  final String searchHint;
  final List<String> values;
  final bool Function(String value, String query) matches;
  final ScrollController scrollController;
  final String? selected;

  @override
  State<_SearchableStringPickerBody> createState() =>
      _SearchableStringPickerBodyState();
}

class _SearchableStringPickerBodyState extends State<_SearchableStringPickerBody> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      setState(() => _query = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.values.where((v) {
      if (_query.isEmpty) return true;
      return widget.matches(v, _query);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            TextField(
              controller: _search,
              autofocus: false,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search, size: 22),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No matches',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final v = filtered[index];
                        final selected = v == widget.selected;
                        return ListTile(
                          dense: true,
                          title: Text(v),
                          trailing: selected
                              ? Icon(
                                  Icons.check,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, v),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
