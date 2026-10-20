import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../utils/money.dart';

const _uuid = Uuid();

/// New client-generated UUID v4 for a synced row.
String newId() => _uuid.v4();

int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// Overridden in `main()` with the opened database.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

/// Settings rows loaded before `runApp`, so the first frame has the theme.
final initialSettingsProvider = Provider<Map<String, String>>(
  (ref) => throw UnimplementedError('initialSettingsProvider must be overridden'),
);

/// Whether Firebase was initialised (keys present in `.env`).
final firebaseReadyProvider = Provider<bool>((ref) => false);

/// Keys of the local `settings` table.
abstract final class SettingKeys {
  static const shopId = 'shop_id';
  static const deviceId = 'device_id';
  static const theme = 'theme';
  static const textSize = 'text_size';
  static const language = 'language';
  static const dateFormat = 'date_format';
  static const timeFormat = 'time_format';
  static const numberGrouping = 'number_grouping';
  static const invoicePrefix = 'invoice_prefix';
  static const invoiceSeq = 'invoice_seq';
  static const lastSyncAt = 'last_sync_at';
  static String cursor(String collection) => 'cursor_$collection';
}

/// Loads all settings, creating a device id on first launch.
Future<Map<String, String>> loadSettings(AppDatabase db) async {
  final rows = await db.select(db.settings).get();
  final map = {for (final r in rows) r.key: r.value};
  if (!map.containsKey(SettingKeys.deviceId)) {
    final id = newId();
    await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: SettingKeys.deviceId, value: id),
        );
    map[SettingKeys.deviceId] = id;
  }
  return map;
}

/// Device preferences (local only). Write-through to SQLite.
class SettingsController extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => ref.read(initialSettingsProvider);

  Future<void> set(String key, String value) async {
    final db = ref.read(databaseProvider);
    await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
    state = {...state, key: value};
  }

  Future<void> remove(String key) async {
    final db = ref.read(databaseProvider);
    await (db.delete(db.settings)..where((s) => s.key.equals(key))).go();
    state = {...state}..remove(key);
  }

  /// Re-reads settings changed directly in the DB (e.g. invoice_seq bumped
  /// inside a sale transaction).
  Future<void> reload() async {
    final rows = await ref.read(databaseProvider).select(ref.read(databaseProvider).settings).get();
    state = {for (final r in rows) r.key: r.value};
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, Map<String, String>>(SettingsController.new);

final themeModeProvider = Provider<ThemeMode>((ref) {
  return switch (ref.watch(settingsProvider)[SettingKeys.theme]) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

final textScaleProvider = Provider<double>((ref) {
  return switch (ref.watch(settingsProvider)[SettingKeys.textSize]) {
    'small' => 0.9,
    'large' => 1.15,
    _ => 1.0,
  };
});

final shopIdProvider = Provider<String?>(
  (ref) => ref.watch(settingsProvider)[SettingKeys.shopId],
);

final currentShopProvider = StreamProvider<Shop?>((ref) {
  final shopId = ref.watch(shopIdProvider);
  if (shopId == null) return Stream.value(null);
  final db = ref.watch(databaseProvider);
  return (db.select(db.shops)..where((s) => s.id.equals(shopId)))
      .watchSingleOrNull();
});

/// Who is writing: the tenant and device stamped on every synced row.
class Session {
  const Session({required this.shopId, required this.deviceId, this.userId});

  final String shopId;
  final String deviceId;
  final String? userId;
}

/// Only valid once a shop exists (the router guarantees this for app screens).
final sessionProvider = Provider<Session>((ref) {
  final settings = ref.watch(settingsProvider);
  final shopId = settings[SettingKeys.shopId];
  if (shopId == null) throw StateError('No shop yet: finish setup first.');
  return Session(shopId: shopId, deviceId: settings[SettingKeys.deviceId]!);
});

final moneyFormatProvider = Provider<MoneyFormat>((ref) {
  final shop = ref.watch(currentShopProvider).value;
  final grouping = ref.watch(settingsProvider)[SettingKeys.numberGrouping] == 'indian'
      ? NumberGrouping.indian
      : NumberGrouping.western;
  if (shop == null) return MoneyFormat(grouping: grouping);
  return MoneyFormat(
    symbol: shop.currencySymbol,
    position: shop.currencyPosition == 'end' ? SymbolPosition.end : SymbolPosition.start,
    decimalPlaces: shop.decimalPlaces,
    grouping: grouping,
  );
});

/// Date / time formatting following the user's settings.
class AppFormats {
  AppFormats({required String datePattern, required bool use24h})
      : date = DateFormat(datePattern),
        time = use24h ? DateFormat('HH:mm') : DateFormat('h:mm a');

  final DateFormat date;
  final DateFormat time;

  String dateMs(int ms) => date.format(DateTime.fromMillisecondsSinceEpoch(ms));
  String dateTimeMs(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${date.format(d)} · ${time.format(d)}';
  }
}

const dateFormatOptions = ['dd MMM yyyy', 'dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd'];

final formatsProvider = Provider<AppFormats>((ref) {
  final s = ref.watch(settingsProvider);
  return AppFormats(
    datePattern: s[SettingKeys.dateFormat] ?? dateFormatOptions.first,
    use24h: s[SettingKeys.timeFormat] == '24h',
  );
});

/// Number of changes waiting to sync.
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  final count = db.outbox.id.count();
  return (db.selectOnly(db.outbox)..addColumns([count]))
      .map((row) => row.read(count) ?? 0)
      .watchSingle();
});
