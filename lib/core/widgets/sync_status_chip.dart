import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_providers.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// ✓ Synced · ⟳ Syncing · ● n pending · ⚠ Sync error. Tapping opens the
/// account & sync screen. Shows sync, never gates on it.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final status = ref.watch(syncStatusProvider).value ?? const SyncStatus(SyncPhase.idle);
    final pending = ref.watch(pendingSyncCountProvider).value ?? 0;

    final (IconData icon, String label, Color color) = switch (status.phase) {
      SyncPhase.disabled => (Icons.cloud_off_outlined, 'Local only', c.textSecondary),
      SyncPhase.signedOut => (Icons.cloud_off_outlined, pending > 0 ? '$pending local' : 'Local only', c.textSecondary),
      SyncPhase.offline => (Icons.wifi_off, pending > 0 ? '$pending pending' : 'Offline', c.warning),
      SyncPhase.syncing => (Icons.sync, 'Syncing', c.primary),
      SyncPhase.error => (Icons.error_outline, 'Sync error', c.danger),
      SyncPhase.idle => pending > 0
          ? (Icons.circle, '$pending pending', c.warning)
          : (Icons.check_circle_outline, 'Synced', c.success),
    };

    return Semantics(
      button: true,
      label: 'Sync status: $label',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: StadiumBorder(side: BorderSide(color: c.outline)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => context.push('/settings/account'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: icon == Icons.circle ? 10 : 16, color: color),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
