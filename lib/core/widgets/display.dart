import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/image_store.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/pricing.dart';
import 'app_scaffold.dart';

/// Horizontal scrolling filter chips. Selected chip is `surfaceTint` with
/// primary text.
class CategoryChips<T> extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.outline),
        ),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(4),
          itemCount: options.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (context, i) {
            final o = options[i];
            final isSelected = o.value == selected;
            return Semantics(
              selected: isSelected,
              button: true,
              child: Material(
                color: isSelected ? c.surfaceTint : Colors.transparent,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onSelected(o.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: Text(
                        o.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? c.primary : c.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Small rounded label. Always text, never color alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.fg, required this.bg});

  factory StatusBadge.payment(BuildContext context, PaymentStatus status) {
    final c = context.colors;
    return switch (status) {
      PaymentStatus.paid => StatusBadge(label: 'Paid', fg: c.success, bg: c.successBg),
      PaymentStatus.partial => StatusBadge(label: 'Partial', fg: c.warning, bg: c.warningBg),
      PaymentStatus.unpaid => StatusBadge(label: 'Unpaid', fg: c.danger, bg: c.dangerBg),
      PaymentStatus.voided => StatusBadge(label: 'Void', fg: c.textSecondary, bg: c.surfaceTint),
    };
  }

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }
}

/// Category tag on inventory rows ("General").
class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: c.categoryBadgeBg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(label, style: TextStyle(color: c.primary, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }
}

/// Product or logo thumbnail: the local file, else the uploaded copy, else
/// a pastel tint with the initials.
class ProductThumb extends ConsumerWidget {
  const ProductThumb({
    super.key,
    required this.name,
    required this.seed,
    this.size = 48,
    this.imagePath,
    this.imageUrl,
    this.file,
  });

  final String name;
  final String seed;
  final double size;

  /// Stored local image, relative to the documents dir ([ImageStore]).
  final String? imagePath;

  /// Uploaded copy, used when this device has no local file.
  final String? imageUrl;

  /// An absolute file to show instead, e.g. a photo picked but not saved.
  final File? file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final radius = BorderRadius.circular(size * 0.25);
    final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = Center(
      child: Text(
        words.isEmpty ? '?' : words.take(2).map((w) => w.characters.first.toUpperCase()).join(),
        style: TextStyle(fontSize: size * 0.32, fontWeight: FontWeight.w600, color: c.primary),
      ),
    );
    final url = imageUrl;
    final network = url == null || url.isEmpty
        ? initials
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: cachePx,
            placeholder: (_, _) => initials,
            errorWidget: (_, _, _) => initials,
          );
    final local = file ?? ref.watch(imageStoreProvider).resolve(imagePath);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.tintFor(seed), borderRadius: radius),
      foregroundDecoration: BoxDecoration(borderRadius: radius, border: Border.all(color: c.outline)),
      child: local == null
          ? network
          : Image.file(
              local,
              fit: BoxFit.cover,
              cacheWidth: cachePx,
              // Missing file (e.g. restored backup): fall back to the URL.
              errorBuilder: (_, _, _) => network,
            ),
    );
  }
}

/// Card with a calendar icon, the current period label and a "Change" pill.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key, required this.label, required this.onChange});

  final String label;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      radius: AppRadius.pill,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: c.surfaceTint, shape: BoxShape.circle),
            child: Icon(Icons.calendar_today_outlined, size: 18, color: c.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
          OutlinedButton.icon(
            onPressed: onChange,
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('Change'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              foregroundColor: c.primary,
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Sale #1 · Cash Sale · date · amount · status".
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.typeLabel,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.status,
    this.onTap,
  });

  final String typeLabel;
  final String title;
  final String subtitle;
  final String amount;
  final PaymentStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(typeLabel, style: text.labelSmall?.copyWith(color: c.primary)),
                  const SizedBox(height: 2),
                  Text(title, style: text.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle, style: text.labelSmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: AppText.amount(context).copyWith(
                    decoration: status == PaymentStatus.voided ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 6),
                StatusBadge.payment(context, status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// KPI card: icon, label, big value and a comparison caption.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.icon, required this.label, required this.value, this.caption});

  final IconData icon;
  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: c.surfaceTint, shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: c.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: text.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppText.amount(context, size: 22)),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption!, style: text.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

/// Square outlined card with an icon in a soft circle and a label below.
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.label, this.onTap, this.badge});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// e.g. "Soon" for P1 features.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.surfaceTint, shape: BoxShape.circle),
              child: Icon(icon, color: c.primary, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            if (badge != null) ...[
              const SizedBox(height: 4),
              Text(badge!, style: Theme.of(context).textTheme.labelSmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Leading icon, label, trailing value + chevron, or a switch.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.switchValue,
    this.onSwitch,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final isSwitch = switchValue != null;
    return InkWell(
      onTap: isSwitch ? () => onSwitch?.call(!switchValue!) : onTap,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 20, color: c.textPrimary),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: text.bodyLarge?.copyWith(fontSize: 14))),
              if (value != null)
                Flexible(
                  child: Text(
                    value!,
                    style: text.bodyMedium,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (isSwitch)
                Switch(value: switchValue!, onChanged: onSwitch)
              else if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: c.textSecondary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Card grouping several [SettingsTile]s with dividers.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 12, endIndent: 12),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Label / amount row used in totals blocks.
class AmountRow extends StatelessWidget {
  const AmountRow({super.key, required this.label, required this.amount, this.emphasize = false, this.color});

  final String label;
  final String amount;
  final bool emphasize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: emphasize ? text.bodyLarge : text.bodyMedium?.copyWith(fontSize: 14)),
          ),
          Text(
            amount,
            style: AppText.amount(
              context,
              size: emphasize ? 17 : 14,
              color: color ?? (emphasize ? context.colors.primary : null),
            ),
          ),
        ],
      ),
    );
  }
}
