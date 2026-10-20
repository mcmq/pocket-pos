import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../providers/app_providers.dart';
import '../utils/period.dart';
import '../utils/pricing.dart';
import 'sale_draft.dart';

/// Transaction type values stored in `transactions.type`.
abstract final class TxnType {
  static const sale = 'sale';
  static const paymentIn = 'payment_in';

  static String label(String type) => switch (type) {
        sale => 'Sale',
        paymentIn => 'Payment In',
        'sale_return' => 'Sale Return',
        'quotation' => 'Quotation',
        'purchase' => 'Purchase',
        'payment_out' => 'Payment Out',
        'expense' => 'Expense',
        _ => type,
      };
}

/// A transaction row with its party name, for lists.
class TxnListItem {
  const TxnListItem(this.txn, this.partyName);
  final Txn txn;
  final String? partyName;

  String get title => partyName ?? (txn.type == TxnType.sale ? 'Cash Sale' : TxnType.label(txn.type));
}

/// Full transaction for detail and receipt screens.
class TxnDetail {
  const TxnDetail({
    required this.txn,
    required this.items,
    required this.payments,
    this.party,
  });

  final Txn txn;
  final List<TxnItem> items;
  final List<Payment> payments;
  final Party? party;

  PaymentStatus get status => PaymentStatus.fromDb(txn.status);
  int get balanceMinor => txn.totalMinor - txn.paidMinor;

  List<({String name, int rateBps, bool inclusive, int amountMinor})> get taxes {
    final map = _breakdown;
    return [
      for (final t in (map['taxes'] as List? ?? const []))
        (
          name: t['name'] as String,
          rateBps: t['rateBps'] as int,
          inclusive: t['inclusive'] as bool,
          amountMinor: t['amountMinor'] as int,
        ),
    ];
  }

  List<ChargeLine> get charges => [
        for (final c in (_breakdown['charges'] as List? ?? const []))
          ChargeLine(label: c['label'] as String, amountMinor: c['amountMinor'] as int),
      ];

  Map<String, dynamic> get _breakdown {
    try {
      return jsonDecode(txn.breakdownJson) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }
}

/// KPIs for a period (docs/features.md §6).
class SalesSummary {
  const SalesSummary({
    required this.count,
    required this.totalMinor,
    required this.receivedMinor,
    required this.unpaidMinor,
  });

  static const zero = SalesSummary(count: 0, totalMinor: 0, receivedMinor: 0, unpaidMinor: 0);

  final int count;
  final int totalMinor;
  final int receivedMinor;
  final int unpaidMinor;
}

/// Sales, payments and their stock effects. Each public write is one local
/// DB transaction that also queues outbox entries.
class SalesRepository {
  SalesRepository(this._db, this._session);

  final AppDatabase _db;
  final Session _session;

  String get _shopId => _session.shopId;

  // ------------------------------------------------------------- numbering

  Future<String> _prefix() async => (await _setting(SettingKeys.invoicePrefix)) ?? 'A';

  Future<String?> _setting(String key) async =>
      (await (_db.select(_db.settings)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  /// Next invoice number, without reserving it.
  Future<String> peekNextNumber() async {
    final seq = int.tryParse(await _setting(SettingKeys.invoiceSeq) ?? '') ?? 0;
    return _format(await _prefix(), seq + 1);
  }

  /// Reserves the next per-device number. Call inside a transaction.
  Future<({String number, int seq})> _reserve(String key, String infix) async {
    final seq = (int.tryParse(await _setting(key) ?? '') ?? 0) + 1;
    await _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: '$seq'),
        );
    return (number: _format(await _prefix(), seq, infix: infix), seq: seq);
  }

  static String _format(String prefix, int seq, {String infix = ''}) =>
      '$prefix-$infix${seq.toString().padLeft(4, '0')}';

  // ------------------------------------------------------------------ sale

  /// Saves a sale with its items, stock movements, payment and outbox
  /// entries in **one** DB transaction.
  Future<Txn> completeSale(SaleDraft draft) {
    if (draft.lines.isEmpty) throw ArgumentError('A sale needs at least one item.');
    return _db.transaction(() async {
      final now = nowMs();
      final totals = draft.totals;
      final number = await _reserve(SettingKeys.invoiceSeq, '');
      final txnId = newId();
      final tax = computeTaxes(totals.subtotalMinor - totals.discountMinor, draft.taxes);
      final breakdown = {
        'taxes': [
          for (final l in tax.lines)
            {
              'name': l.tax.name,
              'rateBps': l.tax.rateBps,
              'inclusive': l.tax.inclusive,
              'amountMinor': l.amountMinor,
            },
        ],
        'charges': [
          for (final c in draft.charges) {'label': c.label, 'amountMinor': c.amountMinor},
        ],
      };

      final txn = Txn(
        id: txnId,
        shopId: _shopId,
        createdAt: now,
        updatedAt: now,
        version: 1,
        syncStatus: 'pending',
        deviceId: _session.deviceId,
        type: TxnType.sale,
        number: number.number,
        deviceSeq: number.seq,
        date: draft.date.millisecondsSinceEpoch,
        partyId: draft.partyId,
        subtotalMinor: totals.subtotalMinor,
        discountMinor: totals.discountMinor,
        taxMinor: totals.taxMinor,
        chargesMinor: totals.chargesMinor,
        totalMinor: totals.totalMinor,
        paidMinor: draft.paidMinor,
        status: draft.status.dbValue,
        paymentMode: draft.paymentMode.dbValue,
        notes: draft.notes.trim(),
        breakdownJson: jsonEncode(breakdown),
        createdBy: _session.userId,
      );
      await _db.into(_db.transactions).insert(txn);

      final items = <TxnItem>[];
      for (final line in draft.lines) {
        final item = TxnItem(
          id: newId(),
          transactionId: txnId,
          productId: line.productId,
          nameSnapshot: line.name,
          unitSnapshot: line.unit,
          qty: line.qty,
          unitPriceMinor: line.unitPriceMinor,
          discountMinor: line.discountMinor,
          taxMinor: 0,
          lineTotalMinor: line.totalMinor,
          costPriceMinor: line.costPriceMinor,
        );
        items.add(item);
        await _db.into(_db.transactionItems).insert(item);

        if (line.productId != null) {
          final product = await (_db.select(_db.products)
                ..where((p) => p.id.equals(line.productId!)))
              .getSingleOrNull();
          if (product != null && product.trackStock) {
            await _addMovement(line.productId!, -line.qty, 'sale', txnId, now);
            await _db.recomputeStock(line.productId!);
          }
        }
      }

      if (draft.paidMinor > 0) {
        await _addPayment(
          transactionId: txnId,
          partyId: draft.partyId,
          amountMinor: draft.paidMinor,
          mode: draft.paymentMode.dbValue,
          date: txn.date,
          now: now,
        );
      }

      await _enqueueTxn(txn, items);
      return txn;
    });
  }

  /// Records money received, optionally against a sale (updating its
  /// paid amount and status).
  Future<Txn> receivePayment({
    String? saleId,
    String? partyId,
    required int amountMinor,
    required PaymentMode mode,
    DateTime? date,
    String notes = '',
  }) {
    if (amountMinor <= 0) throw ArgumentError('Amount must be positive.');
    return _db.transaction(() async {
      final now = nowMs();
      final when = (date ?? DateTime.now()).millisecondsSinceEpoch;
      Txn? sale;
      if (saleId != null) {
        sale = await (_db.select(_db.transactions)..where((t) => t.id.equals(saleId))).getSingle();
        partyId ??= sale.partyId;
      }
      final number = await _reserve('payment_in_seq', 'P');
      final txn = Txn(
        id: newId(),
        shopId: _shopId,
        createdAt: now,
        updatedAt: now,
        version: 1,
        syncStatus: 'pending',
        deviceId: _session.deviceId,
        type: TxnType.paymentIn,
        number: number.number,
        deviceSeq: number.seq,
        date: when,
        partyId: partyId,
        subtotalMinor: amountMinor,
        discountMinor: 0,
        taxMinor: 0,
        chargesMinor: 0,
        totalMinor: amountMinor,
        paidMinor: amountMinor,
        status: PaymentStatus.paid.dbValue,
        paymentMode: mode.dbValue,
        notes: notes.trim(),
        breakdownJson: '{}',
        refTransactionId: saleId,
        createdBy: _session.userId,
      );
      await _db.into(_db.transactions).insert(txn);
      await _addPayment(
        transactionId: txn.id,
        partyId: partyId,
        amountMinor: amountMinor,
        mode: mode.dbValue,
        date: when,
        now: now,
      );
      await _enqueueTxn(txn, const []);

      if (sale != null) {
        final paid = sale.paidMinor + amountMinor;
        final updated = sale.copyWith(
          paidMinor: paid,
          status: paymentStatusFor(totalMinor: sale.totalMinor, paidMinor: paid).dbValue,
          updatedAt: now,
          version: sale.version + 1,
          syncStatus: 'pending',
          deviceId: _session.deviceId,
        );
        await _db.update(_db.transactions).replace(updated);
        await _enqueueTxn(updated, await _items(updated.id));
      }
      return txn;
    });
  }

  /// Voids a sale: marks it `void`, reverses its stock movements and
  /// soft-deletes its payments. Nothing is hard-deleted.
  Future<void> voidTransaction(String id) {
    return _db.transaction(() async {
      final now = nowMs();
      final txn = await (_db.select(_db.transactions)..where((t) => t.id.equals(id))).getSingle();
      if (txn.status == PaymentStatus.voided.dbValue) return;

      final movements = await (_db.select(_db.stockMovements)
            ..where((m) => m.transactionId.equals(id) & m.deletedAt.isNull()))
          .get();
      for (final m in movements) {
        await _addMovement(m.productId, -m.qtyDelta, 'void', id, now);
        await _db.recomputeStock(m.productId);
      }

      final payments = await (_db.select(_db.payments)
            ..where((p) => p.transactionId.equals(id) & p.deletedAt.isNull()))
          .get();
      for (final p in payments) {
        final deleted = p.copyWith(
          deletedAt: Value(now),
          updatedAt: now,
          version: p.version + 1,
          syncStatus: 'pending',
          deviceId: _session.deviceId,
        );
        await _db.update(_db.payments).replace(deleted);
        await _db.enqueue('payments', p.id, deleted.toJson());
      }

      // A voided payment-in no longer counts towards the sale it paid.
      if (txn.type == TxnType.paymentIn && txn.refTransactionId != null) {
        final sale = await (_db.select(_db.transactions)
              ..where((t) => t.id.equals(txn.refTransactionId!)))
            .getSingleOrNull();
        if (sale != null && sale.status != PaymentStatus.voided.dbValue) {
          final paid = (sale.paidMinor - txn.totalMinor).clamp(0, sale.totalMinor);
          final updated = sale.copyWith(
            paidMinor: paid,
            status: paymentStatusFor(totalMinor: sale.totalMinor, paidMinor: paid).dbValue,
            updatedAt: now,
            version: sale.version + 1,
            syncStatus: 'pending',
            deviceId: _session.deviceId,
          );
          await _db.update(_db.transactions).replace(updated);
          await _enqueueTxn(updated, await _items(updated.id));
        }
      }

      final voided = txn.copyWith(
        status: PaymentStatus.voided.dbValue,
        updatedAt: now,
        version: txn.version + 1,
        syncStatus: 'pending',
        deviceId: _session.deviceId,
      );
      await _db.update(_db.transactions).replace(voided);
      await _enqueueTxn(voided, await _items(id));
    });
  }

  // ----------------------------------------------------------------- reads

  Stream<List<TxnListItem>> watchTransactions({
    Period period = Period.allTime,
    String query = '',
    Set<String>? types,
    Set<String>? statuses,
    int? limit,
  }) {
    final t = _db.transactions;
    final p = _db.parties;
    final q = _db.select(t).join([leftOuterJoin(p, p.id.equalsExp(t.partyId))])
      ..where(_filter(t, p, period, query, types, statuses))
      ..orderBy([OrderingTerm.desc(t.date), OrderingTerm.desc(t.createdAt)]);
    if (limit != null) q.limit(limit);
    return q.watch().map((rows) => [
          for (final r in rows) TxnListItem(r.readTable(t), r.readTableOrNull(p)?.name),
        ]);
  }

  Expression<bool> _filter(
    $TransactionsTable t,
    $PartiesTable p,
    Period period,
    String query,
    Set<String>? types,
    Set<String>? statuses,
  ) {
    Expression<bool> e = t.shopId.equals(_shopId) & t.deletedAt.isNull();
    if (period.startMs != null) e = e & t.date.isBiggerOrEqualValue(period.startMs!);
    if (period.endMs != null) e = e & t.date.isSmallerThanValue(period.endMs!);
    if (types != null && types.isNotEmpty) e = e & t.type.isIn(types);
    if (statuses != null && statuses.isNotEmpty) e = e & t.status.isIn(statuses);
    final text = query.trim().replaceAll(RegExp('[%_]'), '');
    if (text.isNotEmpty) {
      final like = '%$text%';
      e = e & (t.number.like(like) | p.name.like(like) | t.notes.like(like));
    }
    return e;
  }

  Stream<TxnDetail?> watchDetail(String id) {
    final query = _db.select(_db.transactions)..where((t) => t.id.equals(id));
    return query.watchSingleOrNull().asyncMap((txn) async {
      if (txn == null) return null;
      final payments = await (_db.select(_db.payments)
            ..where((p) => p.transactionId.equals(id) & p.deletedAt.isNull()))
          .get();
      final party = txn.partyId == null
          ? null
          : await (_db.select(_db.parties)..where((p) => p.id.equals(txn.partyId!)))
              .getSingleOrNull();
      return TxnDetail(txn: txn, items: await _items(id), payments: payments, party: party);
    });
  }

  Future<TxnDetail?> detail(String id) => watchDetail(id).first;

  Stream<SalesSummary> watchSummary(Period period) {
    final t = _db.transactions;
    final count = t.id.count();
    final total = t.totalMinor.sum();
    final paid = t.paidMinor.sum();
    Expression<bool> e = t.shopId.equals(_shopId) &
        t.deletedAt.isNull() &
        t.type.equals(TxnType.sale) &
        t.status.equals(PaymentStatus.voided.dbValue).not();
    if (period.startMs != null) e = e & t.date.isBiggerOrEqualValue(period.startMs!);
    if (period.endMs != null) e = e & t.date.isSmallerThanValue(period.endMs!);
    final q = _db.selectOnly(t)
      ..addColumns([count, total, paid])
      ..where(e);
    return q.watchSingle().map((r) {
      final totalV = r.read(total) ?? 0;
      final paidV = r.read(paid) ?? 0;
      return SalesSummary(
        count: r.read(count) ?? 0,
        totalMinor: totalV,
        receivedMinor: paidV,
        unpaidMinor: totalV - paidV,
      );
    });
  }

  /// Stock value at purchase price (inventory valuation).
  Stream<int> watchStockValue() {
    return _db
        .customSelect(
          'SELECT COALESCE(SUM(stock_qty * purchase_price_minor), 0) AS v FROM products '
          'WHERE shop_id = ? AND deleted_at IS NULL AND track_stock = 1 AND stock_qty > 0',
          variables: [Variable.withString(_shopId)],
          readsFrom: {_db.products},
        )
        .watchSingle()
        .map((r) => (r.data['v'] as num).round());
  }

  // --------------------------------------------------------------- helpers

  Future<List<TxnItem>> _items(String txnId) =>
      (_db.select(_db.transactionItems)..where((i) => i.transactionId.equals(txnId))).get();

  /// Transactions sync as one document with their items embedded.
  Future<void> _enqueueTxn(Txn txn, List<TxnItem> items) => _db.enqueue(
        'transactions',
        txn.id,
        {...txn.toJson(), 'items': [for (final i in items) i.toJson()]},
      );

  Future<void> _addMovement(String productId, double delta, String reason, String txnId, int now) async {
    final m = StockMovement(
      id: newId(),
      shopId: _shopId,
      createdAt: now,
      updatedAt: now,
      version: 1,
      syncStatus: 'pending',
      deviceId: _session.deviceId,
      productId: productId,
      qtyDelta: delta,
      reason: reason,
      transactionId: txnId,
      note: '',
    );
    await _db.into(_db.stockMovements).insert(m);
    await _db.enqueue('stock_movements', m.id, m.toJson());
  }

  Future<void> _addPayment({
    required String transactionId,
    String? partyId,
    required int amountMinor,
    required String mode,
    required int date,
    required int now,
  }) async {
    final pay = Payment(
      id: newId(),
      shopId: _shopId,
      createdAt: now,
      updatedAt: now,
      version: 1,
      syncStatus: 'pending',
      deviceId: _session.deviceId,
      transactionId: transactionId,
      partyId: partyId,
      direction: 'in',
      amountMinor: amountMinor,
      mode: mode,
      reference: '',
      date: date,
    );
    await _db.into(_db.payments).insert(pay);
    await _db.enqueue('payments', pay.id, pay.toJson());
  }
}

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)),
);
