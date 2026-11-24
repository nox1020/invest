// The Android side pre-filters the inbox with regexes in SmsReceiver.kt. This
// test reads those exact literals and runs them against the shared samples so
// a format the Dart parser understands is never dropped natively.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/services/bank_sms_parser.dart';

import 'support/bank_sms_samples.dart';

RegExp _kotlinRegex(String src, String name) {
  final m = RegExp('private val $name = Regex\\("((?:[^"\\\\]|\\\\.)*)"')
      .firstMatch(src);
  if (m == null) throw StateError('Regex $name not found in SmsReceiver.kt');
  final lit = m
      .group(1)!
      .replaceAll(r'\\', '\u0000')
      .replaceAll(r'\"', '"')
      .replaceAll('\u0000', r'\');
  return RegExp(lit, caseSensitive: name != 'skip');
}

void main() {
  final src =
      File('android/app/src/main/kotlin/com/nox1020/invest/SmsReceiver.kt')
          .readAsStringSync();
  final debit = _kotlinRegex(src, 'debit');
  final credit = _kotlinRegex(src, 'credit');
  final skip = _kotlinRegex(src, 'skip');
  bool movement(String b) =>
      (debit.hasMatch(b) || credit.hasMatch(b)) && !skip.hasMatch(b);
  bool withdrawal(String b) => debit.hasMatch(b) && !skip.hasMatch(b);
  final rx = DateTime(2026, 11, 24, 12);

  for (final s in bankSmsSamples) {
    test('native filter keeps «${s.name}»', () {
      final it = parseBankSms(s.sender, s.body, rx);
      if (it == null) return;
      expect(movement(s.body), isTrue,
          reason: 'cashflowInbox would drop a parsed SMS');
      if (it.isOut) {
        expect(withdrawal(s.body), isTrue,
            reason: 'withdrawal inbox/notification would drop it');
      }
    });
  }

  test('pure deposits pass the movement filter but not the withdrawal one', () {
    const blu = '۱۰۰,۰۰۰ تومان به حساب شما واریز شد.\nموجودی: ۵۰۰,۰۰۰ تومان';
    expect(movement(blu), isTrue);
    expect(withdrawal(blu), isFalse);
  });

  test('withdrawal inbox (300 cap) is untouched; cashflow scan has no 300 cap',
      () {
    expect(src, contains('out.size < 300'));
    final mv = src.indexOf('fun readMovements');
    expect(mv, greaterThan(0));
    final body = src.substring(mv, src.indexOf('fun takeRejected'));
    expect(body.contains('< 300'), isFalse);
    expect(body, contains('looksLikeMovement'));
  });
}
