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
        onSell: open ? () => showSellTradeDialog(context, list[i]) : null,
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

class AssetChoice {
  AssetChoice(this.id, this.name);
  final int id;
  final String name;
}

class _TradeTile extends StatelessWidget {
  const _TradeTile({required this.trade, required this.open, this.onSell});
  final Trade trade;
  final bool open;
  final VoidCallback? onSell;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final pnl = trade.realizedPnl;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
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
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              'مقدار: ${formatNumber(trade.quantity, decimals: 4)}',
              'خرید: ${formatMoney(trade.buyPrice)}',
              if (!open && trade.sellPrice != null)
                'فروش: ${formatMoney(trade.sellPrice!)}',
            ].join('  ·  '),
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          Text(
            open
                ? 'تاریخ خرید: ${formatDisplayDate(trade.buyDate, state.settings.calendar)}'
                : 'فروش: ${formatDisplayDate(trade.sellDate, state.settings.calendar)}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
          if (!open && pnl != null) ...[
            const SizedBox(height: 4),
            Text(
              formatMoney(pnl, showSign: true),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: pnl >= 0 ? AppTheme.positive : AppTheme.negative,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (onSell != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onSell,
                icon: const Icon(Icons.sell, size: 18),
                label: const Text('فروش'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
