import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class NavPillItem {
  const NavPillItem({required this.icon, required this.activeIcon, required this.label});
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Floating white bar. The active item is a filled primary circle with a
/// label pill; the others are icon-only circles.
class BottomNavPill extends StatelessWidget {
  const BottomNavPill({super.key, required this.items, required this.index, required this.onTap});

  final List<NavPillItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, AppSpace.sm),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.outline),
        boxShadow: appFloatingShadow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < items.length; i++)
            _NavItem(
              item: items[i],
              active: i == index,
              duration: duration,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.item, required this.active, required this.duration, required this.onTap});

  final NavPillItem item;
  final bool active;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: item.label,
      selected: active,
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: item.label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOut,
            height: 48,
            padding: EdgeInsets.only(right: active ? 14 : 0),
            decoration: BoxDecoration(
              color: active ? c.surfaceTint : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: duration,
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: active ? c.primary : c.surface,
                    shape: BoxShape.circle,
                    border: active ? null : Border.all(color: c.outline),
                  ),
                  child: Icon(
                    active ? item.activeIcon : item.icon,
                    size: 22,
                    color: active ? c.onPrimary : c.textPrimary,
                  ),
                ),
                AnimatedSize(
                  duration: duration,
                  child: active
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            item.label,
                            style: TextStyle(color: c.primary, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
