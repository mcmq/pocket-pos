import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/account_screen.dart';
import '../../features/auth/presentation/setup_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/inventory/presentation/categories_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/inventory/presentation/product_form_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/sell/presentation/checkout_screen.dart';
import '../../features/sell/presentation/scan_screen.dart';
import '../../features/sell/presentation/sell_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/shop_settings_screens.dart';
import '../../features/transactions/presentation/payment_in_screen.dart';
import '../../features/transactions/presentation/receipt_screen.dart';
import '../../features/transactions/presentation/transaction_detail_screen.dart';
import '../../features/transactions/presentation/transactions_screen.dart';
import '../l10n/app_localizations.dart';
import '../providers/app_providers.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav_pill.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Routes. App screens require a shop; until one exists only setup and
/// sign-in are reachable.
final routerProvider = Provider<GoRouter>((ref) {
  final hasShop = ValueNotifier<bool>(ref.read(shopIdProvider) != null);
  ref.listen(shopIdProvider, (_, next) => hasShop.value = next != null);
  ref.onDispose(hasShop.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/sell',
    refreshListenable: hasShop,
    redirect: (context, state) {
      final path = state.uri.path;
      final onboarding = path == '/setup' || path == '/sign-in';
      if (!hasShop.value && !onboarding) return '/setup';
      if (hasShop.value && onboarding && path == '/setup') return '/sell';
      if (hasShop.value && path == '/sign-in' && state.uri.queryParameters['restore'] == '1') return '/sell';
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      GoRoute(
        path: '/sign-in',
        builder: (_, s) => SignInScreen(restore: s.uri.queryParameters['restore'] == '1'),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/sell', builder: (_, _) => const SellScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/inventory', builder: (_, _) => const InventoryScreen())]),
          StatefulShellBranch(
            routes: [GoRoute(path: '/transactions', builder: (_, _) => const TransactionsScreen())],
          ),
          StatefulShellBranch(routes: [GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())]),
        ],
      ),
      GoRoute(path: '/scan', parentNavigatorKey: _rootKey, builder: (_, _) => const ScanScreen()),
      GoRoute(path: '/checkout', parentNavigatorKey: _rootKey, builder: (_, _) => const CheckoutScreen()),
      GoRoute(
        path: '/receipt/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ReceiptScreen(
          txnId: s.pathParameters['id']!,
          justSold: s.uri.queryParameters['new'] == '1',
        ),
      ),
      GoRoute(
        path: '/products/new',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ProductFormScreen(barcode: s.uri.queryParameters['barcode']),
      ),
      GoRoute(
        path: '/products/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ProductFormScreen(productId: s.pathParameters['id']),
      ),
      GoRoute(path: '/categories', parentNavigatorKey: _rootKey, builder: (_, _) => const CategoriesScreen()),
      GoRoute(
        path: '/transactions/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => TransactionDetailScreen(txnId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/payment-in',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => PaymentInScreen(saleId: s.uri.queryParameters['saleId']),
      ),
      GoRoute(path: '/settings/shop', parentNavigatorKey: _rootKey, builder: (_, _) => const ShopDetailsScreen()),
      GoRoute(
        path: '/settings/currency',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const CurrencySettingsScreen(),
      ),
      GoRoute(path: '/settings/taxes', parentNavigatorKey: _rootKey, builder: (_, _) => const TaxRatesScreen()),
      GoRoute(path: '/settings/account', parentNavigatorKey: _rootKey, builder: (_, _) => const AccountScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _AppShell extends StatelessWidget {
  const _AppShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      // Screens end above the floating nav, so FABs and list ends stay visible.
      backgroundColor: context.colors.backgroundBottom,
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomNavPill(
          index: shell.currentIndex,
          onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          items: [
            NavPillItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: l10n.navSell),
            NavPillItem(icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2, label: l10n.navInventory),
            NavPillItem(icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: l10n.navTransactions),
            NavPillItem(icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, label: l10n.navReports),
            NavPillItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, label: l10n.navSettings),
          ],
        ),
      ),
    );
  }
}
