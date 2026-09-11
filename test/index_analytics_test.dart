import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/services/index_analytics.dart';
import 'package:invest/ui/widgets/index_quote_card.dart';

CommodityQuote q({
  required String id,
  String? name,
  String symbol = 'X',
  String unit = 'toman',
  double? price,
  double? change24h,
  double? high24h,
  double? low24h,
  double? bidPrice,
  double? askPrice,
  double? quoteVolume24h,
}) {
  return CommodityQuote(
    id: id,
    name: name ?? id,
    symbol: symbol,
    unit: unit,
    price: price,
    change24h: change24h,
    high24h: high24h,
    low24h: low24h,
    bidPrice: bidPrice,
    askPrice: askPrice,
    quoteVolume24h: quoteVolume24h,
  );
}

void main() {
  test('groupEssentials buckets and orders the household index', () {
    final grouped = groupEssentials([
      q(id: 'btc', name: 'بیت‌کوین'),
      q(id: 'eur', name: 'یورو'),
      q(id: 'gold', name: 'طلا'),
      q(id: 'usdt', name: 'تتر'),
      q(id: 'coin', name: 'سکه'),
      q(id: 'eth', name: 'اتریوم'),
      q(id: 'usd', name: 'دلار'),
      q(id: 'mystery', name: 'سایر'),
    ]);

    expect(
      grouped.map((g) => g.spec.group).toList(),
      [
        IndexQuoteGroup.fxLiquidity,
        IndexQuoteGroup.inflationHedge,
        IndexQuoteGroup.riskAsset,
        IndexQuoteGroup.other,
      ],
    );
    expect(
      grouped[0].quotes.map((e) => e.id).toList(),
      ['usdt', 'usd', 'eur'],
    );
    expect(
      grouped[1].quotes.map((e) => e.id).toList(),
      ['gold', 'coin'],
    );
    expect(
      grouped[2].quotes.map((e) => e.id).toList(),
      ['btc', 'eth'],
    );
    expect(grouped[3].quotes.single.id, 'mystery');
  });

  test('groupEssentials skips empty buckets', () {
    final grouped = groupEssentials([q(id: 'gold', name: 'طلا')]);
    expect(grouped, hasLength(1));
    expect(grouped.single.spec.group, IndexQuoteGroup.inflationHedge);
  });

  test('indexRoleLabel names the economic role', () {
    expect(indexRoleLabel(q(id: 'usdt')), 'لنگر بازار آزاد');
    expect(indexRoleLabel(q(id: 'gold')), 'پوشش تورم · ۱۸ عیار');
    expect(indexRoleLabel(q(id: 'btc')), 'دارایی ریسکی');
    expect(indexRoleLabel(q(id: 'wallex_doge', symbol: 'DOGE')), 'DOGE');
  });

  test('marketPulse reports green majority and the day’s leader', () {
    final pulse = marketPulse([
      q(id: 'usdt', name: 'تتر', change24h: 0.4),
      q(id: 'gold', name: 'طلا', change24h: 1.8),
      q(id: 'btc', name: 'بیت‌کوین', change24h: -0.5),
      q(id: 'eth', name: 'اتریوم', change24h: 0.2),
    ]);
    expect(pulse.up, 3);
    expect(pulse.down, 1);
    expect(pulse.flat, 0);
    expect(pulse.sampled, 4);
    expect(pulse.isGreen, isTrue);
    expect(pulse.leader?.id, 'gold');
    expect(pulse.laggard?.id, 'btc');
    expect(pulse.headline, contains('سبز'));
    expect(pulse.headline, contains('طلا'));
  });

  test('marketPulse reports selling pressure', () {
    final pulse = marketPulse([
      q(id: 'a', name: 'الف', change24h: -1),
      q(id: 'b', name: 'ب', change24h: -2),
      q(id: 'c', name: 'ج', change24h: 0.1),
    ], marketLabel: 'دفتر والکس');
    expect(pulse.isRed, isTrue);
    expect(pulse.headline, contains('فشار فروش'));
    expect(pulse.headline, contains('ب'));
    expect(pulse.laggard?.id, 'b');
  });

  test('marketPulse is empty without 24h changes', () {
    final pulse = marketPulse([q(id: 'usdt', price: 1)]);
    expect(pulse.isEmpty, isTrue);
    expect(pulse.headline, contains('۲۴ساعته'));
  });

  test('marketPulse treats a split book as balanced', () {
    final pulse = marketPulse([
      q(id: 'a', name: 'پیشرو', change24h: 1),
      q(id: 'b', name: 'عقب', change24h: -1),
    ]);
    expect(pulse.isGreen, isFalse);
    expect(pulse.isRed, isFalse);
    expect(pulse.headline, contains('متعادل'));
    expect(pulse.headline, contains('پیشرو'));
    expect(pulse.headline, contains('عقب'));
  });

  test('rangePosition is 0 at the low and 1 at the high', () {
    expect(
      rangePosition(q(id: 'x', price: 10, low24h: 10, high24h: 20)),
      closeTo(0, 1e-9),
    );
    expect(
      rangePosition(q(id: 'x', price: 20, low24h: 10, high24h: 20)),
      closeTo(1, 1e-9),
    );
    expect(
      rangePosition(q(id: 'x', price: 15, low24h: 10, high24h: 20)),
      closeTo(0.5, 1e-9),
    );
    expect(
      rangePosition(q(id: 'x', price: 30, low24h: 10, high24h: 20)),
      closeTo(1, 1e-9),
    );
    expect(rangePosition(q(id: 'x', price: 10)), isNull);
    expect(
      rangePosition(q(id: 'x', price: 10, low24h: 10, high24h: 10)),
      closeTo(0.5, 1e-9),
    );
    expect(
      rangePosition(q(id: 'x', price: 10, low24h: 20, high24h: 10)),
      isNull,
    );
  });

  test('rangeCaption describes extremes', () {
    expect(rangeCaption(0.9), 'نزدیک سقف ۲۴ساعته');
    expect(rangeCaption(0.05), 'نزدیک کف ۲۴ساعته');
    expect(rangeCaption(0.5), 'میانه بازه ۲۴ساعته');
    expect(rangeCaption(null), isNull);
  });

  test('relativeSpreadPct is percent of mid and skips a crossed book', () {
    expect(
      relativeSpreadPct(q(id: 'x', bidPrice: 99, askPrice: 101)),
      closeTo(2, 1e-9),
    );
    expect(relativeSpreadPct(q(id: 'x', bidPrice: 101, askPrice: 99)), isNull);
    expect(relativeSpreadPct(q(id: 'x', bidPrice: 100)), isNull);
    expect(spreadLabel(q(id: 'x', bidPrice: 99, askPrice: 101)),
        contains('اسپرد'));
  });

  test('sortWallexQuotes orders by volume, gainers, then losers', () {
    final quotes = [
      q(id: 'a', name: 'A', change24h: 1, quoteVolume24h: 10),
      q(id: 'b', name: 'B', change24h: -3, quoteVolume24h: 50),
      q(id: 'c', name: 'C', change24h: 5, quoteVolume24h: 20),
      q(id: 'd', name: 'D', quoteVolume24h: 99),
    ];
    expect(
      sortWallexQuotes(quotes, WallexSort.volume).map((e) => e.id).toList(),
      ['d', 'b', 'c', 'a'],
    );
    expect(
      sortWallexQuotes(quotes, WallexSort.gainers).map((e) => e.id).toList(),
      ['c', 'a', 'b', 'd'],
    );
    expect(
      sortWallexQuotes(quotes, WallexSort.losers).map((e) => e.id).toList(),
      ['b', 'a', 'c', 'd'],
    );
  });

  test('indexAnchors prefers USDT and reports grams of 18k per dollar', () {
    final anchors = indexAnchors([
      q(id: 'usd', price: 200000),
      q(id: 'usdt', price: 236000),
      q(
        id: 'gold',
        price: 15000000,
        unit: 'toman_per_gram',
      ),
    ]);
    expect(anchors.usd?.id, 'usdt');
    expect(anchors.gramsPerUsd, closeTo(236000 / 15000000, 1e-12));
    expect(anchors.caption, contains('گرم طلای ۱۸ عیار'));
    expect(indexAnchors([q(id: 'usdt', price: 1)]).caption, isNull);
  });

  testWidgets('IndexQuoteCard shows role, change, and stays compact',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: IndexQuoteCard(
            quote: q(
              id: 'gold',
              name: 'طلای ۱۸ عیار',
              symbol: 'GOLD',
              unit: 'toman_per_gram',
              price: 15200000,
              change24h: 1.25,
              high24h: 15500000,
              low24h: 14800000,
            ),
            showAlert: false,
          ),
        ),
      ),
    );
    expect(find.text('طلای ۱۸ عیار'), findsOneWidget);
    expect(find.text('پوشش تورم · ۱۸ عیار'), findsOneWidget);
    expect(find.textContaining('٪'), findsOneWidget);
    expect(find.byType(QuoteRangeBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
