import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/domain/services/commodity_index_service.dart';

void main() {
  test('fetchAll returns essentials and all Wallex TMN markets', () async {
    final client = MockClient((request) async {
      final host = request.url.host;
      if (host.contains('persiantoolbox')) {
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'currencies': {
                'IRR': {'rate': 1468820.32, 'change24h': 0},
                'USD': {'rate': 1, 'change24h': 0},
                'EUR': {'rate': 0.861, 'change24h': 0.5},
                'GBP': {'rate': 0.738, 'change24h': -0.2},
                'AED': {'rate': 3.67, 'change24h': 0},
                'TRY': {'rate': 48.28, 'change24h': 1.1},
              },
              'gold': {'pricePerGram': 20869399.2, 'change24h': 0.19},
              'crypto': {
                'BTC': {'priceUSD': 78718, 'change24h': 1.5},
                'ETH': {'priceUSD': 2470, 'change24h': 2.3},
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (host.contains('wallex')) {
        return http.Response(
          jsonEncode({
            'result': {
              'symbols': {
                'USDTTMN': {
                  'symbol': 'USDTTMN',
                  'baseAsset': 'USDT',
                  'quoteAsset': 'TMN',
                  'faBaseAsset': 'تتر',
                  'stats': {
                    'lastPrice': '92000',
                    '24h_ch': 0.4,
                    '24h_quoteVolume': '1000000000',
                  },
                },
                'BTCTMN': {
                  'symbol': 'BTCTMN',
                  'baseAsset': 'BTC',
                  'quoteAsset': 'TMN',
                  'faBaseAsset': 'بیت‌کوین',
                  'stats': {
                    'lastPrice': '7000000000',
                    '24h_ch': -1.2,
                    '24h_quoteVolume': '5000000000',
                  },
                },
                'ETHUSDT': {
                  'symbol': 'ETHUSDT',
                  'baseAsset': 'ETH',
                  'quoteAsset': 'USDT',
                  'faBaseAsset': 'اتریوم',
                  'stats': {
                    'lastPrice': '2500',
                    '24h_ch': 1.0,
                    '24h_quoteVolume': '100',
                  },
                },
                'DOGETMN': {
                  'symbol': 'DOGETMN',
                  'baseAsset': 'DOGE',
                  'quoteAsset': 'TMN',
                  'faBaseAsset': 'دوج',
                  'stats': {
                    'lastPrice': '12000',
                    '24h_ch': 2.5,
                    '24h_quoteVolume': '200000',
                  },
                },
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });

    final service = CommodityIndexService(client: client);
    final bundle = await service.fetchAll(
      wallexUrl: 'https://api.wallex.ir/v1/markets',
      marketUrl: 'https://persiantoolbox.ir/api/market',
    );

    expect(bundle.essentials, hasLength(10));

    final usdt = bundle.essentials.firstWhere((q) => q.symbol == 'USDT');
    expect(usdt.price, closeTo(92000, 0.01));

    // Only TMN quote markets, not USDT pairs.
    expect(bundle.wallexMarkets, hasLength(3));
    expect(bundle.wallexMarkets.every((q) => q.unit == 'toman'), isTrue);
    expect(
      bundle.wallexMarkets.map((e) => e.symbol).toList(),
      containsAll(<String>['BTC', 'USDT', 'DOGE']),
    );
    expect(bundle.wallexMarkets.first.symbol, 'BTC'); // highest volume
    expect(bundle.wallexMarkets.any((q) => q.symbol == 'ETH'), isFalse);
  });
}
