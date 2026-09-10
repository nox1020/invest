import 'package:flutter/material.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/models/trade.dart';
import 'package:invest/domain/models/profit_alert.dart';
import 'package:invest/domain/services/buy_usd_suggest.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/domain/utils/buy_usd.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/app_date_picker.dart';
import 'package:invest/ui/widgets/profit_alert_sheet.dart';
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
            .where((t) => t.assetId == assetId && (!open || t.quantity > 1e-9))
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

    final pad =
        shrinkWrap ? EdgeInsets.zero : shellPagePadding(extraForFab: open);
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: pad,
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
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

String _formatFxField(double fx) => formatBuyFxField(fx);

double? _parseOptionalPositive(String raw) {
  final t = raw.trim().replaceAll(',', '');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v <= 0) return null;
  return v;
}

bool _assetIsCrypto(Asset asset) =>
    detectAssetKind(
      name: asset.name,
      symbol: asset.symbol,
      notes: asset.notes,
    ) ==
    AssetKind.crypto;

Asset? _assetById(List<Asset> assets, int? id) {
  if (id == null) return null;
  for (final a in assets) {
    if (a.id == id) return a;
  }
  return null;
}

bool _tradeIsCrypto(Trade trade, List<Asset> assets) {
  final a = _assetById(assets, trade.assetId);
  if (a != null) return _assetIsCrypto(a);
  return detectAssetKind(
        name: trade.assetName,
        symbol: trade.assetSymbol,
      ) ==
      AssetKind.crypto;
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
  final fxCtrl = TextEditingController();
  var buyDate = todayIso();
  var usdManual = false;
  var fxManual = false;
  var suggestGen = 0;
  var suggesting = false;
  var kickedOff = false;
  final calendar = state.settings.calendar;
  final lockAsset = locked != null;

  bool isCrypto() {
    final a = _assetById(state.assets, choice?.id);
    return a != null && _assetIsCrypto(a);
  }

  void fillUsdFromFx() {
    if (usdManual) return;
    final p = _parseOptionalPositive(priceCtrl.text);
    final fx = _parseOptionalPositive(fxCtrl.text);
    if (p == null || fx == null) return;
    final u = tomanToUsd(p, fx);
    if (u != null && u > 0) usdCtrl.text = _formatUsdField(u);
  }

  void fillFxFromUsd() {
    if (fxManual) return;
    final p = _parseOptionalPositive(priceCtrl.text);
    final u = _parseOptionalPositive(usdCtrl.text);
    final fx = impliedBuyUsdTmn(buyToman: p ?? 0, buyUsd: u);
    if (fx != null && fx > 0) fxCtrl.text = _formatFxField(fx);
  }

  Future<void> suggestUsdFromPrice(void Function(VoidCallback) setLocal) async {
    final crypto = isCrypto();
    if (crypto) {
      if (fxManual && usdManual) return;
      final gen = ++suggestGen;
      setLocal(() => suggesting = true);
      try {
        if (!fxManual) {
          final fx = await suggestBuyUsdTmn(
            buyDateIso: buyDate,
            liveUsdtFallback: state.liveUsdt ?? state.settings.usdtTmnRate,
          );
          if (gen != suggestGen || fxManual) return;
          if (fx != null && fx > 0) {
            fxCtrl.text = _formatFxField(fx);
          }
        }
        if (gen != suggestGen) return;
        fillUsdFromFx();
      } finally {
        if (gen == suggestGen) setLocal(() => suggesting = false);
      }
      return;
    }
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
        if (!kickedOff) {
          kickedOff = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            suggestUsdFromPrice(setLocal);
          });
        }
        final crypto = isCrypto();
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
                        fxManual = false;
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
                    if (isCrypto() && fxManual) {
                      fillUsdFromFx();
                      setLocal(() {});
                      return;
                    }
                    suggestUsdFromPrice(setLocal);
                  },
                ),
                if (crypto)
                  TextField(
                    controller: fxCtrl,
                    decoration: InputDecoration(
                      labelText: 'قیمت دلار در زمان خرید',
                      hintText: suggesting
                          ? 'در حال خواندن نرخ تتر همان تاریخ…'
                          : 'تومان به‌ازای ۱ دلار — خودکار از تاریخ خرید',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    onChanged: (_) {
                      fxManual = true;
                      fillUsdFromFx();
                      setLocal(() {});
                    },
                  ),
                TextField(
                  controller: usdCtrl,
                  decoration: InputDecoration(
                    labelText: 'بهای دلاری خرید',
                    hintText: suggesting
                        ? 'در حال محاسبه از نرخ همان تاریخ…'
                        : crypto
                            ? 'قیمت خرید ÷ قیمت دلار آن روز — قابل ویرایش'
                            : 'خودکار از نرخ USDT تاریخ خرید — قابل ویرایش',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  onChanged: (_) {
                    usdManual = true;
                    if (crypto) fillFxFromUsd();
                  },
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
                    fxManual = false;
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
      buyUsdTmn: isCrypto() ? _parseOptionalPositive(fxCtrl.text) : null,
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
    text:
        trade.currentPrice > 0 ? '${trade.currentPrice}' : '${trade.buyPrice}',
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
                decoration:
                    const InputDecoration(labelText: 'قیمت فروش (تومان)'),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('فروش')),
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
  final seedFx = trade.resolvedBuyUsdTmn;
  final hasSeedFx = seedFx != null && seedFx > 0;
  final fxCtrl = TextEditingController(
    text: hasSeedFx ? _formatFxField(seedFx) : '',
  );
  final noteCtrl = TextEditingController(text: trade.buyNoteDisplay);
  var buyDate = trade.buyDate.isEmpty ? todayIso() : trade.buyDate;
  var usdManual = hasSeedUsd;
  var fxManual = hasSeedFx;
  var suggestGen = 0;
  var suggesting = false;
  var kickedOff = false;
  final crypto = () {
    final a = _assetById(state.assets, trade.assetId);
    return a != null && _assetIsCrypto(a);
  }();

  void fillUsdFromFx() {
    if (usdManual) return;
    final p = _parseOptionalPositive(priceCtrl.text);
    final fx = _parseOptionalPositive(fxCtrl.text);
    if (p == null || fx == null) return;
    final u = tomanToUsd(p, fx);
    if (u != null && u > 0) usdCtrl.text = _formatUsdField(u);
  }

  void fillFxFromUsd() {
    if (fxManual) return;
    final p = _parseOptionalPositive(priceCtrl.text);
    final u = _parseOptionalPositive(usdCtrl.text);
    final fx = impliedBuyUsdTmn(buyToman: p ?? 0, buyUsd: u);
    if (fx != null && fx > 0) fxCtrl.text = _formatFxField(fx);
  }

  Future<void> suggestUsdFromPrice(void Function(VoidCallback) setLocal) async {
    if (crypto) {
      if (fxManual && usdManual) return;
      final gen = ++suggestGen;
      setLocal(() => suggesting = true);
      try {
        if (!fxManual) {
          final fx = await suggestBuyUsdTmn(
            buyDateIso: buyDate,
            liveUsdtFallback: state.liveUsdt ?? state.settings.usdtTmnRate,
          );
          if (gen != suggestGen || fxManual) return;
          if (fx != null && fx > 0) {
            fxCtrl.text = _formatFxField(fx);
          }
        }
        if (gen != suggestGen) return;
        fillUsdFromFx();
      } finally {
        if (gen == suggestGen) setLocal(() => suggesting = false);
      }
      return;
    }
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
        if (!kickedOff && (!hasSeedUsd || (crypto && !hasSeedFx))) {
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
                    if (crypto && fxManual) {
                      fillUsdFromFx();
                      setLocal(() {});
                      return;
                    }
                    suggestUsdFromPrice(setLocal);
                  },
                ),
                if (crypto)
                  TextField(
                    controller: fxCtrl,
                    decoration: InputDecoration(
                      labelText: 'قیمت دلار در زمان خرید',
                      hintText: suggesting
                          ? 'در حال خواندن نرخ تتر همان تاریخ…'
                          : 'تومان به‌ازای ۱ دلار — خودکار از تاریخ خرید',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    onChanged: (_) {
                      fxManual = true;
                      fillUsdFromFx();
                      setLocal(() {});
                    },
                  ),
                TextField(
                  controller: usdCtrl,
                  decoration: InputDecoration(
                    labelText: 'بهای دلاری خرید',
                    hintText: suggesting
                        ? 'در حال محاسبه از نرخ همان تاریخ…'
                        : crypto
                            ? 'قیمت خرید ÷ قیمت دلار آن روز — قابل ویرایش'
                            : 'خودکار از نرخ USDT تاریخ خرید — قابل ویرایش',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  onChanged: (_) {
                    usdManual = true;
                    if (crypto) fillFxFromUsd();
                  },
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
                    fxManual = false;
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
      buyUsdTmn: crypto ? _parseOptionalPositive(fxCtrl.text) : null,
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
    if (open) {
      return _OpenTradeCard(
        trade: trade,
        showAssetIdentity: showAssetIdentity,
        onSell: onSell,
        onEdit: onEdit,
      );
    }

    final state = context.read<AppState>();
    final qtyDecimals =
        (trade.quantity - trade.quantity.roundToDouble()).abs() < 1e-9 ? 0 : 4;
    final qtyText = formatNumber(trade.quantity, decimals: qtyDecimals);
    final closedPnl = trade.realizedPnl;
    final note = trade.buyNoteDisplay.trim();

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
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: 12,
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: AppTheme.border),
            ),
          ],
          _TradeDetailRow(label: 'مقدار', value: qtyText),
          _TradeDetailRow(
            label: 'قیمت خرید',
            value: formatTomanPrice(trade.buyPrice),
            secondary: trade.buyPriceUsd != null && trade.buyPriceUsd! > 0
                ? formatUsd(trade.buyPriceUsd!)
                : null,
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
          if (note.isNotEmpty)
            _TradeDetailRow(
              label: 'یادداشت',
              value: note,
            ),
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

class _OpenTradeCard extends StatelessWidget {
  const _OpenTradeCard({
    required this.trade,
    required this.showAssetIdentity,
    this.onSell,
    this.onEdit,
  });

  final Trade trade;
  final bool showAssetIdentity;
  final VoidCallback? onSell;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final qtyDecimals =
        (trade.quantity - trade.quantity.roundToDouble()).abs() < 1e-9 ? 0 : 4;
    final qtyText = formatNumber(trade.quantity, decimals: qtyDecimals);
    final pnl = trade.unrealizedPnl;
    final pct = trade.unrealizedPnlPct;
    final up = pnl >= 0;
    final tone = up ? AppTheme.positive : AppTheme.negative;
    final usdt = state.liveUsdt ?? state.settings.usdtTmnRate;
    final currentUsd = tomanToUsd(trade.currentPrice, usdt);
    final buyUsd = trade.buyPriceUsd != null && trade.buyPriceUsd! > 0
        ? trade.buyPriceUsd
        : null;
    final date = formatDisplayDate(trade.buyDate, state.settings.calendar);
    final note = trade.buyNoteDisplay.trim();
    final meta = [
      if (!showAssetIdentity) qtyText,
      if (date != '—') date,
      _formatOpenDays(trade.openDays),
    ].join(' · ');

    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showOpenTradeDetails(
          context,
          trade: trade,
          onSell: onSell,
          onEdit: onEdit,
        ),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: tone),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    showAssetIdentity
                                        ? trade.assetName
                                        : '$qtyText واحد',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.title,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    showAssetIdentity
                                        ? [
                                            qtyText,
                                            if (trade.assetSymbol
                                                .trim()
                                                .isNotEmpty)
                                              trade.assetSymbol.trim(),
                                            meta,
                                          ].join(' · ')
                                        : meta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      color: AppTheme.muted,
                                      fontSize: 11,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (trade.id != null)
                              ProfitAlertBell(
                                id: ProfitAlert.forTrade(trade.id!),
                                name: trade.assetName,
                                symbol: trade.assetSymbol,
                                currentPnl: pnl,
                                currentPnlPct: pct,
                              ),
                            _PnlBadge(pct: pct, tone: tone, up: up),
                            const Icon(
                              Icons.chevron_left_rounded,
                              color: AppTheme.muted,
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _PriceCell(
                                label: 'خرید',
                                price: formatTomanPrice(trade.buyPrice),
                                usd: buyUsd == null ? null : formatUsd(buyUsd),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(
                                Icons.west_rounded,
                                size: 16,
                                color: tone.withValues(alpha: 0.85),
                              ),
                            ),
                            Expanded(
                              child: _PriceCell(
                                label: 'اکنون',
                                price: formatTomanPrice(trade.currentPrice),
                                usd: currentUsd == null
                                    ? null
                                    : formatUsd(currentUsd),
                                emphasize: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              'ارزش ${formatMoney(trade.currentValue)}',
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              formatMoney(pnl, showSign: true),
                              style: TextStyle(
                                color: tone,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (onSell != null || onEdit != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              if (onSell != null)
                                Expanded(
                                  child: FilledButton(
                                    onPressed: onSell,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.accent,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      visualDensity: VisualDensity.compact,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text('فروش'),
                                  ),
                                ),
                              if (onSell != null && onEdit != null)
                                const SizedBox(width: 8),
                              if (onEdit != null)
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: onEdit,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.title,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      visualDensity: VisualDensity.compact,
                                      side: const BorderSide(
                                          color: AppTheme.border),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text('ویرایش'),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showOpenTradeDetails(
  BuildContext context, {
  required Trade trade,
  VoidCallback? onSell,
  VoidCallback? onEdit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _OpenTradeDetailsSheet(
      trade: trade,
      onSell: onSell == null
          ? null
          : () {
              Navigator.pop(ctx);
              onSell();
            },
      onEdit: onEdit == null
          ? null
          : () {
              Navigator.pop(ctx);
              onEdit();
            },
    ),
  );
}

class _OpenTradeDetailsSheet extends StatelessWidget {
  const _OpenTradeDetailsSheet({
    required this.trade,
    this.onSell,
    this.onEdit,
  });

  final Trade trade;
  final VoidCallback? onSell;
  final VoidCallback? onEdit;

  Trade _live(AppState state) {
    final id = trade.id;
    if (id == null) return trade;
    for (final t in state.openTrades) {
      if (t.id == id) return t;
    }
    return trade;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = _live(state);
    final qtyDecimals =
        (t.quantity - t.quantity.roundToDouble()).abs() < 1e-9 ? 0 : 4;
    final qtyText = formatNumber(t.quantity, decimals: qtyDecimals);
    final pnl = t.unrealizedPnl;
    final pct = t.unrealizedPnlPct;
    final up = pnl >= 0;
    final tone = up ? AppTheme.positive : AppTheme.negative;
    final usdt = state.liveUsdt ?? state.settings.usdtTmnRate;
    final currentUsd = tomanToUsd(t.currentPrice, usdt);
    final buyUsd =
        t.buyPriceUsd != null && t.buyPriceUsd! > 0 ? t.buyPriceUsd : null;
    final note = t.buyNoteDisplay.trim();
    final crypto = _tradeIsCrypto(t, state.assets);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text(
                    'جزئیات معامله',
                    style: TextStyle(
                      color: AppTheme.title,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  _PnlBadge(pct: pct, tone: tone, up: up),
                  if (t.id != null)
                    ProfitAlertBell(
                      id: ProfitAlert.forTrade(t.id!),
                      name: t.assetName,
                      symbol: t.assetSymbol,
                      currentPnl: pnl,
                      currentPnlPct: pct,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                t.assetName,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppTheme.title,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              if (t.assetSymbol.trim().isNotEmpty)
                Text(
                  t.assetSymbol,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      up ? 'سود باز' : 'زیان باز',
                      style: TextStyle(
                        color: tone,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMoney(pnl, showSign: true),
                      style: TextStyle(
                        color: tone,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PriceCell(
                      label: 'خرید',
                      price: formatTomanPrice(t.buyPrice),
                      usd: buyUsd == null ? null : formatUsd(buyUsd),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.west_rounded,
                      size: 16,
                      color: tone.withValues(alpha: 0.85),
                    ),
                  ),
                  Expanded(
                    child: _PriceCell(
                      label: 'اکنون',
                      price: formatTomanPrice(t.currentPrice),
                      usd: currentUsd == null ? null : formatUsd(currentUsd),
                      emphasize: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DetailFact(label: 'مقدار', value: qtyText),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DetailFact(
                      label: 'مدت باز بودن',
                      value: _formatOpenDays(t.openDays),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DetailFact(
                      label: 'هزینه خرید',
                      value: formatMoney(t.buyCost),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DetailFact(
                      label: 'ارزش فعلی',
                      value: formatMoney(t.currentValue),
                    ),
                  ),
                ],
              ),
              if (t.buyFee > 0) ...[
                const SizedBox(height: 8),
                _DetailFact(
                  label: 'کارمزد خرید',
                  value: formatMoney(t.buyFee),
                ),
              ],
              if (crypto && t.resolvedBuyUsdTmn != null) ...[
                const SizedBox(height: 8),
                _DetailFact(
                  label: 'قیمت دلار زمان خرید',
                  value: formatTomanPrice(t.resolvedBuyUsdTmn!),
                ),
              ],
              const SizedBox(height: 8),
              _DetailFact(
                label: 'تاریخ خرید',
                value: formatDisplayDate(t.buyDate, state.settings.calendar),
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 8),
                _DetailFact(label: 'یادداشت', value: note),
              ],
              if (onSell != null || onEdit != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (onSell != null)
                      Expanded(
                        child: FilledButton(
                          onPressed: onSell,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('فروش'),
                        ),
                      ),
                    if (onSell != null && onEdit != null)
                      const SizedBox(width: 8),
                    if (onEdit != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onEdit,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.title,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: AppTheme.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('ویرایش'),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailFact extends StatelessWidget {
  const _DetailFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.title,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PnlBadge extends StatelessWidget {
  const _PnlBadge({
    required this.pct,
    required this.tone,
    required this.up,
  });

  final double pct;
  final Color tone;
  final bool up;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
            size: 18,
            color: tone,
          ),
          Text(
            formatPct(pct),
            style: TextStyle(
              color: tone,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceCell extends StatelessWidget {
  const _PriceCell({
    required this.label,
    required this.price,
    this.usd,
    this.emphasize = false,
  });

  final String label;
  final String price;
  final String? usd;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            price,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: emphasize ? AppTheme.title : AppTheme.text,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (usd != null) ...[
            const SizedBox(height: 2),
            Text(
              usd!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
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
    this.secondary,
    this.pct,
  });

  final String label;
  final String value;
  final String? secondary;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: tone,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (secondary != null)
                  Text(
                    secondary!,
                    textAlign: TextAlign.left,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: tone == AppTheme.title ? AppTheme.muted : tone,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
