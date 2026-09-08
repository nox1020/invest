import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invest/domain/models/commodity_quote.dart';
import 'package:invest/domain/models/price_alert.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/settings_ui.dart';
import 'package:provider/provider.dart';

Future<void> showPriceAlertEditor(
  BuildContext context, {
  required String id,
  String name = '',
  String symbol = '',
  String unit = 'toman',
  double? currentPrice,
}) async {
  final state = context.read<AppState>();
  if (state.readOnlyOffline) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('در حالت آفلاین ذخیره ممکن نیست')),
    );
    return;
  }
  final existing = state.settings.alertFor(
    id,
    name: name,
    symbol: symbol,
    unit: unit,
  );
  final saved = await showModalBottomSheet<PriceAlert>(
    context: context,
    isScrollControlled: true,
    backgroundColor: tgSettingsGroupBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => _PriceAlertSheet(
      initial: existing,
      currentPrice: currentPrice,
    ),
  );
  if (saved == null || !context.mounted) return;
  if (saved.isArmed) {
    final ok = await NotificationService.instance.requestPermission();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اجازه اعلان در تنظیمات سیستم داده نشد'),
        ),
      );
    }
  }
  final next = state.settings.copyWith();
  next.upsertAlert(saved);
  if (!next.notifyPriceMoves) next.notifyPriceMoves = true;
  if (!next.notificationsEnabled) next.notificationsEnabled = true;
  try {
    await state.saveSettings(next);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved.isArmed ? 'آستانه قیمت ذخیره شد' : 'آستانه قیمت حذف شد',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ذخیره ناموفق: $e')),
    );
  }
}

/// Compact bell that opens the high/low threshold editor for a quote.
class QuoteAlertBell extends StatelessWidget {
  const QuoteAlertBell({
    super.key,
    required this.quote,
    this.iconSize = 20,
    this.color,
  });

  final CommodityQuote quote;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final armed = state.settings.alertFor(quote.id).isArmed;
    return IconButton(
      tooltip: armed ? 'ویرایش آستانه قیمت' : 'تنظیم آستانه قیمت',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: () => showPriceAlertEditor(
        context,
        id: quote.id,
        name: quote.name,
        symbol: quote.symbol,
        unit: quote.unit,
        currentPrice: quote.price,
      ),
      icon: Icon(
        armed
            ? Icons.notifications_active_rounded
            : Icons.notifications_outlined,
        size: iconSize,
        color: color ?? (armed ? const Color(0xFFFF9500) : AppTheme.muted),
      ),
    );
  }
}

class _PriceAlertSheet extends StatefulWidget {
  const _PriceAlertSheet({
    required this.initial,
    this.currentPrice,
  });

  final PriceAlert initial;
  final double? currentPrice;

  @override
  State<_PriceAlertSheet> createState() => _PriceAlertSheetState();
}

class _PriceAlertSheetState extends State<_PriceAlertSheet> {
  late bool _enabled;
  late final TextEditingController _above;
  late final TextEditingController _below;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initial.enabled && widget.initial.hasThreshold
        ? true
        : widget.initial.enabled;
    _above = TextEditingController(
      text: _seed(widget.initial.above),
    );
    _below = TextEditingController(
      text: _seed(widget.initial.below),
    );
  }

  String _seed(double? v) {
    if (v == null || v <= 0) return '';
    if (v >= 1000) return formatNumber(v, decimals: 0);
    return formatNumber(v, decimals: v >= 1 ? 2 : 4);
  }

  @override
  void dispose() {
    _above.dispose();
    _below.dispose();
    super.dispose();
  }

  String get _unitHint {
    switch (widget.initial.unit) {
      case 'usd':
        return 'دلار';
      case 'toman_per_gram':
        return 'تومان / گرم';
      default:
        return 'تومان';
    }
  }

  void _submit() {
    final above = parseFlexibleNumber(_above.text);
    final below = parseFlexibleNumber(_below.text);
    Navigator.pop(
      context,
      PriceAlert(
        id: widget.initial.id,
        name: widget.initial.name,
        symbol: widget.initial.symbol,
        unit: widget.initial.unit,
        enabled: _enabled &&
            ((above != null && above > 0) || (below != null && below > 0)),
        above: (above != null && above > 0) ? above : null,
        below: (below != null && below > 0) ? below : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final price = widget.currentPrice;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.muted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'اعلان قیمت ${widget.initial.displayName}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.title,
            ),
          ),
          if (price != null && price > 0) ...[
            const SizedBox(height: 6),
            Text(
              'قیمت فعلی: ${_formatCurrent(price)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.muted),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('فعال'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          TextField(
            controller: _above,
            enabled: _enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹٠-٩.,٬٫]')),
            ],
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: 'اگر بالاتر از ( $_unitHint )',
              hintText: price != null ? _seed(price) : null,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _below,
            enabled: _enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹٠-٩.,٬٫]')),
            ],
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: 'اگر پایین‌تر از ( $_unitHint )',
              hintText: price != null ? _seed(price) : null,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            child: const Text('ذخیره'),
          ),
          TextButton(
            onPressed: () {
              _above.clear();
              _below.clear();
              _submit();
            },
            child: const Text('حذف آستانه'),
          ),
        ],
      ),
    );
  }

  String _formatCurrent(double v) {
    switch (widget.initial.unit) {
      case 'usd':
        return formatUsd(v);
      case 'toman_per_gram':
        return '${formatNumber(v, decimals: 0)} ت/گرم';
      default:
        return formatMoney(v);
    }
  }
}
