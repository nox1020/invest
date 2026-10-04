import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/services/gold_quote_parser.dart';

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

  /// Iranian 18k gold Toman/gram from free public feeds.
  ///
  /// Order: WallGold → TGJU → optional configured URL (toolbox / override).
  Future<({double? price, double? change24h})> fetchGoldToman({
    String? persianUrl,
  }) async {
    final configured = GoldQuoteParser.resolveConfiguredUrl(persianUrl);
    final urls = <String>{
      AppConfig.defaultGoldApiUrl,
      ...AppConfig.tgjuAjaxFallbackUrls,
      if (!GoldQuoteParser.isStaleGoldUrl(configured)) configured,
    }.toList();

    for (final rawUrl in urls) {
      final quote = await _fetchGoldFromUrl(rawUrl);
      if (quote == null) continue;
      // Never accept understated toolbox-style marks as the live 18k price.
      if (GoldQuoteParser.isUnderstated18kToman(quote.priceToman) &&
          quote.source == 'persiantoolbox') {
        continue;
      }
      return (price: quote.priceToman, change24h: quote.change24hPct);
    }
    return (price: null, change24h: null);
  }

  Future<GoldQuoteParse?> _fetchGoldFromUrl(String rawUrl) async {
    try {
      final res = await _client
          .get(
            Uri.parse(rawUrl),
            headers: const {
              'Accept': 'application/json, text/plain, */*',
              'User-Agent': 'V+/1.0',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      final host = Uri.parse(rawUrl).host.toLowerCase();
      if (host.contains('wallgold')) {
        return GoldQuoteParser.fromWallGold(body);
      }
      if (host.contains('tgju')) {
        return GoldQuoteParser.fromTgju(body);
      }
      if (host.contains('persiantoolbox')) {
        return GoldQuoteParser.fromPersianToolbox(body);
      }
      return GoldQuoteParser.fromAny(body);
    } catch (_) {
      return null;
    }
  }
}
