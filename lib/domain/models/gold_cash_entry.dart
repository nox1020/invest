import 'dart:convert';

import 'package:invest/domain/utils/json_values.dart';

/// Kinds of a manual «نقد صندوق طلا» entry. Trade cash is never stored:
/// it is derived from `[gf:…]` trades (see `GoldFundBook`).
class GoldCashKind {
  GoldCashKind._();
  static const opening = 'opening';
  static const deposit = 'deposit';
  static const withdraw = 'withdraw';
  static const adjust = 'adjust';
  static const all = [opening, deposit, withdraw, adjust];

  static String label(String kind) => switch (kind) {
        opening => 'موجودی اول دوره',
        deposit => 'واریز نقد',
        withdraw => 'برداشت نقد',
        adjust => 'تنظیم مانده',
        _ => 'نقد',
      };
}

/// One manual cash movement of the gold fund, synced in the settings bag
/// (`gold_fund_ledger`) and kept in backups.
class GoldCashEntry {
  const GoldCashEntry({
    required this.id,
    required this.kind,
    required this.amount,
    required this.date,
    this.note = '',
    this.createdAt = '',
    this.opId = '',
    this.withdrawalMirrored = false,
    this.deleted = false,
  });

  /// Stable client id (never reused).
  final String id;

  /// One of [GoldCashKind.all].
  final String kind;

  /// Signed effect on the fund cash (deposit/opening +, withdraw −,
  /// adjust ±).
  final double amount;

  /// ISO `yyyy-MM-dd`.
  final String date;
  final String note;
  final String createdAt;

  /// Fund operation this entry belongs to (a gap deposit made for a buy).
  final String opId;

  /// A matching profit withdrawal was also recorded on «نقدینگی».
  final bool withdrawalMirrored;

  /// Tombstone: the row was deleted. Kept (hidden) in the synced list so a
  /// delete wins over a stale copy on another device or in the offline
  /// queue when lists are merged (see [GoldCashLedger.merge]).
  final bool deleted;

  GoldCashEntry copyWith({double? amount, String? date, String? note, bool? deleted}) => GoldCashEntry(
        id: id,
        kind: kind,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        note: note ?? this.note,
        createdAt: createdAt,
        opId: opId,
        withdrawalMirrored: withdrawalMirrored,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'amount': amount,
        'date': date,
        if (note.isNotEmpty) 'note': note,
        if (createdAt.isNotEmpty) 'created_at': createdAt,
        if (opId.isNotEmpty) 'op': opId,
        if (withdrawalMirrored) 'mirrored': true,
        if (deleted) 'deleted': true,
      };

  /// Null when the row is unusable (no id, unknown kind, zero/NaN amount,
  /// bad date).
  static GoldCashEntry? tryParse(Map<String, dynamic> m) {
    final id = jsonText(m['id']).trim();
    final kind = jsonText(m['kind']).trim();
    final amount = jsonDouble(m['amount']);
    final date = jsonText(m['date']).trim();
    if (id.isEmpty || !GoldCashKind.all.contains(kind)) return null;
    if (amount == null || !amount.isFinite || amount.abs() < 0.5) return null;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(date)) return null;
    // Sign is part of the kind; repair rows written with the wrong sign.
    final signed = switch (kind) {
      GoldCashKind.deposit => amount.abs(),
      GoldCashKind.withdraw => -amount.abs(),
      _ => amount,
    };
    final mirrored = m['mirrored'];
    final del = m['deleted'];
    return GoldCashEntry(
      id: id,
      kind: kind,
      amount: signed,
      date: date.substring(0, 10),
      note: jsonText(m['note']).trim(),
      createdAt: jsonText(m['created_at']).trim(),
      opId: jsonText(m['op']).trim(),
      withdrawalMirrored: mirrored == true || mirrored == 1 || '$mirrored' == 'true',
      deleted: del == true || del == 1 || '$del' == 'true',
    );
  }
}

class GoldCashLedger {
  GoldCashLedger._();

  /// Lenient parse of a list or JSON string. Duplicate ids keep the first.
  /// Sorted oldest first (date, then created time).
  static List<GoldCashEntry> parse(dynamic v) {
    if (v == null) return [];
    dynamic raw = v;
    if (raw is String) {
      final t = raw.trim();
      if (t.isEmpty) return [];
      try {
        raw = jsonDecode(t);
      } catch (_) {
        return [];
      }
    }
    if (raw is! List) return [];
    final out = <GoldCashEntry>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final e = GoldCashEntry.tryParse(Map<String, dynamic>.from(item));
      if (e == null || !seen.add(e.id)) continue;
      out.add(e);
    }
    sort(out);
    return out;
  }

  static void sort(List<GoldCashEntry> rows) => rows.sort((a, b) {
        final c = a.date.compareTo(b.date);
        if (c != 0) return c;
        return a.createdAt.compareTo(b.createdAt);
      });

  static String encode(List<GoldCashEntry> rows) => jsonEncode(rows.map((e) => e.toJson()).toList());

  static List<GoldCashEntry> add(List<GoldCashEntry> rows, GoldCashEntry e) {
    final next = [
      for (final r in rows)
        if (r.id != e.id) r,
      e
    ];
    sort(next);
    return next;
  }

  /// Marks [id] deleted (a tombstone stays in the list; see
  /// [GoldCashEntry.deleted]). Unknown or already deleted ids: unchanged.
  static List<GoldCashEntry> remove(List<GoldCashEntry> rows, String id) => [
        for (final r in rows)
          if (r.id == id && !r.deleted) r.copyWith(deleted: true) else r
      ];

  /// Rows that count (tombstones dropped).
  static List<GoldCashEntry> live(Iterable<GoldCashEntry> rows) => [
        for (final r in rows)
          if (!r.deleted) r
      ];

  /// Union by id of two copies of the ledger (this phone and the server).
  /// Rows are never edited, only added or deleted, so a row present on
  /// either side is kept and a delete on either side wins. Order: [sort].
  static List<GoldCashEntry> merge(List<GoldCashEntry> a, List<GoldCashEntry> b) {
    final byId = <String, GoldCashEntry>{};
    for (final r in [...a, ...b]) {
      final cur = byId[r.id];
      if (cur == null) {
        byId[r.id] = r;
      } else if (r.deleted && !cur.deleted) {
        byId[r.id] = cur.copyWith(deleted: true);
      }
    }
    final out = byId.values.toList();
    sort(out);
    return out;
  }

  static bool same(List<GoldCashEntry> a, List<GoldCashEntry> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.id != y.id ||
          x.kind != y.kind ||
          (x.amount - y.amount).abs() > 1e-6 ||
          x.date != y.date ||
          x.note != y.note ||
          x.deleted != y.deleted) {
        return false;
      }
    }
    return true;
  }

  /// Σ of live rows.
  static double total(Iterable<GoldCashEntry> rows) => rows.fold(0.0, (s, e) => e.deleted ? s : s + e.amount);
}
