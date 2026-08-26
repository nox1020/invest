import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:invest/config/app_config.dart';

class QuoteClients {
  QuoteClients({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<double?> fetchUsdtToman({String? wallexUrl}) async {
    final url = Uri.parse(wallexUrl?.isNotEmpty == true
        ? wallexUrl!
        : AppConfig.defaultWallexUrl);
    try {
      final res = await _client.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      // Wallex markets payload: result.symbols.USDTTMN or similar
      if (body is Map) {
        final result = body['result'];
        if (result is Map) {
          final symbols = result['symbols'];
          if (symbols is Map) {
            for (final key in ['USDTTMN', 'USDTTOM', 'USDTIRT']) {
              final m = symbols[key];
              if (m is Map && m['stats'] is Map) {
                final bid = m['stats']['bidPrice'] ?? m['stats']['lastPrice'];
                final v = double.tryParse('$bid');
                if (v != null && v > 0) return v;
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<({double? price, double? change24h})> fetchGoldToman({
    String? persianUrl,
  }) async {
    final url = Uri.parse(persianUrl?.isNotEmpty == true
        ? persianUrl!
        : AppConfig.defaultPersianToolboxUrl);
    try {
      final res = await _client.get(url).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return (price: null, change24h: null);
      final body = jsonDecode(res.body);
      if (body is Map) {
        final gold = body['gold'];
        if (gold is Map) {
          var price = double.tryParse('${gold['pricePerGram']}');
          final units = body['units'];
          final unit = units is Map
              ? '${units['goldPricePerGram'] ?? 'IRR'}'.toUpperCase()
              : 'IRR';
          // API often IRR; app uses toman (÷10)
          if (price != null && price > 0 && unit.contains('IRR')) {
            price = price / 10.0;
          }
          final change = double.tryParse('${gold['change24h']}');
          return (price: price, change24h: change);
        }
      }
    } catch (_) {}
    return (price: null, change24h: null);
  }
}
