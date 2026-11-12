import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/ai_audit_report.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/models/check_payment.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/ai_accountant_controller.dart';
import 'package:invest/domain/services/ai_accountant_engine.dart';
import 'package:invest/domain/services/ai_accountant_service.dart';
import 'package:invest/domain/services/check_ledger.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/ai_audit_detail_sheet.dart';
import 'package:invest/ui/widgets/ai_health_style.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryGeminiKeyVault implements GeminiKeyVault {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> delete() async => value = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final today = DateTime(2026, 11, 12, 23, 30);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CurrencyMode.reset();
  });

  tearDown(CurrencyMode.reset);

  BankCheck cheque({
    int id = 1,
    String direction = checkDirectionPayable,
    double amount = 1000,
    String due = '2026-11-13',
    String status = checkStatusPending,
    String kind = checkKindCheck,
    String counterparty = 'شرکت آلفا',
    String number = '998877',
    List<CheckPayment> payments = const [],
    String? archivedAt,
    int? serverDays,
  }) {
    return BankCheck(
      id: id,
      direction: direction,
      amount: amount,
      issueDate: '2026-11-01',
      dueDate: due,
      status: status,
      kind: kind,
      counterparty: counterparty,
      checkNumber: number,
      payments: payments,
      archivedAt: archivedAt,
      daysUntilDueFromServer: serverDays,
    );
  }

  AiAuditInput input({
    List<BankCheck> checks = const [],
    List<Asset> assets = const [],
    List<Trade> open = const [],
    List<Trade> closed = const [],
    List<Withdrawal> withdrawals = const [],
    PwoLedger? pwo,
    String account = '09120000001',
    DateTime? now,
    int sms = 0,
    double capital = 0,
  }) {
    return AiAuditInput(
      now: now ?? today,
      accountKey: account,
      totalCapitalToman: capital,
      assets: assets,
      checks: checks,
      openTrades: open,
      closedTrades: closed,
      withdrawals: withdrawals,
      pwo: pwo,
      unhandledSms: sms,
    );
  }

  group('aggregation', () {
    test('uses remaining amount and keeps deposits out of cheque totals', () {
      final snap = aggregateAudit(input(checks: [
        cheque(
          amount: 1000,
          payments: [
            CheckPayment(checkId: 1, amount: 400, paidAt: '2026-11-02'),
          ],
        ),
        cheque(
          id: 2,
          amount: 250,
          kind: checkKindDeposit,
          due: '2026-11-13',
          counterparty: 'ودیعه‌گذار',
        ),
        cheque(
          id: 3,
          direction: checkDirectionReceivable,
          amount: 800,
          due: '2026-11-10',
        ),
        cheque(id: 4, amount: 9999, status: checkStatusCleared),
        cheque(id: 5, amount: 8888, status: checkStatusCancelled),
        cheque(id: 6, amount: 7777, archivedAt: '2026-11-01T00:00:00'),
      ]));

      expect(snap.chequePayable, 600);
      expect(snap.chequePayable, isNot(1000));
      expect(snap.depositPayable, 250);
      expect(snap.chequeReceivable, 800);
      expect(snap.depositReceivable, 0);
      expect(
          snap.facts
              .where((f) => f.face == 9999 || f.face == 8888 || f.face == 7777),
          isEmpty);
      expect(snap.facts.singleWhere((f) => f.face == 1000).partial, isTrue);
      expect(snap.facts.singleWhere((f) => f.face == 1000).remaining, 600);
    });

    test('due math is calendar days and prefers the server count', () {
      final lateEvening = aggregateAudit(input(checks: [
        cheque(due: '2026-11-13'),
      ]));
      final fact = lateEvening.facts.single;
      expect(fact.days, 1);
      expect(fact.overdue, isFalse);
      expect(fact.thisWeek, isTrue);
      expect(daysUntilIranianWeekEnd(DateTime(2026, 11, 12)), 1);
      expect(daysUntilIranianWeekEnd(DateTime(2026, 11, 13)), 0);

      final server = aggregateAudit(input(checks: [
        cheque(due: '2026-11-13', serverDays: 40),
      ]));
      expect(server.facts.single.days, 40);
      expect(server.facts.single.thisWeek, isFalse);
      expect(server.facts.single.within30, isFalse);
      expect(server.facts.single.within90, isTrue);
    });

    test('forecast buckets split cheques and deposits', () {
      final snap = aggregateAudit(input(checks: [
        cheque(id: 1, due: '2026-11-10', amount: 100),
        cheque(id: 2, due: '2026-11-13', amount: 200, kind: checkKindDeposit),
        cheque(
          id: 3,
          direction: checkDirectionReceivable,
          due: '2026-12-12',
          amount: 300,
        ),
        cheque(id: 4, due: '2027-03-01', amount: 400),
      ]));
      CashflowBucket bucket(String id) =>
          snap.buckets.singleWhere((b) => b.id == id);

      expect(bucket('overdue').payableCheques, 100);
      expect(bucket('overdue').payableDeposits, 0);
      expect(bucket('week').payableDeposits, 200);
      expect(bucket('week').payableCheques, 0);
      expect(bucket('d30').receivableCheques, 300);
      expect(bucket('d30').payableCheques, 0);
      expect(bucket('d90').payableCheques, 0);
      final far = snap.facts.singleWhere((f) => f.face == 400);
      expect(far.within90, isFalse);
      expect(bucket('month').payableDeposits, 200);
    });

    test('cash warning does not treat نقد / تتر as rial', () {
      final warned = aggregateAudit(input(
        checks: [cheque(amount: 500000, due: '2026-11-13')],
        assets: [
          Asset(name: 'خانه ونک', quantity: 1, currentPrice: 9000000),
        ],
      ));
      expect(warned.cashWarning, isNotNull);
      expect(warned.cashWarning, contains('نقد / تتر'));
      expect(warned.cashWarning, contains('ریالی'));
      expect(jsonEncode(redactedAuditPayload(warned)),
          isNot(contains('خانه ونک')));
      expect(jsonEncode(redactedAuditPayload(warned)),
          isNot(contains('شرکت آلفا')));
      expect(
          jsonEncode(redactedAuditPayload(warned)), isNot(contains('998877')));

      final covered = aggregateAudit(input(
        checks: [cheque(amount: 500000, due: '2026-11-13')],
        assets: [
          Asset(
              name: 'تتر شخصی',
              symbol: 'USDT',
              quantity: 10,
              currentPrice: 80000),
        ],
      ));
      expect(covered.cashKindToman, 800000);
      expect(covered.cashWarning, isNull);
      expect(jsonEncode(redactedAuditPayload(covered)),
          isNot(contains('تتر شخصی')));
    });

    test('toman labels stay toman when the display currency is dollar', () {
      CurrencyMode.update(currency: 'usd', liveUsdt: 70000);
      expect(formatMoney(1500000), isNot(contains('تومان')));
      expect(tomanText(1500000), contains('تومان'));
      expect(tomanText(1500000), contains('۱'));
    });
  });

  group('local score and wider month', () {
    test('thresholds and alerts share one scale', () {
      expect(aiHealthTitle(85), contains('مطلوب'));
      expect(aiHealthTitle(84), contains('نیازمند توجه'));
      expect(aiHealthTitle(59), contains('هشدار'));
      expect(aiHealthColor(85), AppTheme.positive);
      expect(aiHealthColor(84), aiHealthAmber);
      expect(aiHealthColor(59), AppTheme.negative);

      final quiet = buildLocalReport(aggregateAudit(input()));
      expect(quiet.healthScore, greaterThanOrEqualTo(aiScoreGood));

      final loud = buildLocalReport(aggregateAudit(input(checks: [
        cheque(
            id: 1, status: checkStatusBounced, due: '2026-11-01', amount: 10),
        cheque(id: 2, due: '2026-11-01', amount: 10),
      ])));
      expect(loud.healthScore, lessThan(aiScoreWatch));
      expect(
          loud.alerts.map((a) => a.target),
          containsAll([
            aiTargetBounced,
            aiTargetOverdue,
          ]));
    });

    test('month summary includes pwo, withdrawals, pnl, and double count', () {
      final j = Jalali.fromDateTime(today);
      final ledger = PwoLedger(
        people: [PwoPerson(id: 'p0', name: 'نام محرمانه')],
        target: 1000000,
        months: {
          pwoMonthKey(j.year, j.month): PwoMonth(
            year: j.year,
            month: j.month,
            amounts: {'p0': 5000000},
          ),
        },
      );
      final snap = aggregateAudit(input(
        capital: 20000000,
        pwo: ledger,
        withdrawals: [
          Withdrawal(
            amount: 5000000,
            status: 'completed',
            createdAt: today.toIso8601String(),
          ),
        ],
        open: [
          Trade(
            assetId: 1,
            status: 'open',
            quantity: 2,
            buyPrice: 8,
            currentPrice: 10,
            assetName: 'بیت‌کوین علی',
          ),
          Trade(
            assetId: 2,
            status: 'open',
            quantity: 1,
            buyPrice: 5,
            currentPrice: 0,
          ),
        ],
        closed: [
          Trade(
            assetId: 3,
            status: 'closed',
            quantity: 1,
            buyPrice: 10,
            sellDate: toIsoDate(today),
            realizedPnl: 15,
          ),
        ],
        sms: 2,
      ));
      expect(snap.monthly.pwoTotal, 5000000);
      expect(snap.monthly.pwoTarget, 1000000);
      expect(snap.monthly.pwoWithin, isFalse);
      expect(snap.monthly.withdrawalsTotal, 5000000);
      expect(snap.monthly.doubleCountHits, 1);
      expect(snap.monthly.openUnrealizedPnl, 4);
      expect(snap.monthly.openUnpricedTrades, 1);
      expect(snap.monthly.monthRealizedPnl, 15);
      expect(jsonEncode(redactedAuditPayload(snap)),
          isNot(contains('نام محرمانه')));
      expect(jsonEncode(redactedAuditPayload(snap)),
          isNot(contains('بیت‌کوین علی')));

      final report = buildLocalReport(snap);
      expect(report.alerts.map((a) => a.target), contains(aiTargetBankSms));
      expect(report.summary, contains('تومان'));
      expect(report.auditedAtLabel, isNot(contains('2026-')));
      expect(report.auditedAtLabel, contains('۱'));
    });
  });

  group('questions', () {
    test('parses persian and arabic digits and the fixed intents', () {
      final snap = aggregateAudit(input(
          checks: [
            cheque(id: 1, amount: 700, due: '2026-11-14'),
            cheque(
                id: 2, amount: 50, due: '2026-11-10', kind: checkKindDeposit),
            cheque(
              id: 3,
              direction: checkDirectionReceivable,
              amount: 900,
              due: '2026-12-01',
            ),
          ],
          pwo: () {
            final j = Jalali.fromDateTime(today);
            return PwoLedger(
              people: [PwoPerson(id: 'p0', name: 'کسی')],
              target: 100,
              months: {
                pwoMonthKey(j.year, j.month): PwoMonth(
                  year: j.year,
                  month: j.month,
                  amounts: {'p0': 40},
                ),
              },
            );
          }()));

      expect(normalizeQuestion('تا ۷ روز'), contains('7'));
      expect(normalizeQuestion('تا ٧ روز'), contains('7'));

      final week =
          answerAccountantQuestion('تا ۷ روز آینده چقدر باید بپردازم؟', snap);
      final arabic =
          answerAccountantQuestion('تا ٧ روز آینده چقدر باید بپردازم؟', snap);
      expect(week.understood, isTrue);
      expect(week.text, arabic.text);
      expect(week.text, contains('تومان'));
      expect(week.text, isNot(contains('700')));

      final overdue =
          answerAccountantQuestion('چه چک‌هایی سررسید گذشته‌اند؟', snap);
      expect(overdue.understood, isTrue);
      expect(overdue.text, contains('ودیعه'));
      expect(overdue.redacted, isNot(contains('شرکت آلفا')));

      final recv =
          answerAccountantQuestion('مانده دریافتنی‌ها چقدر است؟', snap);
      expect(recv.text, contains('تومان'));

      final deposits = answerAccountantQuestion('ودیعه‌ها چقدر است؟', snap);
      expect(deposits.text, contains('ودیعه'));

      final pwo = answerAccountantQuestion('PWO این ماه چقدر است؟', snap);
      expect(pwo.text, anyOf(contains('PWO'), contains('هدف')));

      final unknown = answerAccountantQuestion('هوا فردا چطور است؟', snap);
      expect(unknown.understood, isFalse);
    });
  });

  group('gemini text', () {
    test('strips fences and rejects a bad schema', () {
      final ok = parseGeminiNarrative('''
```json
{"health_score": 81, "health_title": "پایدار", "summary": "خلاصه کافی است.", "recommendations": ["یک", "دو"]}
```
''');
      expect(ok, isNotNull);
      expect(ok!.healthScore, 81);

      expect(
          parseGeminiNarrative(
              '{"health_score": 10, "health_title": "", "summary": "x", "recommendations": ["a"]}'),
          isNull);
      expect(
          parseGeminiNarrative(
              '{"health_score": 140, "health_title": "عنوان", "summary": "متن", "recommendations": ["a"]}'),
          isNull);
      expect(parseGeminiNarrative('سلام'), isNull);
    });
  });

  group('cache, key, and gemini call', () {
    test('cache key is per account and a previous day is not current',
        () async {
      expect(
        aiAuditCachePrefsKey('09120000001'),
        isNot(aiAuditCachePrefsKey('09120000002')),
      );
      final vault = MemoryGeminiKeyVault();
      final service = AiAccountantService(
        vault: vault,
        clock: () => today,
        post: ({required url, required headers, required body}) async =>
            const AiHttpResult(500, ''),
      );
      final first = await service.audit(input(account: '09120000001'));
      await service.audit(input(account: '09120000002'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(aiAuditCachePrefsKey('09120000001')), isNotNull);
      expect(prefs.getString(aiAuditCachePrefsKey('09120000002')), isNotNull);

      final planted =
          jsonDecode(prefs.getString(aiAuditCachePrefsKey('09120000001'))!)
              as Map;
      planted['day'] = '2020-01-01';
      await prefs.setString(
          aiAuditCachePrefsKey('09120000001'), jsonEncode(planted));
      final cached = await service.readCache('09120000001');
      expect(cached, isNotNull);
      expect(cached!.matches(first.snapshot), isFalse);
      expect(cached.day, '2020-01-01');

      final fresh = await service.audit(input(account: '09120000001'));
      expect(fresh.dayIso, toIsoDate(today));
      expect(fresh.dayIso, isNot('2020-01-01'));
    });

    test('hash changes when the remaining amount changes', () {
      final base = aggregateAudit(input(checks: [cheque(amount: 1000)]));
      final paid = aggregateAudit(input(checks: [
        cheque(
          amount: 1000,
          payments: [
            CheckPayment(checkId: 1, amount: 100, paidAt: '2026-11-02')
          ],
        ),
      ]));
      expect(base.inputHash, isNot(paid.inputHash));
    });

    test('migrates the plaintext key into the vault and deletes it', () async {
      SharedPreferences.setMockInitialValues({kGeminiApiKeyPref: 'legacy-key'});
      final prefs = await SharedPreferences.getInstance();
      final vault = MemoryGeminiKeyVault();
      final migrated =
          await migrateAndReadGeminiKey(vault: vault, prefs: prefs);
      expect(migrated, 'legacy-key');
      expect(vault.value, 'legacy-key');
      expect(prefs.containsKey(kGeminiApiKeyPref), isFalse);

      await prefs.setString(kGeminiApiKeyPref, 'still-there');
      final kept = await migrateAndReadGeminiKey(vault: vault, prefs: prefs);
      expect(kept, 'legacy-key');
      expect(prefs.containsKey(kGeminiApiKeyPref), isFalse);
    });

    test('sends the key in a header and falls back cleanly', () async {
      final vault = MemoryGeminiKeyVault();
      final seenHeaders = <Map<String, String>>[];
      final seenBodies = <String>[];
      final seenUrls = <Uri>[];
      final fixed = AiAccountantService(
        vault: vault,
        clock: () => today,
        post: ({required url, required headers, required body}) async {
          seenUrls.add(url);
          seenHeaders.add(headers);
          seenBodies.add(body);
          return AiHttpResult(200, _goodGemini());
        },
      );
      await fixed.setConsent('09120000001', true);
      await fixed.saveApiKey('super-secret-key');
      final report = await fixed.audit(input(
        assets: [Asset(name: 'خانه ونک', quantity: 1, currentPrice: 10)],
        checks: [cheque()],
      ));
      expect(report.isAiGenerated, isTrue);
      expect(report.fallbackReason, isNull);
      expect(seenUrls.single.queryParameters, isEmpty);
      expect(seenUrls.single.toString(), isNot(contains('super-secret-key')));
      expect(seenHeaders.single['x-goog-api-key'], 'super-secret-key');
      expect(seenBodies.single, isNot(contains('super-secret-key')));
      expect(seenBodies.single, isNot(contains('خانه ونک')));
      expect(seenBodies.single, isNot(contains('شرکت آلفا')));

      final broken = AiAccountantService(
        vault: vault,
        clock: () => DateTime(2026, 11, 13, 9),
        post: ({required url, required headers, required body}) async =>
            const AiHttpResult(
                200, '{"candidates":[{"content":{"parts":[{"text":"نه"}]}}]}'),
      );
      await broken.setConsent('09120000001', true);
      final fallback = await broken.audit(
        input(
            now: DateTime(2026, 11, 13, 9),
            checks: [cheque(due: '2026-11-20')]),
        force: true,
      );
      expect(fallback.isAiGenerated, isFalse);
      expect(fallback.fallbackReason, isNotNull);

      var posts = 0;
      final silent = AiAccountantService(
        vault: MemoryGeminiKeyVault()..value = 'super-secret-key',
        clock: () => today,
        post: ({required url, required headers, required body}) async {
          posts++;
          return AiHttpResult(200, _goodGemini());
        },
      );
      final local = await silent.audit(input(account: '09129999999'));
      expect(posts, 0);
      expect(local.isAiGenerated, isFalse);
      expect(local.fallbackReason, isNull);
    });

    test('one shared gemini call when two refreshes overlap', () async {
      final vault = MemoryGeminiKeyVault()..value = 'k';
      final gate = Completer<AiHttpResult>();
      var calls = 0;
      final service = AiAccountantService(
        vault: vault,
        clock: () => today,
        post: ({required url, required headers, required body}) {
          calls++;
          return gate.future;
        },
      );
      await service.setConsent('09120000001', true);
      final data = input(checks: [cheque(amount: 10, due: '2026-11-20')]);
      final first = service.audit(data, force: true);
      final second = service.audit(data, force: true);
      final wait = Stopwatch()..start();
      while (calls == 0 && wait.elapsed < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(calls, 1);
      gate.complete(AiHttpResult(200, _goodGemini()));
      final reports = await Future.wait([first, second]);
      expect(reports[0].isAiGenerated, isTrue);
      expect(reports[1].healthTitle, reports[0].healthTitle);
      expect(calls, 1);
    });
  });

  group('alerts and notifications', () {
    test('targets open the matching cheque filter', () {
      final todayOnly = DateTime(2026, 11, 12);
      final book = [
        cheque(id: 1, due: '2026-11-10', amount: 1000, payments: [
          CheckPayment(checkId: 1, amount: 100, paidAt: '2026-11-02'),
        ]),
        cheque(id: 2, status: checkStatusBounced, due: '2026-11-01'),
        cheque(id: 3, due: '2026-11-18'),
      ];
      expect(
        filterChecks(book, filterForAuditTarget(aiTargetOverdue)!,
                today: todayOnly)
            .map((c) => c.id),
        [1],
      );
      expect(
        filterChecks(book, filterForAuditTarget(aiTargetBounced)!,
                today: todayOnly)
            .map((c) => c.id),
        [2],
      );
      expect(
        filterChecks(book, filterForAuditTarget(aiTargetPartial)!,
                today: todayOnly)
            .map((c) => c.id),
        [1],
      );
      expect(filterForAuditTarget(aiTargetDueSoon), CheckListFilter.due);
      expect(auditTargetOpensSms(aiTargetBankSms), isTrue);

      final snap = aggregateAudit(input(checks: book));
      final plan = planCheckDigest(
        snap: snap,
        notificationsEnabled: true,
        previousFingerprint: null,
      );
      expect(plan.shouldSend, isTrue);
      expect(plan.items.map((item) => item.id), containsAll([71001, 71002]));
      expect(plan.items.first.body, contains('تومان'));
      expect(plan.items.first.body, isNot(contains('شرکت آلفا')));

      final again = planCheckDigest(
        snap: snap,
        notificationsEnabled: true,
        previousFingerprint: plan.fingerprint,
      );
      expect(again.shouldSend, isFalse);
      final muted = planCheckDigest(
        snap: snap,
        notificationsEnabled: false,
        previousFingerprint: null,
      );
      expect(muted.shouldSend, isFalse);
    });

    test('controller shows yesterday as stale and then replaces it', () async {
      final vault = MemoryGeminiKeyVault();
      final yesterday = DateTime(2026, 11, 11, 12);
      final oldService =
          AiAccountantService(vault: vault, clock: () => yesterday);
      await oldService.audit(input(now: yesterday, account: '09121111111'));

      final service = AiAccountantService(vault: vault, clock: () => today);
      final controller = AiAccountantController(service: service);
      final flags = <bool>[];
      controller.addListener(() => flags.add(controller.stale));
      final state = AppState()
        ..userPhone = '09121111111'
        ..settings.notificationsEnabled = false;
      await controller.load(state);
      expect(flags, contains(true));
      expect(controller.stale, isFalse);
      expect(controller.report!.dayIso, toIsoDate(today));
    });
  });

  testWidgets('sheet shows forecast, fallback, score color, and answers',
      (tester) async {
    final snap = aggregateAudit(input(checks: [
      cheque(id: 1, due: '2026-11-10', amount: 1000),
      cheque(id: 2, due: '2026-11-13', amount: 200, kind: checkKindDeposit),
    ]));
    final report = buildLocalReport(snap).copyWithNarrative(
      healthScore: 84,
      healthTitle: aiHealthTitle(84),
      fallbackReason: 'ساختار پاسخ جمنای با گزارش حسابرسی جور نبود.',
    );
    String? opened;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => AiAuditDetailSheet(
                  report: report,
                  onAlert: (alert) => opened = alert.target,
                ),
              );
            },
            child: const Text('باز کردن'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('باز کردن'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-forecast')), findsOneWidget);
    expect(find.text('ودیعه پرداختی'), findsOneWidget);
    expect(find.byKey(const Key('ai-fallback-banner')), findsOneWidget);
    final score = tester.widget<Text>(find.byKey(const Key('ai-health-score')));
    expect(score.style!.color, aiHealthAmber);
    expect(find.textContaining('تومان'), findsWidgets);

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('ai-monthly')),
      300,
      scrollable: scrollable,
    );
    expect(find.byKey(const Key('ai-monthly')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('ai-alert-overdue')),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('ai-alert-overdue')));
    await tester.pump();
    expect(opened, aiTargetOverdue);

    await tester.scrollUntilVisible(
      find.text('ودیعه‌ها چقدر است؟'),
      300,
      scrollable: scrollable,
    );
    await tester.tap(find.text('ودیعه‌ها چقدر است؟'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('ai-qa-answer')),
      200,
      scrollable: scrollable,
    );
    expect(find.byKey(const Key('ai-qa-answer')), findsOneWidget);
    expect(find.textContaining('ودیعه'), findsWidgets);
  });
}

String _goodGemini() {
  return jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {
              'text': jsonEncode({
                'health_score': 90,
                'health_title': 'پایدار',
                'summary': 'خلاصه آنلاین.',
                'recommendations': ['یک', 'دو'],
              }),
            },
          ],
        },
      },
    ],
  });
}
