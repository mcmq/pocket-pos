import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pos/app.dart';
import 'package:pocket_pos/core/database/app_database.dart';
import 'package:pocket_pos/core/providers/app_providers.dart';

Future<void> settle(WidgetTester tester) async {
  // Drift does real async I/O, so alternate real waits with frames.
  // (pumpAndSettle would spin forever on loading indicators.)
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
  });

  // Closed inside the test via runAsync: drift needs real async, and a
  // tearDown close under fake async can hang the runner.
  Future<void> closeDb(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final settings = await tester.runAsync(() => loadSettings(db));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(settings!),
        ],
        child: const PocketPosApp(),
      ),
    );
    await settle(tester);
  }

  testWidgets('offline: set up shop, add a product, sell it, see the receipt', (tester) async {
    await pumpApp(tester);

    // 1. First launch: shop setup.
    expect(find.text('Welcome to PocketPOS'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Corner Café');
    await tester.tap(find.text('Create shop'));
    await settle(tester);

    // 2. Empty sell screen.
    expect(find.text('Corner Café'), findsOneWidget);
    expect(find.text('No products yet'), findsOneWidget);

    // 3. Add a product with opening stock.
    await tester.tap(find.text('Add product'));
    await settle(tester);
    expect(find.text('New Item'), findsOneWidget);
    Finder field(String label) => find.descendant(
          of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
          matching: find.byType(TextFormField),
        );
    await tester.enterText(field('Name'), 'Latte');
    await tester.enterText(field('Sale price'), '4.50');
    await tester.scrollUntilVisible(
      find.text('Opening stock'),
      200,
      scrollable: find.ancestor(of: find.text('Description'), matching: find.byType(Scrollable)).last,
    );
    await tester.enterText(field('Opening stock'), '10');
    await tester.tap(find.text('Save Item'));
    await settle(tester);

    // 4. Tap the product to add it to the cart (twice).
    expect(find.text('Latte'), findsOneWidget);
    await tester.tap(find.text('Latte'));
    await tester.tap(find.text('Latte'));
    await settle(tester);
    expect(find.text('1 Item'), findsOneWidget);
    expect(find.text(r'$9.00'), findsOneWidget);

    // 5. Checkout in two taps: Next → Save Sale.
    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(find.text('Confirm Sale'), findsOneWidget);
    expect(find.text('A-0001'), findsOneWidget);
    expect(find.text('Cash Sale'), findsOneWidget);
    await tester.tap(find.text('Save Sale'));
    await settle(tester);

    // 6. Receipt.
    expect(find.text('Sale saved'), findsOneWidget);
    expect(find.text('Sale A-0001', findRichText: true), findsOneWidget);

    // Stock was decremented in the same transaction.
    final product = await tester.runAsync(() => db.select(db.products).getSingle());
    expect(product!.stockQty, 8);
    final txn = await tester.runAsync(() => db.select(db.transactions).getSingle());
    expect(txn!.totalMinor, 900);
    expect(txn.status, 'paid');

    await closeDb(tester);
  });
}
