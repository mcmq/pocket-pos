import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/buttons.dart';

/// Account, sync status and "Sync now".
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final auth = ref.watch(authServiceProvider);
    final user = ref.watch(authUserProvider).value;
    final status = ref.watch(syncStatusProvider).value ?? const SyncStatus(SyncPhase.idle);
    final pending = ref.watch(pendingSyncCountProvider).value ?? 0;
    final formats = ref.watch(formatsProvider);
    final lastSync = status.lastSyncedAt ??
        switch (int.tryParse(ref.watch(settingsProvider)[SettingKeys.lastSyncAt] ?? '')) {
          final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
          null => null,
        };

    if (!auth.available) {
      return const AppScaffold(
        title: 'Account & sync',
        showBack: true,
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Cloud sync is not configured',
          message: 'This build has no Firebase settings. Your data is safe on this device. See docs/setup.md.',
        ),
      );
    }

    if (user == null) {
      return AppScaffold(
        title: 'Account & sync',
        showBack: true,
        body: EmptyState(
          icon: Icons.cloud_upload_outlined,
          title: 'Back up and sync your shop',
          message: pending > 0
              ? 'You have $pending changes saved only on this device. Sign in to back them up.'
              : 'Sign in to keep a cloud backup and use PocketPOS on several devices.',
          action: PrimaryButton(label: 'Sign in', onPressed: () => context.push('/sign-in')),
        ),
      );
    }

    final (String statusLabel, Color statusColor) = switch (status.phase) {
      SyncPhase.syncing => ('Syncing…', c.primary),
      SyncPhase.error => ('Sync error', c.danger),
      SyncPhase.offline => ('Offline: changes will sync when you reconnect', c.warning),
      _ when pending > 0 => ('$pending changes waiting', c.warning),
      _ => ('All changes synced', c.success),
    };

    return AppScaffold(
      title: 'Account & sync',
      showBack: true,
      body: ListView(
        children: [
          AppCard(
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: c.surfaceTint,
                  child: Icon(Icons.person_outline, color: c.primary),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.email ?? 'Signed in', style: text.bodyLarge),
                      Text('Shop owner', style: text.labelSmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusLabel, style: text.bodyLarge?.copyWith(color: statusColor)),
                if (status.phase == SyncPhase.error && status.error != null) ...[
                  const SizedBox(height: 4),
                  Text(status.error!, style: text.bodyMedium),
                ],
                const SizedBox(height: 4),
                Text(
                  lastSync == null ? 'Never synced' : 'Last synced ${formats.dateTimeMs(lastSync.millisecondsSinceEpoch)}',
                  style: text.labelSmall,
                ),
                const SizedBox(height: AppSpace.md),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'Sync now',
                    icon: Icons.sync,
                    busy: status.phase == SyncPhase.syncing,
                    onPressed: () => ref.read(syncEngineProvider)?.sync(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          SizedBox(
            width: double.infinity,
            child: SecondaryButton(
              label: 'Sign out',
              icon: Icons.logout,
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Sign out?',
                  message: pending > 0
                      ? 'You have $pending changes not yet synced. They stay on this device and sync after you sign in again.'
                      : 'Your data stays on this device. Sync pauses until you sign in again.',
                  confirmLabel: 'Sign out',
                );
                if (ok) await ref.read(authServiceProvider).signOut();
              },
            ),
          ),
        ],
      ),
    );
  }
}
