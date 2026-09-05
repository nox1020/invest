import 'package:flutter/material.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

class TradesPage extends StatelessWidget {
  const TradesPage({super.key, required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final list = open ? state.openTrades : state.closedTrades;
    if (list.isEmpty) {
      return Center(child: Text(open ? 'معامله بازی نیست' : 'معامله بسته‌ای نیست'));
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: shellPagePadding(extraForFab: open),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _TradeTile(
        trade: list[i],
        open: open,
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

Future<void> showBuyTradeDialog(BuildContext context) async {
  final state = context.read<AppState>();
  if (state.assets.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ابتدا یک دارایی بسازید')),
    );
    return;
  }
  AssetChoice? choice = AssetChoice(state.assets.first.id!, state.assets.first.name);
  final qtyCtrl = TextEditingController(text: '1');
  final priceCtrl = TextEditingController(
    text: '${state.assets.first.currentPrice}',
  );
  final feeCtrl = TextEditingController(text: '0');

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('ثبت خرید'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  });
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
                decoration: const InputDecoration(labelText: 'قیمت خرید'),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
              ),
              TextField(
                controller: feeCtrl,
                decoration: const InputDecoration(labelText: 'کارمزد'),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await state.tradeService.registerBuy(
      assetId: choice!.id,
      quantity: double.parse(qtyCtrl.text),
      buyPrice: double.parse(priceCtrl.text),
      buyFee: double.tryParse(feeCtrl.text) ?? 0,
    );
    await state.refresh();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

Future<void> showSellTradeDialog(BuildContext context, Trade trade) async {
  final qtyCtrl = TextEditingController(text: '${trade.quantity}');
  final priceCtrl = TextEditingController(
    text: trade.currentPrice > 0 ? '${trade.currentPrice}' : '${trade.buyPrice}',
  );
  final feeCtrl = TextEditingController(text: '0');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
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
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('فروش')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final state = context.read<AppState>();
  try {
    await state.tradeService.closeTrade(
      tradeId: trade.id!,
      sellPrice: double.parse(priceCtrl.text),
      sellFee: double.tryParse(feeCtrl.text) ?? 0,
      quantity: double.parse(qtyCtrl.text),
    );
    await state.refresh();
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
  final noteCtrl = TextEditingController(text: trade.buyNote);
  var buyDate = trade.buyDate.isEmpty ? todayIso() : trade.buyDate;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
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
                decoration: const InputDecoration(labelText: 'قیمت خرید'),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
              ),
              TextField(
                controller: feeCtrl,
                decoration: const InputDecoration(labelText: 'کارمزد'),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تاریخ خرید'),
                subtitle: Text(
                  formatDisplayDate(buyDate, state.settings.calendar),
                ),
                trailing: const Icon(Icons.calendar_today_outlined, size: 18),
                onTap: () async {
                  final initial = parseIsoDate(buyDate);
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: initial,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked == null) return;
                  setLocal(() {
                    buyDate =
                        '${picked.year.toString().padLeft(4, '0')}-'
                        '${picked.month.toString().padLeft(2, '0')}-'
                        '${picked.day.toString().padLeft(2, '0')}';
                  });
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
      ),
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
    this.onSell,
    this.onEdit,
    this.onDelete,
  });
  final Trade trade;
  final bool open;
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
          _TradeDetailRow(label: 'مقدار', value: qtyText),
          _TradeDetailRow(
            label: 'قیمت خرید',
            value: formatMoney(trade.buyPrice),
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
