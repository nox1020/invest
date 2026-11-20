import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'perf_finders.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/utils/biz_dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/performance_page.dart';
import 'package:invest/ui/widgets/performance_sections.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefBaseUrl: 'https://vinor.test',
    });
    BizStore.instance.debugReset();
    ProjectsStore.instance.debugReset();
    BizStore.yearNow = () => 1405;
  });

  tearDown(() {
    BizStore.instance.debugReset();
    ProjectsStore.instance.debugReset();
    BizStore.yearNow = currentJalaliYear;
  });

  testWidgets(
    'همه ماه‌ها opens the full list; a month opens the all-category detail',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      BizStore.instance.debugSet(
        account: 'test',
        BizSnapshot({
          'year': 1405,
          'trades': [
            {
              'id': 1,
              'title': 'آپارتمان ونک',
              'buy_date': '1405/08/01',
              'sell_date': '1405/08/15',
              'buy_amount': 2000000000,
              'sell_amount': 2200000000,
              'extra_cost': 20000000, // +180M
            },
          ],
          'months': [
            for (var m = 1; m <= 12; m++)
              if (m == 8)
                {
                  'year': 1405,
                  'month': 8,
                  'income': 80000000,
                  'staff': 25000000,
                  'pwo': 12000000,
                  'ads': 3000000,
                  'has_ops': true, // office +40M
                }
              else
                {'year': 1405, 'month': m},
          ],
        }),
      );

      final app = AppState()
        ..settings = AppSettings(calendar: AppConfig.calendarJalali)
        ..assets = [
          Asset(
            id: 1,
            name: 'طلای آب‌شده',
            symbol: 'GOLD',
            notes: '[kind:gold]',
          ),
          Asset(id: 2, name: 'Bitcoin', symbol: 'BTC', notes: '[kind:crypto]'),
        ]
        ..closedTrades = [
          Trade(
            id: 10,
            assetId: 1,
            assetName: 'طلای آب‌شده',
            status: AppConfig.tradeClosed,
            quantity: 1,
            buyPrice: 210000000,
            sellPrice: 252000000,
            realizedPnl: 42000000,
            buyDate: '1405/08/02',
            sellDate: '1405/08/08',
          ),
          Trade(
            id: 11,
            assetId: 2,
            assetName: 'Bitcoin',
            status: AppConfig.tradeClosed,
            quantity: 1,
            buyPrice: 100000000,
            sellPrice: 91500000,
            realizedPnl: -8500000,
            buyDate: '1405/08/01',
            sellDate: '1405/08/03',
          ),
        ];

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const MaterialApp(home: Scaffold(body: PerformancePage())),
        ),
      );
      await tester.pumpAndSettle();

      // Office 40M + property 180M + gold 42M + crypto -8.5M = 253.5M
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('biz-total-net'))).data,
        formatMoney(253500000),
      );
      await revealKey(tester, const ValueKey('perf-open-all-months'));
      expect(
        find.byKey(const ValueKey('perf-open-all-months')),
        findsOneWidget,
      );
      await revealKey(tester, const ValueKey('perf-preview-month-8'));
      expect(
        find.byKey(const ValueKey('perf-preview-month-8')),
        findsOneWidget,
      );
      expect(find.text('برج 8 · آبان'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('perf-preview-month-net-8')))
            .data,
        signedPerfMoney(253500000),
      );
      expect(find.text('آپارتمان ونک'), findsNothing);
      expect(find.text('طلای آب‌شده'), findsNothing);
      expect(find.text('Bitcoin'), findsNothing);
      expect(find.textContaining('در خالص حساب نمی‌شود'), findsNothing);
      expect(find.byKey(const ValueKey('perf-preview-month-flag-8')),
          findsNothing);
      expect(find.byKey(const ValueKey('biz-month-12')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('perf-open-all-months')));
      await tester.pumpAndSettle();
      expect(find.text('عملکرد ماهانه'), findsWidgets);
      expect(
        find.byKey(const ValueKey('biz-months-filter-all')),
        findsOneWidget,
      );
      await revealKey(tester, const ValueKey('biz-month-8'));
      expect(find.byKey(const ValueKey('biz-month-8')), findsOneWidget);
      expect(find.text('برج 8 · آبان'), findsWidgets);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('biz-month-net-8'))).data,
        signedPerfMoney(253500000),
      );
      expect(find.text('آپارتمان ونک'), findsNothing);
      expect(find.text('طلای آب‌شده'), findsNothing);
      expect(find.text('Bitcoin'), findsNothing);
      await revealKey(tester, const ValueKey('biz-month-12'));
      expect(find.byKey(const ValueKey('biz-month-12')), findsOneWidget);

      await revealKey(tester, const ValueKey('biz-month-8'));
      await tester.tap(find.byKey(const ValueKey('biz-month-8')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('perf-month-hero')), findsOneWidget);
      expect(find.text('آپارتمان ونک'), findsOneWidget);
      expect(find.text('طلای آب‌شده'), findsOneWidget);
      expect(find.text('Bitcoin'), findsOneWidget);
      expect(find.text('تفکیک سود هر دسته'), findsOneWidget);
      expect(find.byKey(const ValueKey('perf-month-office')), findsOneWidget);
      expect(find.byKey(const ValueKey('perf-month-edit')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detail page flags all-category duplicate income and opens the editor',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      BizStore.instance.debugSet(
        account: 'test',
        BizSnapshot({
          'year': 1405,
          'trades': [
            {
              'id': 1,
              'title': 'زمین دماوند',
              'buy_date': '1405/01/01',
              'sell_date': '1405/01/10',
              'buy_amount': 100000000,
              'sell_amount': 200000000,
              'extra_cost': 0, // +100M
            },
          ],
          'months': [
            {
              'year': 1405,
              'month': 1,
              'income': 110000000, // 100M property + 10M gold
              'staff': 0,
              'pwo': 0,
              'ads': 0,
              'has_ops': true,
            },
            for (var m = 2; m <= 12; m++) {'year': 1405, 'month': m},
          ],
        }),
      );

      final app = AppState()
        ..settings = AppSettings(calendar: AppConfig.calendarJalali)
        ..assets = [
          Asset(id: 1, name: 'سکه امامی', symbol: 'GOLD', notes: '[kind:gold]'),
        ]
        ..closedTrades = [
          Trade(
            id: 2,
            assetId: 1,
            assetName: 'سکه امامی',
            status: AppConfig.tradeClosed,
            quantity: 1,
            buyPrice: 40000000,
            sellPrice: 50000000,
            realizedPnl: 10000000,
            buyDate: '1405/01/02',
            sellDate: '1405/01/12',
          ),
        ];

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const MaterialApp(home: Scaffold(body: PerformancePage())),
        ),
      );
      await tester.pumpAndSettle();

      // Income flagged, so net is 110M not 220M
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('biz-total-net'))).data,
        formatMoney(110000000),
      );
      expect(find.byKey(const ValueKey('biz-mismatch-pill')), findsOneWidget);

      await revealKey(tester, const ValueKey('perf-preview-month-1'));
      await tester.tap(find.byKey(const ValueKey('perf-preview-month-1')));
      await tester.pumpAndSettle();
      await revealKey(tester, const ValueKey('perf-month-flag-1'));
      expect(find.byKey(const ValueKey('perf-month-flag-1')), findsOneWidget);

      await revealKey(tester, const ValueKey('perf-month-edit'));
      await tester.tap(find.byKey(const ValueKey('perf-month-edit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('biz-m-clear-dup')), findsOneWidget);
      expect(find.byKey(const ValueKey('biz-m-trades-info')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
