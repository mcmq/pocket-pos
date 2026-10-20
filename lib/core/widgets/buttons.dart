import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Full-pill, 48 px primary action.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.icon, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final child = busy
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.onPrimary),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    return FilledButton(onPressed: busy ? null : onPressed, child: child);
  }
}

/// White, outlined pill ("Cancel").
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// `surfaceTint` pill with a leading icon ("+ Add Discount", "Change").
class GhostAddButton extends StatelessWidget {
  const GhostAddButton({super.key, required this.label, this.onPressed, this.icon = Icons.add});

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surfaceTint,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: c.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.primary, fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// White circle with an icon (back, menu, profile). 44 px touch target.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.filled = false,
    this.size = 44,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Filled with primary instead of white.
  final bool filled;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? c.primary : c.surface,
        shape: CircleBorder(side: filled ? BorderSide.none : BorderSide(color: c.outline)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.45, color: color ?? (filled ? c.onPrimary : c.textPrimary)),
          ),
        ),
      ),
    );
  }
}

/// Small filled pill used in top bars ("Add Item").
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, this.onPressed, this.icon, this.filled = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = filled ? c.onPrimary : c.textPrimary;
    return Material(
      color: filled ? c.primary : c.surface,
      shape: StadiumBorder(side: filled ? BorderSide.none : BorderSide(color: c.outline)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 6)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cancel / Save row at the bottom of forms and sheets.
class FormActions extends StatelessWidget {
  const FormActions({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel = 'Cancel',
    this.onSecondary,
    this.busy = false,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final VoidCallback? onSecondary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SecondaryButton(
            label: secondaryLabel,
            onPressed: onSecondary ?? () => Navigator.of(context).maybePop(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: PrimaryButton(label: primaryLabel, onPressed: onPrimary, busy: busy)),
      ],
    );
  }
}
