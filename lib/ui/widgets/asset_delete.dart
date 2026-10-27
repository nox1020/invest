import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/user_error.dart';
import 'package:provider/provider.dart';

/// Asks first, saying exactly what goes (the asset, its open lots and its
/// closed history), then deletes. Works offline: the change waits in the
/// outbox and the asset disappears from totals at once. Returns true when
/// the asset was removed.
Future<bool> confirmDeleteAsset(BuildContext context, Asset asset) async {
  final state = context.read<AppState>();
  final id = asset.id;
  if (id == null) return false;
  final open = state.openTrades.where((t) => t.assetId == id && t.quantity > 1e-9).toList();
  final closed = state.closedTrades.where((t) => t.assetId == id).length;
  final qty = open.fold<double>(0, (s, t) => s + t.quantity);
  final value = qty * asset.currentPrice;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('حذف دارایی «${asset.name}»'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('این موارد برای همیشه حذف می‌شوند:', textAlign: TextAlign.right),
            const SizedBox(height: 8),
            Text('• خود دارایی «${asset.name}»', textAlign: TextAlign.right),
            Text(
              open.isEmpty
                  ? '• معامله باز ندارد'
                  : '• ${open.length} معامله باز (موجودی ${formatNumber(qty, decimals: qty == qty.roundToDouble() ? 0 : 4)}'
                      '${value > 0 ? '، ارزش حدود ${formatMoney(value)}' : ''})',
              key: const ValueKey('asset-delete-open'),
              textAlign: TextAlign.right,
            ),
            Text(
              closed == 0 ? '• تاریخچه معامله بسته ندارد' : '• $closed معامله بسته از تاریخچه و سود/زیان آن',
              key: const ValueKey('asset-delete-closed'),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 10),
            const Text(
              'جمع دارایی‌ها، سود و زیان و داشبورد بدون این دارایی محاسبه می‌شوند. این کار قابل بازگشت نیست.',
              textAlign: TextAlign.right,
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          ElevatedButton(
            key: const ValueKey('asset-delete-confirm'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.negative, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف دارایی و معاملات'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await state.tradeService.deleteAsset(id);
    try {
      await state.refresh();
    } catch (_) {}
    messenger?.showSnackBar(SnackBar(content: Text('دارایی «${asset.name}» حذف شد')));
    return true;
  } catch (e) {
    if (context.mounted) showUserError(context, e);
    return false;
  }
}
