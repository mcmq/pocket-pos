import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pos/core/database/app_database.dart';

void main() {
  test('v1 → v2 adds shops.logo_local_path and keeps rows', () async {
    final db = AppDatabase(DatabaseConnection(
      NativeDatabase.memory(setup: (raw) {
        // The v1 shops table (no logo_local_path) with one row.
        raw.execute('''
          CREATE TABLE shops (
            id TEXT NOT NULL PRIMARY KEY, shop_id TEXT NOT NULL,
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
            deleted_at INTEGER NULL, version INTEGER NOT NULL DEFAULT 1,
            sync_status TEXT NOT NULL DEFAULT 'pending', device_id TEXT NOT NULL,
            name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '',
            tax_id TEXT NOT NULL DEFAULT '', currency_code TEXT NOT NULL DEFAULT 'USD',
            currency_symbol TEXT NOT NULL DEFAULT '\$', currency_position TEXT NOT NULL DEFAULT 'start',
            decimal_places INTEGER NOT NULL DEFAULT 2, logo_url TEXT NULL,
            receipt_header TEXT NOT NULL DEFAULT '',
            receipt_footer TEXT NOT NULL DEFAULT 'Thank you for your purchase!',
            owner_uid TEXT NULL)''');
        raw.execute(
          "INSERT INTO shops (id, shop_id, created_at, updated_at, device_id, name) "
          "VALUES ('s1', 's1', 1, 1, 'd1', 'Corner Café')",
        );
        raw.execute('PRAGMA user_version = 1');
      }),
      closeStreamsSynchronously: true,
    ));
    addTearDown(db.close);

    final shop = await db.select(db.shops).getSingle();
    expect(shop.name, 'Corner Café');
    expect(shop.logoLocalPath, isNull);
    await db.update(db.shops).replace(shop.copyWith(logoLocalPath: const Value('images/logo.jpg')));
    expect((await db.select(db.shops).getSingle()).logoLocalPath, 'images/logo.jpg');
  });
}
