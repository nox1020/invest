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

  GoldCashEntry copyWith({double? amount, String? date, String? note}) => GoldCashEntry(
        id: id,
        kind: kind,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        note: note ?? this.note,
        createdAt: createdAt,
        opId: opId,
        withdrawalMirrored: withdrawalMirrored,
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
    return GoldCashEntry(
      id: id,
      kind: kind,
      amount: signed,
      date: date.substring(0, 10),
      note: jsonText(m['note']).trim(),
      createdAt: jsonText(m['created_at']).trim(),
      opId: jsonText(m['op']).trim(),
      withdrawalMirrored: mirrored == true || mirrored == 1 || '$mirrored' == 'true',
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

  static List<GoldCashEntry> remove(List<GoldCashEntry> rows, String id) => [
        for (final r in rows)
          if (r.id != id) r
      ];

  static bool same(List<GoldCashEntry> a, List<GoldCashEntry> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.id != y.id ||
          x.kind != y.kind ||
          (x.amount - y.amount).abs() > 1e-6 ||
          x.date != y.date ||
          x.note != y.note) {
        return false;
      }
    }
    return true;
  }

  static double total(Iterable<GoldCashEntry> rows) => rows.fold(0.0, (s, e) => s + e.amount);
}
