import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../core/constants/category_styles.dart';
import '../../../models/category/expense_category.dart';
import '../../../providers/ai_providers.dart';
import '../../../providers/categories/category_providers.dart';
import '../../../widgets/common/glass.dart';

/// Settings screen for managing expense categories: add, rename, restyle,
/// and delete. Icons/colors can be auto-suggested by Gemini or picked by hand.
class ManageCategoriesScreen extends ConsumerWidget {
  const ManageCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Manage Categories'), elevation: 0),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add category'),
      ),
      body: SlidableAutoCloseBehavior(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final isProtected = category.name == kProtectedCategoryName;
            final count = ref
                .read(categoriesProvider.notifier)
                .usageCount(category.name);

            return _CategoryRow(
              category: category,
              usageCount: count,
              isProtected: isProtected,
              onEdit: () => _openEditor(context, ref, existing: category),
              onDelete: isProtected
                  ? null
                  : () => _confirmDelete(context, ref, category.name),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    ExpenseCategory? existing,
  }) async {
    final result = await showDialog<ExpenseCategory>(
      context: context,
      builder: (_) => _CategoryEditorDialog(existing: existing),
    );
    if (result == null || !context.mounted) return;

    final notifier = ref.read(categoriesProvider.notifier);
    if (existing == null) {
      if (notifier.exists(result.name)) {
        _snack(context, 'A category named "${result.name}" already exists.');
        return;
      }
      await notifier.addCategory(
        name: result.name,
        iconKey: result.iconKey,
        colorHex: result.colorHex,
      );
      return;
    }

    // Editing: rename first (migrates records), then apply style to new name.
    if (result.name != existing.name) {
      if (existing.name == kProtectedCategoryName) {
        _snack(context, '"$kProtectedCategoryName" cannot be renamed.');
      } else if (notifier.exists(result.name)) {
        _snack(context, 'A category named "${result.name}" already exists.');
        return;
      } else {
        await notifier.renameCategory(existing.name, result.name);
      }
    }
    await notifier.updateStyle(
      result.name,
      iconKey: result.iconKey,
      colorHex: result.colorHex,
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final count = ref.read(categoriesProvider.notifier).usageCount(name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: Text(
          count == 0
              ? 'This category is not used by any records.'
              : '$count record${count == 1 ? '' : 's'} using this category '
                    'will be moved to "$kProtectedCategoryName".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(categoriesProvider.notifier).deleteCategory(name);
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// A glass category row with a tinted icon and swipe actions (edit / delete).
class _CategoryRow extends StatelessWidget {
  final ExpenseCategory category;
  final int usageCount;
  final bool isProtected;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _CategoryRow({
    required this.category,
    required this.usageCount,
    required this.isProtected,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = CategoryStyles.of(category.name);
    final subtitle = isProtected
        ? 'Default category'
        : usageCount == 0
        ? 'Unused'
        : '$usageCount ${usageCount == 1 ? 'expense' : 'expenses'}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: onDelete == null ? 0.28 : 0.5,
          children: [
            SlidableAction(
              onPressed: (_) => onEdit(),
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
              icon: Icons.edit_rounded,
              label: 'Edit',
              borderRadius: BorderRadius.circular(14),
            ),
            if (onDelete != null)
              SlidableAction(
                onPressed: (_) => onDelete!(),
                backgroundColor: cs.error,
                foregroundColor: Colors.white,
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                borderRadius: BorderRadius.circular(14),
              ),
          ],
        ),
        child: GlassCard(
          onTap: onEdit,
          radius: 14,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(style.icon, size: 20, color: style.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isProtected)
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add / edit dialog for a single category (name + icon + color).
class _CategoryEditorDialog extends ConsumerStatefulWidget {
  final ExpenseCategory? existing;

  const _CategoryEditorDialog({this.existing});

  @override
  ConsumerState<_CategoryEditorDialog> createState() =>
      _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends ConsumerState<_CategoryEditorDialog> {
  late final TextEditingController _nameController;
  late String _iconKey;
  late String _colorHex;
  bool _suggesting = false;

  bool get _isProtected =>
      widget.existing?.name == kProtectedCategoryName;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _iconKey = widget.existing?.iconKey ?? 'category';
    _colorHex = widget.existing?.colorHex ??
        CategoryStyles.fallbackHexFor('');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _suggest() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _suggesting = true);
    try {
      final service = ref.read(geminiServiceProvider);
      final suggestion = await service.suggestCategoryStyle(
        name: name,
        iconKeys: CategoryStyles.iconOptions.keys.toList(),
      );
      final icon = suggestion['icon'] ?? '';
      final color = suggestion['color'] ?? '';
      setState(() {
        if (CategoryStyles.iconOptions.containsKey(icon)) _iconKey = icon;
        if (_isValidHex(color)) _colorHex = color;
      });
    } catch (_) {
      // Offline / not configured / bad response: keep manual selection.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get an AI suggestion. Pick manually.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  bool _isValidHex(String value) {
    return RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(value.trim());
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      ExpenseCategory(name: name, iconKey: _iconKey, colorHex: _colorHex),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aiConfigured = ref.watch(geminiConfiguredProvider);
    final previewColor = CategoryStyles.parseHex(_colorHex);

    return AlertDialog(
      title: Text(widget.existing == null ? 'Add category' : 'Edit category'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: previewColor.withValues(alpha: 0.15),
                  child: Icon(
                    CategoryStyles.iconForKey(_iconKey),
                    color: previewColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    enabled: !_isProtected,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      helperText: _isProtected
                          ? 'This default name cannot be changed'
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (aiConfigured)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _suggesting ? null : _suggest,
                  icon: _suggesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Suggest icon & color with AI'),
                ),
              ),
            const SizedBox(height: 8),
            Text('Icon', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: CategoryStyles.iconOptions.entries.map((entry) {
                final selected = entry.key == _iconKey;
                return InkWell(
                  onTap: () => setState(() => _iconKey = entry.key),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: selected
                          ? previewColor.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? previewColor
                            : Theme.of(context).dividerColor,
                      ),
                    ),
                    child: Icon(
                      entry.value,
                      size: 20,
                      color: selected
                          ? previewColor
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text('Color', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CategoryStyles.paletteHex.map((hex) {
                final selected = hex.toUpperCase() == _colorHex.toUpperCase();
                return GestureDetector(
                  onTap: () => setState(() => _colorHex = hex),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: CategoryStyles.parseHex(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _nameController.text.trim().isEmpty ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
