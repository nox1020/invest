import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:invest/data/biz_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/pwo_page.dart';
import 'package:invest/ui/theme/app_theme.dart';

/// Binds [store] to the signed-in Vinor account, or shows its cache offline.
Future<void> ensureBizReady(BuildContext context, BizStore store,
    {bool refresh = true}) {
  AppState? app;
  try {
    app = Provider.of<AppState>(context, listen: false);
  } catch (_) {
    app = null;
  }
  final phone = (app?.userPhone ?? '').trim();
  final remote = app?.remote;
  if (app != null && app.useRemote && remote != null && phone.isNotEmpty) {
    if (!refresh && store.account == phone && store.isRemote &&
        (store.loaded || store.syncing)) {
      return Future.value();
    }
    return store.bindAccount(remote.biz, phone);
  }
  if (app == null && store.isRemote) return store.refresh();
  return store.loadOffline();
}

String _m(num v) => formatMoney(v);

/// Large amounts shrink to fit instead of overflowing on small phones.
Widget _fit(Widget w) => Flexible(
      child: FittedBox(
          fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerEnd, child: w),
    );

Color _sign(num v) => v < 0 ? AppTheme.negative : AppTheme.positive;

Future<bool> _guard(BuildContext context, Future<void> Function() op) async {
  try {
    await op();
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
    return false;
  }
}

/// «سابقه خرید و فروش ملک» + «جدول ماهانه».
class BizPage extends StatefulWidget {
  const BizPage({super.key, this.store, this.initialTab = 0});
  final BizStore? store;
  final int initialTab;

  @override
  State<BizPage> createState() => _BizPageState();
}

class _BizPageState extends State<BizPage> {
  late final BizStore _store = widget.store ?? BizStore.instance;
  Object? _pwoLedger;

  @override
  void initState() {
    super.initState();
    _pwoLedger = PwoStore.instance.ledger;
    PwoStore.instance.addListener(_onPwo);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureBizReady(context, _store);
    });
  }

  /// PWO column is read from the PWO module on the server: refresh after a
  /// PWO edit so both views agree.
  void _onPwo() {
    final l = PwoStore.instance.ledger;
    if (!identical(l, _pwoLedger) && !PwoStore.instance.syncing) {
      _pwoLedger = l;
      if (_store.isRemote) _store.refresh();
    }
  }

  @override
  void dispose() {
    PwoStore.instance.removeListener(_onPwo);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        initialIndex: widget.initialTab,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('ملک و دفتر'),
            bottom: const TabBar(tabs: [
              Tab(text: 'معاملات ملک'),
              Tab(text: 'جدول ماهانه'),
            ]),
          ),
          body: ListenableBuilder(
            listenable: _store,
            builder: (context, _) {
              final banner = _store.showingCache || _store.lastError != null
                  ? MaterialBanner(
                      content: Text(_store.lastError ??
                          const BizReadOnlyException().toString()),
                      actions: [
                        TextButton(
                            onPressed: () => ensureBizReady(context, _store),
                            child: const Text('تلاش دوباره')),
                      ],
                    )
                  : null;
              if (!_store.loaded) {
                return const Center(child: CircularProgressIndicator());
              }
              return Column(children: [
                if (banner != null) banner,
                if (_store.syncing) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: TabBarView(children: [
                    _TradesTab(store: _store),
                    _MonthsTab(store: _store),
                  ]),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color, this.valueKey});
  final String label;
  final String value;
  final Color? color;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12))),
        const SizedBox(width: 8),
        _fit(Text(value,
            key: valueKey,
            style: TextStyle(
                color: color ?? AppTheme.title,
                fontWeight: FontWeight.w700,
                fontSize: 13))),
      ]);
}

// ---------------------------------------------------------------- trades

class _TradesTab extends StatelessWidget {
  const _TradesTab({required this.store});
  final BizStore store;

  @override
  Widget build(BuildContext context) {
    final s = store.snap;
    final trades = s.trades.reversed.toList();
    return Stack(children: [
      RefreshIndicator(
        onRefresh: store.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  _Stat('جمع سود / زیان', _m(s.totalProfit),
                      color: _sign(s.totalProfit),
                      valueKey: const ValueKey('biz-total-profit')),
                  const SizedBox(height: 6),
                  _Stat('تعداد معاملات', '${trades.length}'),
                  if (s.totalExtraCost > 0) ...[
                    const SizedBox(height: 6),
                    _Stat('جمع کد و نقشه', _m(s.totalExtraCost)),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 10),
            if (!store.readOnly && store.isEmpty) ...[
              OutlinedButton.icon(
                key: const ValueKey('biz-import'),
                onPressed: () => _importSheet(context, store),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('ورود از شیت'),
              ),
              const SizedBox(height: 10),
            ],
            if (trades.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('هنوز معامله‌ای ثبت نشده',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted)),
              ),
            for (final t in trades) ...[
              _TradeTile(store: store, t: t),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      if (!store.readOnly)
        Positioned(
          left: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            key: const ValueKey('biz-add-trade'),
            heroTag: 'biz-add-trade',
            onPressed: () => _editTrade(context, store, null),
            icon: const Icon(Icons.add),
            label: const Text('ثبت معامله'),
          ),
        ),
    ]);
  }
}

class _TradeTile extends StatelessWidget {
  const _TradeTile({required this.store, required this.t});
  final BizStore store;
  final PropertyTrade t;

  @override
  Widget build(BuildContext context) {
    final p = t.profit;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: store.readOnly ? null : () => _editTrade(context, store, t),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text(t.title.isEmpty ? 'بدون عنوان' : t.title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 8),
                _fit(Text(p == null ? 'فروش نرفته' : _m(p),
                    style: TextStyle(
                        color: p == null ? AppTheme.muted : _sign(p),
                        fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 12, runSpacing: 4, children: [
                _kv('خرید', '${t.buyDate} · ${_m(t.buyAmount)}'),
                if (t.sellDate.isNotEmpty)
                  _kv('فروش', '${t.sellDate} · ${_m(t.sellAmount)}'),
                if (t.area != null) _kv('متراژ', formatNumber(t.area!, decimals: t.area! % 1 == 0 ? 0 : 2)),
                if (t.days != null) _kv('زمان', '${t.days} روز'),
                if (t.profitPct != null)
                  _kv('درصد سود/زیان', '${t.profitPct!.round()}٪'),
                if (t.extraCost > 0) _kv('کد و نقشه', _m(t.extraCost)),
              ]),
              if (t.note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(t.note,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Text('$k: $v',
      style: const TextStyle(color: AppTheme.muted, fontSize: 12));
}

Future<void> _importSheet(BuildContext context, BizStore store) async {
  final ctl = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (c) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('ورود از شیت'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'متن JSON شیت را اینجا بچسبانید. فقط یک بار و فقط روی حساب خالی اعمال می‌شود؛ دادهٔ موجود هرگز بازنویسی نمی‌شود.',
            style: TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('biz-import-text'),
            controller: ctl,
            maxLines: 6,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
                hintText: '{"trades": [...], "months": [...]}', isDense: true),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if (d?.text != null) ctl.text = d!.text!;
              },
              icon: const Icon(Icons.content_paste_rounded, size: 16),
              label: const Text('چسباندن از کلیپ‌بورد'),
            ),
          ),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('انصراف')),
          FilledButton(
              key: const ValueKey('biz-import-go'),
              onPressed: () => Navigator.pop(c, ctl.text),
              child: const Text('ورود')),
        ],
      ),
    ),
  );
  // Controller is left to GC: the dialog may still be animating out.
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  int n = 0;
  final ok = await _guard(context, () async => n = await store.importSheet(text));
  if (ok && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'این حساب از قبل داده دارد؛ چیزی وارد نشد.'
            : '$n ردیف از شیت وارد شد.')));
  }
}

String _amountText(double v) => v == 0 ? '' : formatNumber(v);

Future<void> _editTrade(
    BuildContext context, BizStore store, PropertyTrade? t) async {
  final res = await showDialog<_DialogResult>(
    context: context,
    builder: (_) => _TradeDialog(t: t),
  );
  if (res == null || !context.mounted) return;
  if (res.delete && t != null) {
    await _guard(context, () => store.deleteTrade(t.id));
  } else if (t == null) {
    await _guard(context, () => store.addTrade(res.body));
  } else {
    await _guard(context, () => store.updateTrade(t.id, res.body));
  }
}

class _DialogResult {
  _DialogResult(this.body, {this.delete = false});
  final Map<String, dynamic> body;
  final bool delete;
}

class _TradeDialog extends StatefulWidget {
  const _TradeDialog({this.t});
  final PropertyTrade? t;

  @override
  State<_TradeDialog> createState() => _TradeDialogState();
}

class _TradeDialogState extends State<_TradeDialog> {
  late final _buyDate = TextEditingController(text: widget.t?.buyDate ?? '');
  late final _sellDate = TextEditingController(text: widget.t?.sellDate ?? '');
  late final _buy = TextEditingController(text: _amountText(widget.t?.buyAmount ?? 0));
  late final _sell = TextEditingController(text: _amountText(widget.t?.sellAmount ?? 0));
  late final _area = TextEditingController(
      text: widget.t?.area == null ? '' : formatNumber(widget.t!.area!, decimals: widget.t!.area! % 1 == 0 ? 0 : 2));
  late final _title = TextEditingController(text: widget.t?.title ?? '');
  late final _extra = TextEditingController(text: _amountText(widget.t?.extraCost ?? 0));
  late final _note = TextEditingController(text: widget.t?.note ?? '');
  String? _err;

  @override
  void dispose() {
    for (final c in [_buyDate, _sellDate, _buy, _sell, _area, _title, _extra, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _f(TextEditingController c, String label, {bool num = false, String? hint, Key? key}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: key,
          controller: c,
          keyboardType: num ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
        ),
      );

  void _submit() {
    final buy = parseFlexibleNumber(_buy.text);
    if (_buyDate.text.trim().isEmpty || buy == null || buy <= 0) {
      setState(() => _err = 'تاریخ خرید و مبلغ خرید لازم است.');
      return;
    }
    Navigator.of(context).pop(_DialogResult({
      'buy_date': _buyDate.text.trim(),
      'sell_date': _sellDate.text.trim(),
      'buy_amount': buy,
      'sell_amount': parseFlexibleNumber(_sell.text) ?? 0,
      'area': parseFlexibleNumber(_area.text),
      'title': _title.text.trim(),
      'extra_cost': parseFlexibleNumber(_extra.text) ?? 0,
      'note': _note.text.trim(),
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.t == null ? 'ثبت معامله ملک' : 'ویرایش معامله'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _f(_title, 'نوع دارایی / طرفین', key: const ValueKey('biz-f-title')),
            _f(_buyDate, 'تاریخ خرید', hint: '1405/01/20', key: const ValueKey('biz-f-buy-date')),
            _f(_buy, 'مبلغ خرید (تومان)', num: true, key: const ValueKey('biz-f-buy')),
            _f(_sellDate, 'تاریخ فروش', hint: 'خالی = هنوز فروش نرفته', key: const ValueKey('biz-f-sell-date')),
            _f(_sell, 'مبلغ فروش (تومان)', num: true, key: const ValueKey('biz-f-sell')),
            _f(_area, 'متراژ', num: true),
            _f(_extra, 'کد و نقشه (تومان)', num: true),
            _f(_note, 'یادداشت'),
            if (_err != null)
              Text(_err!, style: const TextStyle(color: AppTheme.negative)),
          ]),
        ),
        actions: [
          if (widget.t != null)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('حذف معامله؟'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  Navigator.of(context).pop(_DialogResult(const {}, delete: true));
                }
              },
              child: const Text('حذف', style: TextStyle(color: AppTheme.negative)),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
              key: const ValueKey('biz-f-save'),
              onPressed: _submit,
              child: const Text('ذخیره')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- months

class _MonthsTab extends StatelessWidget {
  const _MonthsTab({required this.store});
  final BizStore store;

  @override
  Widget build(BuildContext context) {
    final s = store.snap;
    final months = s.months;
    final tot = s.monthTotals;
    final years = s.years;
    final year = s.year;
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (years.length > 1 && year != null)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final y in years.reversed) ...[
                  ChoiceChip(
                    label: Text('$y'),
                    selected: y == year,
                    onSelected: (_) => store.selectYear(y),
                  ),
                  const SizedBox(width: 6),
                ],
              ]),
            ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                _Stat('جمع خالص ${year ?? ''}', _m(tot['net'] ?? 0),
                    color: _sign(tot['net'] ?? 0),
                    valueKey: const ValueKey('biz-total-net')),
                const SizedBox(height: 6),
                _Stat('درآمد', _m(tot['income'] ?? 0)),
                _Stat('کارمندان', _m(tot['staff'] ?? 0)),
                _Stat('PWO', _m(tot['pwo'] ?? 0)),
                _Stat('دیوار - تبلیغات دفتر', _m(tot['ads'] ?? 0)),
                const SizedBox(height: 6),
                const Text(
                  'خالص ماه = درآمد − کارمندان − PWO − تبلیغات · ستون PWO از بخش PWO خوانده می‌شود',
                  style: TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          for (final m in months) ...[
            _MonthTile(store: store, m: m),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({required this.store, required this.m});
  final BizStore store;
  final BizMonth m;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey('biz-month-${m.month}'),
        borderRadius: BorderRadius.circular(12),
        onTap: store.readOnly ? null : () => _editMonth(context, store, m),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('برج ${m.month} · ${pwoMonthNames[m.month - 1]}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              _fit(Text(m.isEmpty ? '—' : _m(m.net),
                  style: TextStyle(
                      color: m.isEmpty ? AppTheme.muted : _sign(m.net),
                      fontWeight: FontWeight.w800))),
            ]),
            if (!m.isEmpty) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 12, runSpacing: 2, children: [
                _t('درآمد ${_m(m.income)}'),
                _t('کارمندان ${_m(m.staff)}'),
                _t('PWO ${_m(m.pwo)}'),
                _t('تبلیغات ${_m(m.ads)}'),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _t(String s) =>
      Text(s, style: const TextStyle(color: AppTheme.muted, fontSize: 12));
}

Future<void> _editMonth(BuildContext context, BizStore store, BizMonth m) async {
  final res = await showDialog<_DialogResult>(
    context: context,
    builder: (_) => _MonthDialog(m: m),
  );
  if (res == null || !context.mounted) return;
  if (res.delete) {
    await _guard(context, () => store.clearMonth(m.year, m.month));
  } else {
    await _guard(context, () => store.saveMonth(m.year, m.month, res.body));
  }
}

class _MonthDialog extends StatefulWidget {
  const _MonthDialog({required this.m});
  final BizMonth m;

  @override
  State<_MonthDialog> createState() => _MonthDialogState();
}

class _MonthDialogState extends State<_MonthDialog> {
  late final _staff = TextEditingController(text: _amountText(widget.m.staff));
  late final _ads = TextEditingController(text: _amountText(widget.m.ads));
  late final _income = TextEditingController(text: _amountText(widget.m.income));

  @override
  void dispose() {
    _staff.dispose();
    _ads.dispose();
    _income.dispose();
    super.dispose();
  }

  Widget _f(TextEditingController c, String label, Key key) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: key,
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('برج ${m.month} · ${pwoMonthNames[m.month - 1]} ${m.year}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _f(_income, 'درآمد (تومان)', const ValueKey('biz-m-income')),
            _f(_staff, 'کارمندان (تومان)', const ValueKey('biz-m-staff')),
            _f(_ads, 'دیوار - تبلیغات دفتر (تومان)', const ValueKey('biz-m-ads')),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute(builder: (_) => const PwoPage()));
                },
                child: Text('PWO این ماه: ${_m(m.pwo)}\nویرایش در بخش PWO',
                    textAlign: TextAlign.right),
              ),
            ),
          ]),
        ),
        actions: [
          if (m.hasOps)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _DialogResult(const {}, delete: true)),
              child: const Text('پاک کردن ماه',
                  style: TextStyle(color: AppTheme.negative)),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
            key: const ValueKey('biz-m-save'),
            onPressed: () => Navigator.pop(
                context,
                _DialogResult({
                  'staff': parseFlexibleNumber(_staff.text) ?? 0,
                  'ads': parseFlexibleNumber(_ads.text) ?? 0,
                  'income': parseFlexibleNumber(_income.text) ?? 0,
                })),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }
}

/// Entry tile used on the withdrawals page.
class BizEntryCard extends StatelessWidget {
  const BizEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = BizStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.snap;
        final sub = store.loaded && s.raw.isNotEmpty
            ? 'سود معاملات ${formatCompactToman(s.totalProfit)} · خالص ماهانه ${formatCompactToman(s.monthTotals['net'] ?? 0)}'
            : 'سابقه خرید و فروش ملک و جدول ماهانهٔ دفتر';
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            key: const ValueKey('biz-entry'),
            leading: const Icon(Icons.home_work_outlined, color: AppTheme.positive),
            title: const Text('ملک و دفتر',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BizPage())),
          ),
        );
      },
    );
  }
}
