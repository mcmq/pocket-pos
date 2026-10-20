import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_scaffold.dart';
import 'buttons.dart';
import 'display.dart';

/// Photo row for forms: thumbnail plus add / change / remove. The parent
/// keeps the picked file until the form is saved.
class ImageField extends StatelessWidget {
  const ImageField({
    super.key,
    required this.label,
    required this.name,
    required this.seed,
    required this.onPicked,
    required this.onRemove,
    this.imagePath,
    this.imageUrl,
    this.pickedFile,
  });

  final String label;

  /// Used for the initials placeholder.
  final String name;
  final String seed;

  /// Currently stored image.
  final String? imagePath;
  final String? imageUrl;

  /// Picked in this form but not saved yet; shown instead of the stored one.
  final File? pickedFile;

  final ValueChanged<File> onPicked;
  final VoidCallback? onRemove;

  bool get _hasImage => pickedFile != null || imagePath != null || imageUrl != null;

  Future<void> _pick(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, AppSpace.sm),
            child: Text(label, style: Theme.of(ctx).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: AppSpace.lg),
        ],
      ),
    );
    if (source == null) return;
    try {
      // Downscaled JPEG keeps local files and uploads small.
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked != null) onPicked(File(picked.path));
    } catch (e) {
      if (context.mounted) showAppSnack(context, 'Could not open ${source.name}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ProductThumb(
            name: name,
            seed: seed,
            size: 72,
            file: pickedFile,
            imagePath: pickedFile == null ? imagePath : null,
            imageUrl: pickedFile == null ? imageUrl : null,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
          if (_hasImage && onRemove != null) ...[
            CircleIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Remove photo',
              color: c.danger,
              onPressed: onRemove,
            ),
            const SizedBox(width: AppSpace.sm),
          ],
          GhostAddButton(
            label: _hasImage ? 'Change' : 'Add',
            icon: Icons.add_a_photo_outlined,
            onPressed: () => _pick(context),
          ),
        ],
      ),
    );
  }
}
