import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../providers/app_providers.dart';

/// Customers and suppliers. Full party management (balances, ledgers) is P1;
/// for now parties are picked or created at checkout and on Payment In.
class PartyRepository {
  PartyRepository(this._db, this._session);

  final AppDatabase _db;
  final Session _session;

  Stream<List<Party>> watchParties({String query = '', String? type}) {
    return (_db.select(_db.parties)
          ..where((p) {
            Expression<bool> e = p.shopId.equals(_session.shopId) & p.deletedAt.isNull();
            if (type != null) e = e & (p.type.equals(type) | p.type.equals('both'));
            final text = query.trim().replaceAll(RegExp('[%_]'), '');
            if (text.isNotEmpty) e = e & (p.name.like('%$text%') | p.phone.like('%$text%'));
            return e;
          })
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  Future<Party?> byId(String id) =>
      (_db.select(_db.parties)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<Party> create({
    required String name,
    String phone = '',
    String email = '',
    String address = '',
    String type = 'customer',
  }) {
    return _db.transaction(() async {
      final now = nowMs();
      final party = Party(
        id: newId(),
        shopId: _session.shopId,
        createdAt: now,
        updatedAt: now,
        version: 1,
        syncStatus: 'pending',
        deviceId: _session.deviceId,
        type: type,
        name: name.trim(),
        phone: phone.trim(),
        email: email.trim(),
        address: address.trim(),
        openingBalanceMinor: 0,
      );
      await _db.into(_db.parties).insert(party);
      await _db.enqueue('parties', party.id, party.toJson());
      return party;
    });
  }
}

final partyRepositoryProvider = Provider<PartyRepository>(
  (ref) => PartyRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)),
);
