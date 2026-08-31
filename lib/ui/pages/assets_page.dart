import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAssetEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('دارایی جدید'),
      ),
      body: state.assets.isEmpty
          ? const Center(child: Text('هنوز دارایی ثبت نشده'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.assets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final a = state.assets[i];
                return _AssetTile(asset: a);
              },
            ),
    );
  }
}

Future<void> showAssetEditor(BuildContext context, {Asset? edit}) async {
  final nameCtrl = TextEditingController(text: edit?.name ?? '');
  final symbolCtrl = TextEditingController(text: edit?.symbol ?? '');
  final qtyCtrl =
      TextEditingController(text: edit == null ? '0' : '${edit.quantity}');
  final priceCtrl = TextEditingController(
      text: edit == null ? '' : '${edit.avgBuyPrice}');
  final currentCtrl = TextEditingController(
      text: edit == null ? '' : '${edit.currentPrice}');

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(edit == null ? 'افزودن دارایی' : 'ویرایش دارایی'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'نام'),
              textAlign: TextAlign.right,
            ),
            TextField(
              controller: symbolCtrl,
              decoration: const InputDecoration(labelText: 'نماد (مثل GOLD)'),
              textAlign: TextAlign.right,
            ),
            if (edit == null) ...[
              TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(labelText: 'مقدار اولیه'),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
              ),
              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: 'قیمت خرید'),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
              ),
            ],
            TextField(
              controller: currentCtrl,
              decoration: const InputDecoration(labelText: 'قیمت فعلی'),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ذخیره')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final state = context.read<AppState>();
  final svc = state.tradeService;
  try {
    if (edit == null) {
      await svc.createAsset(
        name: nameCtrl.text,
        symbol: symbolCtrl.text,
        quantity: double.tryParse(qtyCtrl.text) ?? 0,
        avgBuyPrice: double.tryParse(priceCtrl.text) ?? 0,
        currentPrice: double.tryParse(currentCtrl.text) ??
            double.tryParse(priceCtrl.text) ??
            0,
      );
    } else {
      edit.name = nameCtrl.text.trim();
      edit.symbol = symbolCtrl.text.trim();
      final cp = double.tryParse(currentCtrl.text);
      if (cp != null) edit.currentPrice = cp;
      await svc.assets.update(edit);
    }
    await state.refresh();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset});
  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final pnl = asset.unrealizedPnl;
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showAssetEditor(context, edit: asset),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                asset.name,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppTheme.title,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (asset.symbol.isNotEmpty) asset.symbol,
                  'مقدار: ${formatNumber(asset.quantity, decimals: 4)}',
                  'ارزش: ${formatMoney(asset.totalValue)}',
                ].join('  ·  '),
                textAlign: TextAlign.right,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'PnL: ${formatMoney(pnl, showSign: true)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: pnl >= 0 ? AppTheme.positive : AppTheme.negative,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
