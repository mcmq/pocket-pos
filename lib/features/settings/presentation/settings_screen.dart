import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/inputs.dart';
import '../../../core/widgets/pickers.dart';

/// App Settings: shop, appearance, regional, sales and account groups.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref, {
    required String key,
    required String title,
    required List<({String value, String label})> options,
    required String current,
  }) async {
    final v = await showChoiceSheet<String>(context, title: title, options: options, selected: current);
    if (v != null) await ref.read(settingsProvider.notifier).set(key, v);
  }

  Future<void> _editPrefix(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invoice prefix'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabeledField(label: 'Prefix for this device', controller: controller, autofocus: true),
            const SizedBox(height: 8),
            Text(
              'Each device needs its own prefix (A, B, …) so offline invoice numbers never clash.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    final cleaned = value?.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned != null && cleaned.isNotEmpty) {
      await ref.read(settingsProvider.notifier).set(SettingKeys.invoicePrefix, cleaned);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final shop = ref.watch(currentShopProvider).value;
    final user = ref.watch(authUserProvider).value;
    final money = ref.watch(moneyFormatProvider);

    final theme = s[SettingKeys.theme] ?? 'system';
    final textSize = s[SettingKeys.textSize] ?? 'normal';
    final dateFormat = s[SettingKeys.dateFormat] ?? dateFormatOptions.first;
    final timeFormat = s[SettingKeys.timeFormat] ?? '12h';
    final grouping = s[SettingKeys.numberGrouping] ?? 'western';
    final sample = DateTime(2026, 2, 26, 16, 20);

    const themeOptions = [
      (value: 'system', label: 'System'),
      (value: 'light', label: 'Light Mode'),
      (value: 'dark', label: 'Dark Mode'),
    ];
    const sizeOptions = [
      (value: 'small', label: 'Small'),
      (value: 'normal', label: 'Normal'),
      (value: 'large', label: 'Large'),
    ];
    String labelOf(List<({String value, String label})> o, String v) =>
        o.firstWhere((e) => e.value == v, orElse: () => o.first).label;

    const gap = SizedBox(height: AppSpace.md);
    return AppScaffold(
      title: l10n.navSettings,
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.xl),
        children: [
          SettingsGroup(children: [
            SettingsTile(
              icon: Icons.storefront_outlined,
              label: 'Shop & receipt',
              value: shop?.name,
              onTap: () => context.push('/settings/shop'),
            ),
            SettingsTile(
              icon: Icons.cloud_outlined,
              label: 'Account & sync',
              value: user?.email ?? 'Not signed in',
              onTap: () => context.push('/settings/account'),
            ),
          ]),
          gap,
          SettingsGroup(children: [
            SettingsTile(
              icon: Icons.contrast,
              label: 'Theme',
              value: labelOf(themeOptions, theme),
              onTap: () => _pick(context, ref, key: SettingKeys.theme, title: 'Theme', options: themeOptions, current: theme),
            ),
            SettingsTile(
              icon: Icons.format_size,
              label: 'Text Size',
              value: labelOf(sizeOptions, textSize),
              onTap: () =>
                  _pick(context, ref, key: SettingKeys.textSize, title: 'Text Size', options: sizeOptions, current: textSize),
            ),
            SettingsTile(
              icon: Icons.translate,
              label: 'Language',
              value: 'English',
              onTap: () => showAppSnack(context, 'More languages are coming.'),
            ),
          ]),
          gap,
          SettingsGroup(children: [
            SettingsTile(
              icon: Icons.attach_money,
              label: 'Currency',
              value: shop == null ? null : '${shop.currencyCode} · ${money.format(123456)}',
              onTap: () => context.push('/settings/currency'),
            ),
            SettingsTile(
              icon: Icons.calendar_today_outlined,
              label: 'Date format',
              value: DateFormat(dateFormat).format(sample),
              onTap: () => _pick(
                context,
                ref,
                key: SettingKeys.dateFormat,
                title: 'Date format',
                options: [for (final f in dateFormatOptions) (value: f, label: DateFormat(f).format(sample))],
                current: dateFormat,
              ),
            ),
            SettingsTile(
              icon: Icons.schedule,
              label: 'Time format',
              value: timeFormat == '24h' ? '16:20' : '4:20 PM',
              onTap: () => _pick(
                context,
                ref,
                key: SettingKeys.timeFormat,
                title: 'Time format',
                options: const [(value: '12h', label: '12-hour (4:20 PM)'), (value: '24h', label: '24-hour (16:20)')],
                current: timeFormat,
              ),
            ),
            SettingsTile(
              icon: Icons.pin_outlined,
              label: 'Number Type',
              value: MoneyFormat(
                decimalPlaces: 0,
                grouping: grouping == 'indian' ? NumberGrouping.indian : NumberGrouping.western,
              ).formatAmount(1000000),
              onTap: () => _pick(
                context,
                ref,
                key: SettingKeys.numberGrouping,
                title: 'Number Type',
                options: const [(value: 'western', label: '1,000,000'), (value: 'indian', label: '10,00,000')],
                current: grouping,
              ),
            ),
          ]),
          gap,
          SettingsGroup(children: [
            SettingsTile(
              icon: Icons.percent,
              label: 'Tax rates',
              onTap: () => context.push('/settings/taxes'),
            ),
            SettingsTile(
              icon: Icons.tag,
              label: 'Invoice prefix',
              value: s[SettingKeys.invoicePrefix] ?? 'A',
              onTap: () => _editPrefix(context, ref, s[SettingKeys.invoicePrefix] ?? 'A'),
            ),
          ]),
          gap,
          SettingsGroup(children: [
            SettingsTile(
              icon: Icons.privacy_tip_outlined,
              label: 'About & Privacy Policy',
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'PocketPOS',
                applicationVersion: '1.0.0',
                children: const [
                  Text(
                    'Your sales and inventory are stored on this device. When you sign in, they are '
                    'also backed up to your shop\'s private cloud account so your devices stay in sync. '
                    'PocketPOS does not sell or share your data.',
                  ),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
