import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'buttons.dart';

/// Gradient background, safe area and an optional [AppTopBar].
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.title,
    this.showBack = false,
    this.leading,
    this.trailing,
    required this.body,
    this.bottom,
    this.floatingActionButton,
    this.padBody = true,
  });

  final String? title;
  final bool showBack;
  final Widget? leading;
  final Widget? trailing;
  final Widget body;

  /// Pinned below the body (action bars, Cancel / Save rows).
  final Widget? bottom;
  final Widget? floatingActionButton;
  final bool padBody;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.backgroundBottom,
      floatingActionButton: floatingActionButton,
      resizeToAvoidBottomInset: true,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.backgroundTop, c.backgroundBottom],
            stops: const [0, 0.45],
          ),
        ),
        child: SafeArea(
          bottom: bottom == null,
          child: Column(
            children: [
              if (title != null || showBack || leading != null || trailing != null)
                AppTopBar(title: title, showBack: showBack, leading: leading, trailing: trailing),
              Expanded(
                child: padBody
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.screen),
                        child: body,
                      )
                    : body,
              ),
              if (bottom != null)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.screen,
                      AppSpace.sm,
                      AppSpace.screen,
                      AppSpace.md,
                    ),
                    child: bottom,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular back button on the left, centered title, optional trailing action.
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, this.title, this.showBack = false, this.leading, this.trailing});

  final String? title;
  final bool showBack;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final lead = leading ??
        (showBack
            ? CircleIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onPressed: () => context.canPop() ? context.pop() : context.go('/sell'),
              )
            : null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.sm, AppSpace.screen, AppSpace.md),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Text(
                  title!,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (lead != null) Align(alignment: Alignment.centerLeft, child: lead),
            if (trailing != null) Align(alignment: Alignment.centerRight, child: trailing),
          ],
        ),
      ),
    );
  }
}

/// White rounded card with a hairline border.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.onTap,
    this.color,
    this.radius = AppRadius.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: c.outline),
    );
    return Material(
      color: color ?? c.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Section header ("Sales Transactions").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.sm),
      child: Row(
        children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Centered icon + message for empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: c.surfaceTint, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: c.primary),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(message!, style: text.bodyMedium, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: AppSpace.xl), action!],
          ],
        ),
      ),
    );
  }
}

void showAppSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
      content: Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive ? TextButton.styleFrom(foregroundColor: c.danger) : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
