import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/catalog_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/inputs.dart';

/// Categories drive the chips on the sell screen. Drag to reorder.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [ProductCategory? category]) async {
    final controller = TextEditingController(text: category?.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(category == null ? 'New category' : 'Rename category'),
        content: LabeledField(
          label: 'Name',
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await ref.read(catalogRepositoryProvider).saveCategory(id: category?.id, name: name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final categories = ref.watch(categoriesProvider).value ?? const <ProductCategory>[];
    final repo = ref.read(catalogRepositoryProvider);

    return AppScaffold(
      title: 'Categories',
      showBack: true,
      trailing: PillButton(label: 'Add', icon: Icons.add, filled: true, onPressed: () => _edit(context, ref)),
      body: categories.isEmpty
          ? EmptyState(
              icon: Icons.category_outlined,
              title: 'No categories',
              action: PrimaryButton(label: 'Add category', onPressed: () => _edit(context, ref)),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: AppSpace.lg),
              itemCount: categories.length,
              onReorderItem: (from, to) async {
                final list = [...categories];
                list.insert(to, list.removeAt(from));
                for (var i = 0; i < list.length; i++) {
                  if (list[i].sortOrder != i) {
                    await repo.saveCategory(id: list[i].id, name: list[i].name, sortOrder: i);
                  }
                }
              },
              itemBuilder: (context, i) {
                final cat = categories[i];
                return Padding(
                  key: ValueKey(cat.id),
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: AppCard(
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(cat.name, style: Theme.of(context).textTheme.bodyLarge)),
                        IconButton(
                          tooltip: 'Rename',
                          icon: Icon(Icons.edit_outlined, color: c.textSecondary),
                          onPressed: () => _edit(context, ref, cat),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: Icon(Icons.delete_outline, color: c.danger),
                          onPressed: () async {
                            final ok = await confirmDialog(
                              context,
                              title: 'Delete ${cat.name}?',
                              message: 'Its products stay, without a category.',
                              confirmLabel: 'Delete',
                              destructive: true,
                            );
                            if (ok) await repo.deleteCategory(cat.id);
                          },
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(Icons.drag_handle, color: c.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
