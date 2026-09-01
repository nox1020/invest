import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invest/domain/services/commodity_index_service.dart';

void main() {
  test('fetch returns 10 commodity quotes from market payload', () async {
    final client = MockClient((request) async {
      if (request.url.host.contains('persiantoolbox')) {
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
        );
      }
      return http.Response('{}', 404);
    });

    final service = CommodityIndexService(client: client);
    final quotes = await service.fetch(wallexUrl: 'https://example.test/markets');

    expect(quotes.length, 10);
    expect(quotes.first.symbol, 'USDT');
    expect(quotes[1].symbol, 'USD');
    expect(quotes[1].price, closeTo(146882.032, 0.01));
    expect(quotes[6].symbol, 'GOLD');
    expect(quotes[6].price, closeTo(2086939.92, 0.1));
    expect(quotes[8].symbol, 'BTC');
    expect(quotes[8].price, 78718);
  });
}
