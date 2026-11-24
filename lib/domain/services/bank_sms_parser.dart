import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shamsi_date/shamsi_date.dart';

/// Incoming bank deposit (واریز / بستانکار).
const bankSmsDirectionIn = 'in';

/// Outgoing bank withdrawal (برداشت / خرید / انتقال / …).
const bankSmsDirectionOut = 'out';

/// One bank movement parsed from an SMS. Only these fields are kept on the
/// device; the raw text is never stored, logged or sent anywhere.
class BankSmsItem {
  const BankSmsItem({
    required this.fp,
    required this.bank,
    required this.toman,
    required this.at,
    this.balanceToman,
    this.card,
    this.lowConfidence = false,
    this.direction = bankSmsDirectionOut,
  });

  /// sha1(sender + body): stable for the same SMS from the inbox or receiver.
  final String fp;
  final String bank;
  final double toman;
  final double? balanceToman;
  final String? card;
  final DateTime at;
  final bool lowConfidence;

  /// [bankSmsDirectionIn] or [bankSmsDirectionOut]. Missing/legacy → out.
  final String direction;

  bool get isIn => direction == bankSmsDirectionIn;
  bool get isOut => !isIn;

  /// Real SHA-1 fingerprints (not synthetic history ids) produce a note tag.
  bool get hasRealTag =>
      fp.length >= 8 && !fp.startsWith('hist-') && !fp.startsWith('sms-');

  Jalali get jalali => Jalali.fromDateTime(at);

  /// Server idempotency key (A-Z a-z 0-9 _ -, 8..100).
  String get idempotencyKey => 'sms-${fp.substring(0, 32)}';

  /// Short marker appended to the saved note so the same SMS can be
  /// recognised later as already recorded (also on the server, after a reset
  /// or on another phone). 8 hex chars of the hash; no SMS content.
  String get tag => hasRealTag ? '#${fp.substring(0, 8)}' : '';

  static bool noteHasTag(String note, String tag) =>
      tag.isNotEmpty && note.contains(tag);

  String get note {
    final parts = <String>[bank];
    if (card != null) parts.add('کارت $card');
    return '${parts.join(' · ')} (پیامک)';
  }

  Map<String, Object?> toJson() => {
        'fp': fp,
        'bank': bank,
        'toman': toman,
        'bal': balanceToman,
        'card': card,
        'at': at.millisecondsSinceEpoch,
        'low': lowConfidence,
        if (direction == bankSmsDirectionIn) 'dir': direction,
      };

  static BankSmsItem? fromJson(Object? o) {
    if (o is! Map) return null;
    final fp = o['fp'], t = o['toman'], at = o['at'];
    if (fp is! String || t is! num || at is! num) return null;
    return BankSmsItem(
      fp: fp,
      bank: (o['bank'] as String?) ?? 'بانک',
      toman: t.toDouble(),
      balanceToman: (o['bal'] as num?)?.toDouble(),
      card: o['card'] as String?,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      lowConfidence: o['low'] == true,
      direction: o['dir'] == bankSmsDirectionIn
          ? bankSmsDirectionIn
          : bankSmsDirectionOut,
    );
  }
}

String bankSmsFingerprint(String sender, String body) =>
    sha1.convert(utf8.encode('${sender.trim()}\n${body.trim()}')).toString();

const _banks = <String, String>{
  'ملت': 'بانک ملت',
  'mellat': 'بانک ملت',
  'ملی': 'بانک ملی',
  'melli': 'بانک ملی',
  'bmi': 'بانک ملی',
  'صادرات': 'بانک صادرات',
  'saderat': 'بانک صادرات',
  'bsi': 'بانک صادرات',
  'پاسارگاد': 'بانک پاسارگاد',
  'pasargad': 'بانک پاسارگاد',
  'bpi': 'بانک پاسارگاد',
  'سامان': 'بانک سامان',
  'saman': 'بانک سامان',
  'تجارت': 'بانک تجارت',
  'tejarat': 'بانک تجارت',
  'آینده': 'بانک آینده',
  'ayandeh': 'بانک آینده',
  'رسالت': 'بانک رسالت',
  'سپه': 'بانک سپه',
  'کشاورزی': 'بانک کشاورزی',
  'مسکن': 'بانک مسکن',
  'پارسیان': 'بانک پارسیان',
  'parsian': 'بانک پارسیان',
  'رفاه': 'بانک رفاه',
  'شهر': 'بانک شهر',
  'اقتصاد نوین': 'بانک اقتصاد نوین',
  'بلو': 'بلو',
  'blu': 'بلو',
};

String normalizeSmsText(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r == 0x066C || r == 0x060C) {
      b.write(',');
    } else if (r == 0x066B) {
      b.write('.');
    } else if (r == 0x2212 || r == 0x2013 || r == 0x2014) {
      b.write('-');
    } else if (r == 0x200E ||
        r == 0x200F ||
        (r >= 0x202A && r <= 0x202E) ||
        (r >= 0x2066 && r <= 0x2069)) {
      // bidi marks
    } else if (r == 0x064A) {
      b.write('ی');
    } else if (r == 0x0643) {
      b.write('ک');
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

final _otp = RegExp(r'رمز|کد\s*(تایید|تأیید|یکبار|پویا)|otp|password',
    caseSensitive: false);
final _withdrawKw = RegExp(r'برداشت|خرید|انتقال|کسر|پرداخت|انتقالی|بدهکار');
final _failed =
    RegExp(r'ناموفق|عدم موفقیت|لغو شد|برگشت خورد|برگشت داده|انجام نشد|رد شد');
final _reminder =
    RegExp(r'یادآوری|سررسید|مهلت|پرداخت کنید|لطفا|لطفاً|بدهی|قسط');
final _depositKw = RegExp(r'واریز|بستانکار');
final _balanceKw = RegExp(
    r'(مانده|موجودی|ماند)(\s*(حساب|کارت|قابل\s*برداشت|فعلی))?\s*[:：]?\s*$');

/// Money arriving in *your* account/card (strong «in» signal).
final _youIn = RegExp(r'به\s*(حساب|کارت|سپرده)\s*(ی\s*)?شما|بستانکار');

/// Money leaving *your* account/card (strong «out» signal).
final _youOut = RegExp(r'از\s*(حساب|کارت|سپرده)\s*(ی\s*)?شما|بدهکار');

/// Outgoing transfers that mention «واریز» for the *receiver* side.
final _outTransfer = RegExp(
    r'کارت\s*به\s*کارت|پایا|ساتنا|واریز\s*به\s*(کارت|حساب|شبا|سپرده)(?!\s*(ی\s*)?شما)');

/// First money keyword on the amount's own line decides mixed messages.
final _lineKw = RegExp(r'واریز|بستانکار|برداشت|خرید|انتقال|کسر|پرداخت|بدهکار');
final _lineDepositKw = RegExp(r'^(واریز|بستانکار)$');
final _amountKw = RegExp(r'(برداشت|خرید|انتقال|کسر|پرداخت|مبلغ)[^\d\n]{0,14}$');
final _depositAmountKw = RegExp(r'(واریز|بستانکار|مبلغ)[^\d\n]{0,14}$');
final _num = RegExp(r'\d[\d,]*');

class _Cand {
  _Cand(this.value, this.start, this.end, this.minus, this.commas,
      {this.plus = false});
  final double value;
  final int start, end;
  final bool minus, commas;

  /// Explicit «+» next to the amount (deposit marker on some banks).
  final bool plus;
}

/// Parses an Iranian bank SMS; returns null unless it is clearly a withdrawal.
BankSmsItem? parseBankSms(String sender, String body, DateTime receivedAt) {
  final t = normalizeSmsText(body);
  final lower = t.toLowerCase();
  if (_otp.hasMatch(lower)) return null;
  // Failed / reversed / cancelled transactions.
  if (_failed.hasMatch(t)) return null;
  final hasW = _withdrawKw.hasMatch(t) ||
      _outTransfer.hasMatch(t) ||
      _youOut.hasMatch(t);

  final cands = <_Cand>[];
  for (final m in _num.allMatches(t)) {
    var raw = m.group(0)!;
    while (raw.endsWith(',')) {
      raw = raw.substring(0, raw.length - 1);
    }
    final s = m.start, e = m.start + raw.length;
    final before = s > 0 ? t[s - 1] : '';
    final after = e < t.length ? t[e] : '';
    bool digitAt(int i) =>
        i >= 0 && i < t.length && RegExp(r'\d').hasMatch(t[i]);
    if (before == '/' || before == '*') continue;
    if (after == '/' || after == '*') continue;
    if (before == ':' && digitAt(s - 2)) continue;
    if (after == ':' && digitAt(e + 1)) continue;
    final commas = raw.contains(',');
    if (commas && !RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(raw)) continue;
    final digits = raw.replaceAll(',', '');
    if (digits.length > 15) continue;
    final v = double.tryParse(digits);
    if (v == null || v <= 0) continue;
    final pre = t.substring(s >= 14 ? s - 14 : 0, s);
    // Card / account numbers.
    if (RegExp(r'(کارت|حساب|ش\.?ح|سپرده)[^\d\n]{0,4}$').hasMatch(pre) &&
        !commas) {
      continue;
    }
    final minus =
        RegExp(r'-\s*$').hasMatch(t.substring(s >= 2 ? s - 2 : 0, s)) ||
            RegExp(r'^\s*-')
                .hasMatch(t.substring(e, e + 2 > t.length ? t.length : e + 2));
    final plusSign =
        RegExp(r'\+\s*$').hasMatch(t.substring(s >= 2 ? s - 2 : 0, s)) ||
            RegExp(r'^\s*\+')
                .hasMatch(t.substring(e, e + 2 > t.length ? t.length : e + 2));
    // «+98…» phone numbers are not amounts with a sign.
    final plus = plusSign && !minus && (commas || digits.length <= 9);
    cands.add(_Cand(v, s, e, minus, commas, plus: plus));
  }

  bool isBalance(_Cand c) => _balanceKw
      .hasMatch(t.substring(c.start >= 26 ? c.start - 26 : 0, c.start));
  String before24(_Cand c) =>
      t.substring(c.start >= 24 ? c.start - 24 : 0, c.start);
  bool isDateLike(_Cand c) {
    if (c.commas) return false;
    final m = RegExp(r'^14(\d{2})(\d{2})(\d{2})$')
        .firstMatch(c.value.toStringAsFixed(0));
    if (m == null) return false;
    final mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
    // «واریز 14500000» is an amount: month 50 is not a date.
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return false;
    if (_amountKw.hasMatch(before24(c)) ||
        _depositAmountKw.hasMatch(before24(c))) {
      return false;
    }
    return true;
  }

  final pool = cands.where((c) => !isBalance(c) && !isDateLike(c)).toList();
  final withCommas = pool.where((c) => c.commas).toList();
  final usable = withCommas.isNotEmpty ? withCommas : pool;

  _Cand? amount;
  var low = false;
  for (final c in usable) {
    if (c.minus) {
      amount = c;
      break;
    }
  }
  amount ??= usable
      .where((c) => _amountKw
          .hasMatch(t.substring(c.start >= 24 ? c.start - 24 : 0, c.start)))
      .firstOrNull;
  // «۱۰۰,۰۰۰ تومان برداشت شد» / «مبلغ ... از حساب شما برداشت» (Blu-style):
  // the withdrawal word follows the amount on the same line.
  amount ??= usable.where((c) {
    final end = c.end + 30 > t.length ? t.length : c.end + 30;
    final after = t.substring(c.end, end).split('\n').first;
    return _withdrawKw.hasMatch(after) && !_depositKw.hasMatch(after);
  }).firstOrNull;
  // A single withdrawal-looking amount besides the balance is unambiguous.
  if (amount == null && hasW && usable.length == 1) amount = usable.first;
  if (amount == null && hasW && usable.isNotEmpty) {
    amount = usable.first;
    low = true;
  }
  final hasD = _depositKw.hasMatch(t) || _youIn.hasMatch(t);
  var direction = bankSmsDirectionOut;

  _Cand? pickDepositAmount({bool mark = false}) {
    final pool = usable.where((c) => !c.minus).toList();
    if (pool.isEmpty) return null;
    final plus = pool.where((c) => c.plus).firstOrNull;
    if (plus != null) return plus;
    for (final c in pool) {
      if (_depositAmountKw.hasMatch(before24(c))) return c;
    }
    final after = pool.where((c) {
      final end = c.end + 30 > t.length ? t.length : c.end + 30;
      final rest = t.substring(c.end, end).split('\n').first;
      return (_depositKw.hasMatch(rest) || _youIn.hasMatch(rest)) &&
          !_withdrawKw.hasMatch(rest);
    }).firstOrNull;
    if (after != null) return after;
    if (mark && pool.length > 1) low = true;
    return pool.first;
  }

  /// First money keyword on the line holding [c] (null when none).
  String? lineKwOf(_Cand c) {
    final ls = t.lastIndexOf('\n', c.start > 0 ? c.start - 1 : 0);
    final le = t.indexOf('\n', c.end);
    final line = t.substring(ls < 0 ? 0 : ls + 1, le < 0 ? t.length : le);
    return _lineKw.firstMatch(line)?.group(0);
  }

  bool decideIn() {
    if (amount != null && amount.minus) return false;
    if (usable.any((c) => c.plus)) return true;
    final youIn = _youIn.hasMatch(t), youOut = _youOut.hasMatch(t);
    if (youIn && !youOut) return true;
    if (youOut || _outTransfer.hasMatch(t)) return false;
    if (!hasD) return false;
    if (!_withdrawKw.hasMatch(t)) return true;
    // Both kinds of words: the amount's own line decides, then word order.
    final c = amount ?? pickDepositAmount();
    final kw = c == null ? null : lineKwOf(c);
    if (kw != null) return _lineDepositKw.hasMatch(kw);
    return _depositKw.firstMatch(t)!.start < _withdrawKw.firstMatch(t)!.start;
  }

  if (usable.isNotEmpty && decideIn()) {
    low = false;
    final dep = pickDepositAmount(mark: true);
    if (dep != null) {
      amount = dep;
      direction = bankSmsDirectionIn;
    }
  }
  if (amount == null) return null;
  if (direction != bankSmsDirectionIn && !hasW && !amount.minus) return null;

  final toman = lower.contains('تومان');
  double toT(double v) => toman ? v : v / 10;
  if (amount.value < 1000 && !toman) return null; // under 100 toman: noise

  double? bal;
  for (final c in cands) {
    if (isBalance(c)) {
      bal = toT(c.value);
      break;
    }
  }

  String? card;
  final cm = RegExp(r'\d*\*+(\d{2,4})(?!\d)').firstMatch(t);
  if (cm != null) card = cm.group(1);

  var at = receivedAt;
  final dm = RegExp(r'(14\d{2})/(\d{1,2})/(\d{1,2})').firstMatch(t) ??
      RegExp(r'(?<!\d)(14\d{2})(\d{2})(\d{2})(?!\d)').firstMatch(t);
  final tm = RegExp(r'(?<!\d)(\d{1,2}):(\d{2})(?!\d)').firstMatch(t);
  if (dm != null) {
    try {
      final j = Jalali(int.parse(dm.group(1)!), int.parse(dm.group(2)!),
          int.parse(dm.group(3)!));
      final g = j.toDateTime();
      final h = tm == null ? receivedAt.hour : int.parse(tm.group(1)!);
      final mi = tm == null ? receivedAt.minute : int.parse(tm.group(2)!);
      final cand =
          DateTime(g.year, g.month, g.day, h.clamp(0, 23), mi.clamp(0, 59));
      if (cand.difference(receivedAt).inDays.abs() <= 40) at = cand;
    } catch (_) {}
  }

  var bank = 'بانک';
  final key =
      '${sender.toLowerCase()} ${lower.substring(0, lower.length > 60 ? 60 : lower.length)}';
  for (final e in _banks.entries) {
    if (key.contains(e.key)) {
      bank = e.value;
      break;
    }
  }

  // Ads mention «خرید» and amounts too: require a bank signal.
  final snd = sender.trim().replaceAll(' ', '');
  // Personal mobile numbers (people, shops) are never bank senders.
  final isMobile = RegExp(r'^(\+98|0098|98|0)9\d{9}$').hasMatch(snd);
  final senderLooksBank =
      (!isMobile && RegExp(r'^\+?\d{3,15}$').hasMatch(snd)) || bank != 'بانک';
  if (isMobile && bank == 'بانک') return null;
  // Payment reminders / instalment notices are not withdrawals.
  if (_reminder.hasMatch(t) && !amount.minus && !t.contains('برداشت')) {
    return null;
  }
  if (!senderLooksBank && bal == null && card == null) return null;

  return BankSmsItem(
    fp: bankSmsFingerprint(sender, body),
    bank: bank,
    toman: toT(amount.value).roundToDouble(),
    balanceToman: bal,
    card: card,
    at: at,
    lowConfidence: low,
    direction: direction,
  );
}
