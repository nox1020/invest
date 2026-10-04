import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/services/gold_quote_parser.dart';
import 'package:invest/domain/services/quote_clients.dart';

void main() {
  test('parses WallGold 18k toman price and percent change', () {
    final q = GoldQuoteParser.fromWallGold({
      'result': [
        {
          'symbol': 'GLD_18C_750TMN',
          'marketCap': {
            'lastPrice': '26422000',
            '24hChangePrice': '0.02',
          },
        },
      ],
    });
    expect(q, isNotNull);
    expect(q!.priceToman, 26422000);
    expect(q.change24hPct, closeTo(2.0, 1e-9));
    expect(q.source, 'wallgold');
  });

  test('parses TGJU geram18 from IRR into toman', () {
    final q = GoldQuoteParser.fromTgju({
      'current': {
        'geram18': {'p': '264,550,000', 'dp': 0.88},
      },
    });
    expect(q, isNotNull);
    expect(q!.priceToman, closeTo(26455000, 1e-6));
    expect(q.change24hPct, closeTo(0.88, 1e-9));
    expect(q.source, 'tgju');
  });

  test('toolbox fallback converts 24k IRR spot to 18k toman', () {
    final q = GoldQuoteParser.fromPersianToolbox({
      'ok': true,
      'data': {
        'gold': {'pricePerGram': 177480399, 'change24h': 0.03},
        'units': {'goldPricePerGram': 'IRR'},
      },
    });
    expect(q, isNotNull);
    expect(q!.priceToman, closeTo(177480399 / 10 * 0.75, 0.1));
  });

  test('stale toolbox URLs migrate to WallGold default', () {
    expect(
      GoldQuoteParser.resolveConfiguredUrl(
        'https://persiantoolbox.ir/api/market',
      ),
      AppConfig.defaultGoldApiUrl,
    );
    expect(
      GoldQuoteParser.resolveConfiguredUrl(
        'https://api.persiantoolbox.com/v1/metal',
      ),
      AppConfig.defaultGoldApiUrl,
    );
    expect(
      GoldQuoteParser.resolveConfiguredUrl(
        'https://api.wallgold.ir/api/v1/markets',
      ),
      'https://api.wallgold.ir/api/v1/markets',
    );
  });

  test('preferFreeMarketGold rejects understated Vinor/toolbox marks', () {
    expect(GoldQuoteParser.isUnderstated18kToman(13300000), isTrue);
    expect(GoldQuoteParser.isUnderstated18kToman(17700000), isTrue);
    expect(GoldQuoteParser.isUnderstated18kToman(26400000), isFalse);
    expect(
      GoldQuoteParser.preferFreeMarketGold(
        freeMarket: 26422000,
        remoteOrCached: 13313120,
      ),
      26422000,
    );
    expect(
      GoldQuoteParser.preferFreeMarketGold(
        freeMarket: null,
        remoteOrCached: 13313120,
      ),
      13313120, // last resort only when free feeds fail
    );
    expect(
      GoldQuoteParser.preferFreeMarketGold(
        freeMarket: null,
        remoteOrCached: 26422000,
      ),
      26422000,
    );
  });

  test('QuoteClients falls back from WallGold to TGJU', () async {
    var wallGoldHits = 0;
    final client = MockClient((request) async {
      final host = request.url.host;
      if (host.contains('wallgold')) {
        wallGoldHits += 1;
        return http.Response('{"result":[]}', 200);
      }
      if (host.contains('tgju')) {
        return http.Response(
          '{"current":{"geram18":{"p":"260000000","dp":1.2}}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    final quote = await QuoteClients(client: client).fetchGoldToman();
    expect(wallGoldHits, 1);
    expect(quote.price, closeTo(26000000, 1e-6));
    expect(quote.change24h, closeTo(1.2, 1e-9));
  });
}
