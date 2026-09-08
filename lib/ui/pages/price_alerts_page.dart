import 'package:flutter/material.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/price_alert.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/price_alert_sheet.dart';
import 'package:invest/ui/widgets/settings_ui.dart';
import 'package:provider/provider.dart';

class PriceAlertsPage extends StatelessWidget {
  const PriceAlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final prices = <String, CommodityQuote>{
      for (final q in [...state.commodityIndex, ...state.wallexMarkets]) q.id: q,
    };
    final extra = state.settings.priceAlerts
        .where((a) => catalogInstrument(a.id) == null)
        .toList();

    return Scaffold(
      backgroundColor: tgSettingsPageBg(context),
      appBar: AppBar(
        title: const Text('آستانه قیمت ارزها'),
        centerTitle: true,
      ),
      body: ListView(
        padding: shellPagePadding(),
        children: [
          TgSettingsSection(
            title: 'ارزها و کالاها',
            children: [
              for (var i = 0; i < priceAlertCatalog.length; i++)
                _AlertRow(
                  instrument: priceAlertCatalog[i],
                  alert: state.settings.alertFor(priceAlertCatalog[i].id),
                  quote: prices[priceAlertCatalog[i].id],
                  showDivider: i != priceAlertCatalog.length - 1 || extra.isNotEmpty,
                ),
              for (var i = 0; i < extra.length; i++)
                _AlertRow(
                  instrument: PriceAlertInstrument(
                    id: extra[i].id,
                    name: extra[i].displayName,
                    symbol: extra[i].symbol,
                    unit: extra[i].unit,
                  ),
                  alert: extra[i],
                  quote: prices[extra[i].id],
                  showDivider: i != extra.length - 1,
                ),
            ],
          ),
          Text(
            'برای هر ارز یک سقف و یک کف به تومان وارد کنید. اعلان فقط وقتی قیمت از آستانه عبور کند یک‌بار فرستاده می‌شود.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.muted.withValues(alpha: 0.8),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.instrument,
    required this.alert,
    this.quote,
    required this.showDivider,
  });

  final PriceAlertInstrument instrument;
  final PriceAlert alert;
  final CommodityQuote? quote;
  final bool showDivider;

  String _priceLabel(double v) {
    switch (instrument.unit) {
      case 'usd':
        return formatUsd(v);
      case 'toman_per_gram':
        return '${formatNumber(v, decimals: 0)} ت/گرم';
      default:
        return formatMoney(v);
    }
  }

  String get _subtitle {
    final parts = <String>[];
    final live = quote?.price;
    if (live != null && live > 0) {
      parts.add('الان ${_priceLabel(live)}');
    }
    if (alert.isArmed) {
      if (alert.above != null) {
        parts.add('بالاتر از ${_priceLabel(alert.above!)}');
      }
      if (alert.below != null) {
        parts.add('پایین‌تر از ${_priceLabel(alert.below!)}');
      }
    } else {
      parts.add('آستانه تنظیم نشده');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return TgSettingsTile(
      icon: CommodityQuote.iconForId(instrument.id),
      iconColor: alert.isArmed ? const Color(0xFFFF9500) : const Color(0xFF8E8E93),
      title: instrument.name,
      subtitle: _subtitle,
      value: alert.isArmed ? 'فعال' : '',
      onTap: () => showPriceAlertEditor(
        context,
        id: instrument.id,
        name: instrument.name,
        symbol: instrument.symbol,
        unit: instrument.unit,
        currentPrice: quote?.price,
      ),
      showDivider: showDivider,
    );
  }
}
