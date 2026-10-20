import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

/// Product images and the shop logo on this device. Files live under
/// `<app documents>/images/`; rows store the path relative to the documents
/// dir, because iOS moves the app container between updates.
class ImageStore {
  const ImageStore(this.root);

  /// The app documents dir, or null where there is none (widget tests).
  final Directory? root;

  static const folder = 'images';

  /// The file for a stored relative [path], or null if there isn't one.
  File? resolve(String? path) {
    final dir = root;
    if (dir == null || path == null || path.isEmpty) return null;
    return File('${dir.path}/$path');
  }

  /// Copies the picked file at [sourcePath] into the images folder and
  /// returns its relative path. Each save gets a new name so image caches
  /// never show the previous picture.
  Future<String> save(String sourcePath, String rowId) async {
    final dir = root;
    if (dir == null) throw StateError('No documents directory for images.');
    await Directory('${dir.path}/$folder').create(recursive: true);
    final relative = '$folder/$rowId-${nowMs()}.jpg';
    await File(sourcePath).copy('${dir.path}/$relative');
    return relative;
  }

  /// Removes a file that is no longer referenced. Missing files are fine.
  Future<void> delete(String? path) async {
    final file = resolve(path);
    if (file != null && await file.exists()) await file.delete();
  }
}

/// What a save does to a row's picture (product image or shop logo).
class ImageEdit {
  const ImageEdit.set(String this.localPath) : unchanged = false;
  const ImageEdit._(this.localPath, this.unchanged);

  static const keep = ImageEdit._(null, true);
  static const remove = ImageEdit._(null, false);

  /// New file relative to the documents dir ([ImageStore]); null removes.
  final String? localPath;
  final bool unchanged;
}

/// Overridden in `main.dart` with the real documents dir.
final imageStoreProvider = Provider<ImageStore>((ref) => const ImageStore(null));
