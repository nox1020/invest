import 'package:flutter/material.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/services/buy_usd_suggest.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/app_date_picker.dart';
import 'package:provider/provider.dart';

class TradesPage extends StatelessWidget {
  const TradesPage({
    super.key,
    required this.open,
    this.assetId,
    this.shrinkWrap = false,
    this.hideAssetIdentity = false,
  });

  final bool open;
  final int? assetId;
  final bool shrinkWrap;
  final bool hideAssetIdentity;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final raw = open ? state.openTrades : state.closedTrades;
    final list = assetId == null
        ? List<Trade>.from(raw)
        : raw
            .where((t) =>
                t.assetId == assetId &&
                (!open || t.quantity > 1e-9))
            .toList();
    if (open) {
      list.sort((a, b) => a.buyDate.compareTo(b.buyDate));
    } else {
      list.sort((a, b) {
        final sa = a.sellDate ?? '';
        final sb = b.sellDate ?? '';
        final c = sb.compareTo(sa);
        return c != 0 ? c : b.buyDate.compareTo(a.buyDate);
      });
    }
    if (list.isEmpty) {
      final empty = Text(
        open ? 'معامله بازی نیست' : 'معامله بسته‌ای نیست',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.muted),
      );
      if (shrinkWrap) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: empty,
        );
      }
      return Center(child: empty);
    }

    final pad = shrinkWrap
        ? EdgeInsets.zero
        : shellPagePadding(extraForFab: open);
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: pad,
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _TradeTile(
        trade: list[i],
        open: open,
        showAssetIdentity: !hideAssetIdentity,
        onSell: open && state.canMutate
            ? () => showSellTradeDialog(context, list[i])
            : null,
        onEdit: open && state.canMutate
            ? () => showEditOpenTradeDialog(context, list[i])
            : null,
        onDelete: !open && state.canMutate
            ? () => confirmDeleteClosedTrade(context, list[i])
            : null,
      ),
    );
  }
}

/// Open/closed trade lists for a single asset (embedded in detail page).
class AssetTradesSection extends StatefulWidget {
  const AssetTradesSection({super.key, required this.assetId});

  final int assetId;

  @override
  State<AssetTradesSection> createState() => _AssetTradesSectionState();
}

class _AssetTradesSectionState extends State<AssetTradesSection> {
  int _segment = 0; // 0 open, 1 closed

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'معاملات',
          textAlign: TextAlign.right,
          style: TextStyle(
            color: AppTheme.title,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('باز')),
            ButtonSegment(value: 1, label: Text('بسته')),
          ],
          selected: {_segment},
          onSelectionChanged: (value) {
            setState(() => _segment = value.first);
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppTheme.accent;
              }
              return AppTheme.card;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return AppTheme.muted;
            }),
          ),
        ),
        const SizedBox(height: 10),
        TradesPage(
          open: _segment == 0,
          assetId: widget.assetId,
          shrinkWrap: true,
          hideAssetIdentity: true,
        ),
      ],
    );
  }
}

String _formatUsdField(double usd) => formatBuyUsdField(usd);

double? _parseOptionalPositive(String raw) {
  final t = raw.trim().replaceAll(',', '');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v <= 0) return null;
  return v;
}

Future<void> showBuyTradeDialog(
  BuildContext context, {
  int? assetId,
}) async {
  final state = context.read<AppState>();
  if (state.assets.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ابتدا یک دارایی بسازید')),
    );
    return;
  }

  final locked = assetId == null
      ? null
      : () {
          for (final a in state.assets) {
            if (a.id == assetId) return a;
          }
          return null;
        }();

  if (assetId != null && locked == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('دارایی یافت نشد')),
    );
    return;
  }

  final seed = locked ?? state.assets.first;
  AssetChoice? choice = AssetChoice(seed.id!, seed.name);
  final qtyCtrl = TextEditingController(text: '1');
  final priceCtrl = TextEditingController(
    text: '${seed.currentPrice}',
  );
  final feeCtrl = TextEditingController(text: '0');
  final usdCtrl = TextEditingController();
  var buyDate = todayIso();
  var usdManual = false;
  var suggestGen = 0;
  var suggesting = false;
  var kickedOff = false;
  final calendar = state.settings.calendar;
  final lockAsset = locked != null;

  Future<void> suggestUsdFromPrice(void Function(VoidCallback) setLocal) async {
    if (usdManual) return;
    final p = double.tryParse(priceCtrl.text.replaceAll(',', ''));
    if (p == null || p <= 0) return;
    final gen = ++suggestGen;
    setLocal(() => suggesting = true);
    try {
      final u = await suggestBuyPriceUsd(
        buyPriceToman: p,
        buyDateIso: buyDate,
        liveUsdtFallback: state.liveUsdt ?? state.settings.usdtTmnRate,
      );
      if (gen != suggestGen || usdManual) return;
      if (u != null && u > 0) {
        usdCtrl.text = _formatUsdField(u);
      }
    } finally {
      if (gen == suggestGen) setLocal(() => suggesting = false);
    }
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        if (!kickedOff && !usdManual) {
          kickedOff = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            suggestUsdFromPrice(setLocal);
          });
        }
        return AlertDialog(
          title: const Text('ثبت خرید'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lockAsset)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('دارایی'),
                    subtitle: Text(choice!.name),
                  )
                else
                  DropdownButtonFormField<int>(
                    key: ValueKey(choice!.id),
                    initialValue: choice!.id,
                    items: state.assets
                        .map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name),
                            ))
                        .toList(),
                    onChanged: (v) {
                      final a = state.assets.firstWhere((e) => e.id == v);
                      setLocal(() {
                        choice = AssetChoice(a.id!, a.name);
                        priceCtrl.text = '${a.currentPrice}';
                        usdManual = false;
                      });
                      suggestUsdFromPrice(setLocal);
                    },
                    decoration: const InputDecoration(labelText: 'دارایی'),
                  ),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'مقدار'),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                ),
                TextField(
                  controller: priceCtrl,
                  decoration:
                      const InputDecoration(labelText: 'قیمت خرید (تومان)'),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  onChanged: (_) {
                    usdManual = false;
                    suggestUsdFromPrice(setLocal);
                  },
                ),
                TextField(
                  controller: usdCtrl,
                  decoration: InputDecoration(
                    labelText: 'بهای دلاری خرید',
                    hintText: suggesting
                        ? 'در حال محاسبه از نرخ همان تاریخ…'
                        : 'خودکار از نرخ USDT تاریخ خرید — قابل ویرایش',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  onChanged: (_) => usdManual = true,
                ),
                TextField(
                  controller: feeCtrl,
                  decoration: const InputDecoration(labelText: 'کارمزد'),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                ),
                AppDateTile(
                  label: 'تاریخ خرید',
                  isoDate: buyDate,
                  calendar: calendar,
                  onChanged: (v) {
                    setLocal(() => buyDate = v);
                    usdManual = false;
                    suggestUsdFromPrice(setLocal);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ثبت'),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await state.tradeService.registerBuy(
      assetId: choice!.id,
      quantity: double.parse(qtyCtrl.text),
      buyPrice: double.parse(priceCtrl.text),
      buyPriceUsd: _parseOptionalPositive(usdCtrl.text),
      buyFee: double.tryParse(feeCtrl.text) ?? 0,
      buyDate: buyDate,
    );
    await state.refresh();
    await state.emitLocalAlert(
      kind: NotificationKind.trades,
      title: 'خرید ثبت شد',
      body: choice!.name,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

Future<void> showSellTradeDialog(BuildContext context, Trade trade) async {
  final state = context.read<AppState>();
  final qtyCtrl = TextEditingController(text: '${trade.quantity}');
  final priceCtrl = TextEditingController(
    text: trade.currentPrice > 0 ? '${trade.currentPrice}' : '${trade.buyPrice}',
  );
  final feeCtrl = TextEditingController(text: '0');
  var sellDate = todayIso();
  final calendar = state.settings.calendar;
  final buyFloor = parseIsoDate(
    trade.buyDate.isEmpty ? todayIso() : trade.buyDate,
  );

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('فروش ${trade.assetName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('حداکثر: ${formatNumber(trade.quantity, decimals: 4)}',
                  textAlign: TextAlign.right),
              TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(labelText: 'مقدار فروش'),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
              ),
              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: 'قیمت فروش'),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
              ),
              TextField(
                controller: feeCtrl,
                decoration: const InputDecoration(labelText: 'کارمزد'),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
              ),
              AppDateTile(
                label: 'تاریخ فروش',
                isoDate: sellDate,
                calendar: calendar,
                firstDate: buyFloor,
                onChanged: (v) => setLocal(() => sellDate = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('فروش')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await state.tradeService.closeTrade(
      tradeId: trade.id!,
      sellPrice: double.parse(priceCtrl.text),
      sellFee: double.tryParse(feeCtrl.text) ?? 0,
      quantity: double.parse(qtyCtrl.text),
      sellDate: sellDate,
    );
    await state.refresh();
    await state.emitLocalAlert(
      kind: NotificationKind.trades,
      title: 'فروش ثبت شد',
      body: trade.assetName,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

Future<void> showEditOpenTradeDialog(BuildContext context, Trade trade) async {
  final state = context.read<AppState>();
  final qtyCtrl = TextEditingController(text: '${trade.quantity}');
  final priceCtrl = TextEditingController(text: '${trade.buyPrice}');
  final feeCtrl = TextEditingController(text: '${trade.buyFee}');
  final hasSeedUsd = trade.buyPriceUsd != null && trade.buyPriceUsd! > 0;
  final usdCtrl = TextEditingController(
    text: hasSeedUsd ? _formatUsdField(trade.buyPriceUsd!) : '',
  );
  final noteCtrl = TextEditingController(text: trade.buyNoteDisplay);
  var buyDate = trade.buyDate.isEmpty ? todayIso() : trade.buyDate;
  var usdManual = hasSeedUsd;
  var suggestGen = 0;
  var suggesting = false;
  var kickedOff = false;

  Future<void> suggestUsdFromPrice(void Function(VoidCallback) setLocal) async {
    if (usdManual) return;
    final p = double.tryParse(priceCtrl.text.replaceAll(',', ''));
    if (p == null || p <= 0) return;
    final gen = ++suggestGen;
    setLocal(() => suggesting = true);
    try {
      final u = await suggestBuyPriceUsd(
        buyPriceToman: p,
        buyDateIso: buyDate,
        liveUsdtFallback: state.liveUsdt ?? state.settings.usdtTmnRate,
      );
      if (gen != suggestGen || usdManual) return;
      if (u != null && u > 0) {
        usdCtrl.text = _formatUsdField(u);
      }
    } finally {
      if (gen == suggestGen) setLocal(() => suggesting = false);
    }
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        if (!hasSeedUsd && !kickedOff && !usdManual) {
          kickedOff = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            suggestUsdFromPrice(setLocal);
          });
        }
        return AlertDialog(
          title: Text('ویرایش ${trade.assetName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'مقدار'),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                ),
                TextField(
                  controller: priceCtrl,
                  decoration:
                      const InputDecoration(labelText: 'قیمت خرید (تومان)'),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  onChanged: (_) {
                    usdManual = false;
                    suggestUsdFromPrice(setLocal);
                  },
                ),
                TextField(
                  controller: usdCtrl,
                  decoration: InputDecoration(
                    labelText: 'بهای دلاری خرید',
                    hintText: suggesting
                        ? 'در حال محاسبه از نرخ همان تاریخ…'
                        : 'خودکار از نرخ USDT تاریخ خرید — قابل ویرایش',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  onChanged: (_) => usdManual = true,
                ),
                TextField(
                  controller: feeCtrl,
                  decoration: const InputDecoration(labelText: 'کارمزد'),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                ),
                AppDateTile(
                  label: 'تاریخ خرید',
                  isoDate: buyDate,
                  calendar: state.settings.calendar,
                  onChanged: (v) {
                    setLocal(() => buyDate = v);
                    usdManual = false;
                    suggestUsdFromPrice(setLocal);
                  },
                ),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'یادداشت'),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ذخیره'),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return;
  final qty = double.tryParse(qtyCtrl.text);
  final price = double.tryParse(priceCtrl.text);
  if (qty == null || price == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('مقدار و قیمت خرید را درست وارد کنید')),
    );
    return;
  }
  try {
    await state.tradeService.updateOpenTrade(
      tradeId: trade.id!,
      quantity: qty,
      buyPrice: price,
      buyPriceUsd: _parseOptionalPositive(usdCtrl.text),
      buyFee: double.tryParse(feeCtrl.text) ?? 0,
      buyDate: buyDate,
      buyNote: noteCtrl.text,
    );
    await state.refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('معامله ویرایش شد')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

Future<void> confirmDeleteClosedTrade(BuildContext context, Trade trade) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('حذف از تاریخچه'),
      content: Text(
        'تاریخچه معامله «${trade.assetName}» حذف شود؟\n'
        'این کار فقط از سوابق حذف می‌کند و موجودی فعلی را تغییر نمی‌دهد.\n'
        'این عمل قابل بازگشت نیست.',
        textAlign: TextAlign.right,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('انصراف'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.negative,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final state = context.read<AppState>();
  try {
    await state.tradeService.deleteClosedTrade(trade.id!);
    await state.refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('معامله از تاریخچه حذف شد')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class AssetChoice {
  AssetChoice(this.id, this.name);
  final int id;
  final String name;
}

class _TradeTile extends StatelessWidget {
  const _TradeTile({
    required this.trade,
    required this.open,
    this.showAssetIdentity = true,
    this.onSell,
    this.onEdit,
    this.onDelete,
  });
  final Trade trade;
  final bool open;
  final bool showAssetIdentity;
  final VoidCallback? onSell;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final qtyDecimals =
        (trade.quantity - trade.quantity.roundToDouble()).abs() < 1e-9 ? 0 : 4;
    final qtyText = formatNumber(trade.quantity, decimals: qtyDecimals);
    final openPnl = trade.unrealizedPnl;
    final closedPnl = trade.realizedPnl;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showAssetIdentity) ...[
            Text(
              trade.assetName,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.title,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            if (trade.assetSymbol.trim().isNotEmpty)
              Text(
                trade.assetSymbol,
                textAlign: TextAlign.right,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: AppTheme.border),
            ),
          ],
          _TradeDetailRow(label: 'مقدار', value: qtyText),
          _TradeDetailRow(
            label: 'قیمت خرید',
            value: formatMoney(trade.buyPrice),
          ),
          if (trade.buyPriceUsd != null && trade.buyPriceUsd! > 0)
            _TradeDetailRow(
              label: 'بهای دلاری خرید',
              value: formatUsd(trade.buyPriceUsd!),
            ),
          if (trade.buyFee > 0)
            _TradeDetailRow(
              label: 'کارمزد خرید',
              value: formatMoney(trade.buyFee),
            ),
          _TradeDetailRow(
            label: 'هزینه خرید',
            value: formatMoney(trade.buyCost),
          ),
          _TradeDetailRow(
            label: 'تاریخ خرید',
            value: formatDisplayDate(trade.buyDate, state.settings.calendar),
          ),
          if (open) ...[
            _TradeDetailRow(
              label: 'مدت باز بودن',
              value: _formatOpenDays(trade.openDays),
            ),
            _TradeDetailRow(
              label: 'قیمت لحظه‌ای',
              value: formatMoney(trade.currentPrice),
            ),
            _TradeDetailRow(
              label: 'ارزش فعلی',
              value: formatMoney(trade.currentValue),
            ),
            _TradeDetailRow(
              label: 'سود/زیان',
              value: formatMoney(openPnl, showSign: true),
              pct: trade.unrealizedPnlPct,
            ),
          ] else ...[
            if (trade.sellPrice != null)
              _TradeDetailRow(
                label: 'قیمت فروش',
                value: formatMoney(trade.sellPrice!),
              ),
            _TradeDetailRow(
              label: 'تاریخ فروش',
              value: formatDisplayDate(trade.sellDate, state.settings.calendar),
            ),
            if (trade.holdingDays != null)
              _TradeDetailRow(
                label: 'مدت نگهداری',
                value: _formatOpenDays(trade.holdingDays!),
              ),
            if (closedPnl != null)
              _TradeDetailRow(
                label: 'سود/زیان',
                value: formatMoney(closedPnl, showSign: true),
                pct: trade.returnPct,
              ),
          ],
          if (trade.buyNote.trim().isNotEmpty)
            _TradeDetailRow(
              label: 'یادداشت',
              value: trade.buyNote.trim(),
            ),
          if (onSell != null || onEdit != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 4,
                children: [
                  if (onEdit != null)
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('ویرایش'),
                    ),
                  if (onSell != null)
                    TextButton.icon(
                      onPressed: onSell,
                      icon: const Icon(Icons.sell, size: 18),
                      label: const Text('فروش'),
                    ),
                ],
              ),
            ),
          ],
          if (onDelete != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onDelete,
                style: TextButton.styleFrom(foregroundColor: AppTheme.negative),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('حذف'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatOpenDays(int days) {
  if (days <= 0) return 'کمتر از یک روز';
  return '${formatNumber(days, decimals: 0)} روز';
}

class _TradeDetailRow extends StatelessWidget {
  const _TradeDetailRow({
    required this.label,
    required this.value,
    this.pct,
  });

  final String label;
  final String value;
  final double? pct;

  @override
  Widget build(BuildContext context) {
    final tone = pct == null
        ? AppTheme.title
        : pct! >= 0
            ? AppTheme.positive
            : AppTheme.negative;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const Spacer(),
          if (pct != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                formatPct(pct!),
                style: TextStyle(
                  color: tone,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: tone,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
