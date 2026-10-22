import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:invest/data/biz_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/pwo_page.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/app_date_picker.dart';
import 'package:shamsi_date/shamsi_date.dart';

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

class _BizPageState extends State<BizPage> with SingleTickerProviderStateMixin {
  late final BizStore _store = widget.store ?? BizStore.instance;
  late final TabController _tabs =
      TabController(length: 2, vsync: this, initialIndex: widget.initialTab)
        ..addListener(() {
          if (mounted) setState(() {});
        });
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
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ملک و دفتر'),
          bottom: TabBar(controller: _tabs, tabs: const [
            Tab(text: 'معاملات ملک'),
            Tab(text: 'جدول ماهانه'),
          ]),
        ),
        // Scaffold places the FAB above system insets / keyboard; only the
        // trades tab has it, so it never covers the monthly table.
        floatingActionButton: ListenableBuilder(
          listenable: _store,
          builder: (context, _) => _tabs.index == 0 &&
                  _store.loaded &&
                  !_store.readOnly
              ? FloatingActionButton.extended(
                  key: const ValueKey('biz-add-trade'),
                  heroTag: 'biz-add-trade',
                  onPressed: () => _editTrade(context, _store, null),
                  icon: const Icon(Icons.add),
                  label: const Text('ثبت معامله'),
                )
              : const SizedBox.shrink(),
        ),
        body: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            final err = _store.lastError;
            final banner = _store.showingCache || err != null
                ? MaterialBanner(
                    content: Text(err ?? const BizReadOnlyException().toString()),
                    actions: [
                      TextButton(
                          onPressed: () => ensureBizReady(context, _store),
                          child: const Text('تلاش دوباره')),
                    ],
                  )
                : null;
            if (!_store.loaded) {
              // Never spin forever: a failed first load shows the error.
              if (banner != null && !_store.syncing) {
                return Column(children: [banner]);
              }
              return const Center(child: CircularProgressIndicator());
            }
            return Column(children: [
              if (banner != null) banner,
              if (_store.syncing) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: TabBarView(controller: _tabs, children: [
                  _TradesTab(store: _store),
                  _MonthsTab(store: _store),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// List padding that keeps the last row clear of the FAB and system bars.
EdgeInsets _listPad(BuildContext context, {bool fab = false}) =>
    EdgeInsets.fromLTRB(12, 12, 12,
        (fab ? 96 : 24) + MediaQuery.paddingOf(context).bottom);

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

/// Jalali sell month key 'YYYY/MM' of a trade, or null when unsold.
String? _sellMonth(PropertyTrade t) =>
    t.sellDate.length >= 7 ? t.sellDate.substring(0, 7) : null;

class _TradesTab extends StatefulWidget {
  const _TradesTab({required this.store});
  final BizStore store;

  @override
  State<_TradesTab> createState() => _TradesTabState();
}

class _TradesTabState extends State<_TradesTab>
    with AutomaticKeepAliveClientMixin {
  /// null = همه; 'open' = فروش نرفته; otherwise 'YYYY/MM'.
  String? _filter;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final store = widget.store;
    final all = store.snap.trades;
    final keys = <String>{for (final t in all) _sellMonth(t) ?? 'open'}.toList()
      ..sort((a, b) => a == 'open' ? -1 : b == 'open' ? 1 : b.compareTo(a));
    final filter = keys.contains(_filter) ? _filter : null;
    final trades = [
      for (final t in all)
        if (filter == null || (_sellMonth(t) ?? 'open') == filter) t
    ]..sort((a, b) => (b.sellDate.isEmpty ? '9' : b.sellDate)
        .compareTo(a.sellDate.isEmpty ? '9' : a.sellDate));
    final profit = trades.fold<double>(0, (v, t) => v + (t.profit ?? 0));
    final extra = trades.fold<double>(0, (v, t) => v + t.extraCost);
    String label(String k) {
      if (k == 'open') return 'فروش نرفته';
      final p = k.split('/');
      final m = int.tryParse(p.last) ?? 1;
      return '${pwoMonthNames[(m - 1).clamp(0, 11)]} ${p.first}';
    }

    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        padding: _listPad(context, fab: !store.readOnly),
        children: [
          if (keys.isNotEmpty) ...[
            SizedBox(
              height: 40,
              child: SingleChildScrollView(
                key: const ValueKey('biz-month-filter'),
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final k in <String?>[null, ...keys]) ...[
                    ChoiceChip(
                      key: ValueKey('biz-filter-${k ?? 'all'}'),
                      label: Text(k == null ? 'همه' : label(k)),
                      selected: k == filter,
                      onSelected: (_) => setState(() => _filter = k),
                    ),
                    const SizedBox(width: 6),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                _Stat(filter == null ? 'جمع سود / زیان' : 'سود / زیان ${label(filter)}',
                    _m(profit),
                    color: _sign(profit),
                    valueKey: const ValueKey('biz-total-profit')),
                const SizedBox(height: 6),
                _Stat('تعداد معاملات', '${trades.length}',
                    valueKey: const ValueKey('biz-trade-count')),
                if (extra > 0) ...[
                  const SizedBox(height: 6),
                  _Stat('جمع کد و نقشه', _m(extra)),
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
    );
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

/// Parses a Jalali date the way vinor biz_api does (Y/M/D or D/M/Y,
/// Persian digits ok, year 1300–1600). Null when invalid.
Jalali? parseBizDate(String raw) {
  const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final r in raw.trim().runes) {
    final ch = String.fromCharCode(r);
    final i = fa.indexOf(ch), k = ar.indexOf(ch);
    b.write(i >= 0 ? '$i' : k >= 0 ? '$k' : ch);
  }
  final m = RegExp(r'^(\d{1,4})[/\-.](\d{1,2})[/\-.](\d{1,4})$').firstMatch(b.toString());
  if (m == null) return null;
  final a = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), c = int.parse(m.group(3)!);
  final y = a > 31 ? a : c, d = a > 31 ? c : a;
  if (y < 1300 || y > 1600 || mo < 1 || mo > 12 || d < 1) return null;
  try {
    final j = Jalali(y, mo, d);
    if (d > j.monthLength) return null;
    return j;
  } catch (_) {
    return null;
  }
}

String bizDateText(Jalali j) =>
    '${j.year.toString().padLeft(4, '0')}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';

/// Live preview of a trade, same formulas as the server.
class BizTradePreview {
  BizTradePreview({this.days, this.profit, this.pct});
  final int? days;
  final double? profit;
  final double? pct;

  static BizTradePreview compute(Jalali? buyD, Jalali? sellD, double buy, double sell) {
    final sold = sellD != null && sell > 0;
    final profit = sold ? sell - buy : null;
    final days = (buyD != null && sellD != null)
        ? sellD.toDateTime().difference(buyD.toDateTime()).inDays
        : null;
    return BizTradePreview(
        days: days, profit: profit, pct: profit != null && sell > 0 ? profit / sell * 100 : null);
  }
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

  @override
  void initState() {
    super.initState();
    for (final c in [_buyDate, _sellDate, _buy, _sell]) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _pick(TextEditingController c, String label) async {
    final cur = parseBizDate(c.text) ?? parseBizDate(_buyDate.text);
    final iso = await pickAppDate(context,
        calendar: AppConfig.calendarJalali,
        initialIso: cur == null ? null : toIsoDate(cur.toDateTime()),
        firstDate: Jalali(1300, 1, 1).toDateTime(),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
        helpText: label);
    if (iso == null) return;
    c.text = bizDateText(Jalali.fromDateTime(parseIsoDate(iso)));
  }

  Widget _date(TextEditingController c, String label, String hint, String k) {
    final txt = c.text.trim();
    final j = txt.isEmpty ? null : parseBizDate(txt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        key: ValueKey(k),
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          helperText: j == null ? null : formatDisplayDate(toIsoDate(j.toDateTime()), AppConfig.calendarJalali),
          errorText: txt.isNotEmpty && j == null ? 'تاریخ نامعتبر است.' : null,
          suffixIcon: IconButton(
            key: ValueKey('$k-pick'),
            tooltip: 'انتخاب از تقویم',
            icon: const Icon(Icons.calendar_month_outlined, size: 20),
            onPressed: () => _pick(c, label),
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    final buyD = parseBizDate(_buyDate.text);
    final sellD = _sellDate.text.trim().isEmpty ? null : parseBizDate(_sellDate.text);
    final p = BizTradePreview.compute(buyD, sellD,
        parseFlexibleNumber(_buy.text) ?? 0, parseFlexibleNumber(_sell.text) ?? 0);
    final parts = <String>[
      if (p.days != null) 'مدت نگهداری ${p.days} روز',
      if (p.profit != null)
        '${p.profit! < 0 ? 'زیان' : 'سود'} ${_m(p.profit!.abs())}${p.pct == null ? '' : ' (${p.pct!.toStringAsFixed(1)}٪)'}',
      if (p.profit == null) 'هنوز فروش نرفته',
    ];
    final neg = (p.profit ?? 0) < 0 || (p.days ?? 0) < 0;
    return Container(
      key: const ValueKey('biz-f-preview'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border)),
      child: Text(
        (p.days ?? 0) < 0 ? 'تاریخ فروش پیش از تاریخ خرید است' : parts.join(' · '),
        textAlign: TextAlign.right,
        style: TextStyle(color: neg ? AppTheme.negative : AppTheme.positive, fontSize: 12),
      ),
    );
  }

  void _submit() {
    final buy = parseFlexibleNumber(_buy.text);
    if (_buyDate.text.trim().isEmpty || buy == null || buy <= 0) {
      setState(() => _err = 'تاریخ خرید و مبلغ خرید لازم است.');
      return;
    }
    final bd = parseBizDate(_buyDate.text);
    final sdText = _sellDate.text.trim();
    final sd = sdText.isEmpty ? null : parseBizDate(sdText);
    if (bd == null || (sdText.isNotEmpty && sd == null)) {
      setState(() => _err = 'تاریخ نامعتبر است.');
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
            _date(_buyDate, 'تاریخ خرید', '1405/01/20', 'biz-f-buy-date'),
            _f(_buy, 'مبلغ خرید (تومان)', num: true, key: const ValueKey('biz-f-buy')),
            _date(_sellDate, 'تاریخ فروش', 'خالی = هنوز فروش نرفته', 'biz-f-sell-date'),
            _f(_sell, 'مبلغ فروش (تومان)', num: true, key: const ValueKey('biz-f-sell')),
            _preview(),
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
    final year = store.year ?? s.year;
    // While another year is loading, the rows still belong to the old year:
    // hide them so an edit can never land on the wrong year.
    final stale = year != null && s.year != null && s.year != year;
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        padding: _listPad(context),
        children: [
          if (year != null)
            Row(children: [
              IconButton(
                key: const ValueKey('biz-year-prev'),
                tooltip: 'سال قبل',
                onPressed: year > 1300 ? () => store.selectYear(year - 1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              Expanded(
                child: Text('سال $year',
                    key: const ValueKey('biz-year'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              IconButton(
                key: const ValueKey('biz-year-next'),
                tooltip: 'سال بعد',
                onPressed: year < 1600 ? () => store.selectYear(year + 1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ]),
          const SizedBox(height: 4),
          if (stale)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                  child: store.syncing
                      ? const CircularProgressIndicator()
                      : const Text('دادهٔ این سال در دسترس نیست',
                          style: TextStyle(color: AppTheme.muted))),
            )
          else ...[
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
        ],
      ),
    );
  }
}

/// Profit of trades sold in Jalali [year]/[month] (by sell date).
double tradeProfitInMonth(Iterable<PropertyTrade> trades, int year, int month) {
  final key = '${year.toString().padLeft(4, '0')}/${month.toString().padLeft(2, '0')}';
  var sum = 0.0;
  for (final t in trades) {
    if (t.profit != null && _sellMonth(t) == key) sum += t.profit!;
  }
  return sum;
}

/// Income and sold-trade profit differ (more than 1,000 toman).
bool incomeMismatch(double income, double tradeProfit) =>
    (tradeProfit != 0 || income != 0) && (income - tradeProfit).abs() > 1000;

class _MonthTile extends StatelessWidget {
  const _MonthTile({required this.store, required this.m});
  final BizStore store;
  final BizMonth m;

  @override
  Widget build(BuildContext context) {
    final tp = tradeProfitInMonth(store.snap.trades, m.year, m.month);
    final flag = (!m.isEmpty || tp != 0) && incomeMismatch(m.income, tp);
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
            if (!m.isEmpty || tp != 0) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 12, runSpacing: 2, children: [
                _t('درآمد ${_m(m.income)}'),
                Text('سود معاملات ${_m(tp)}',
                    key: ValueKey('biz-month-tp-${m.month}'),
                    style: TextStyle(
                        color: flag ? AppTheme.negative : AppTheme.muted,
                        fontSize: 12,
                        fontWeight: flag ? FontWeight.w700 : null)),
                _t('کارمندان ${_m(m.staff)}'),
                _t('PWO ${_m(m.pwo)}'),
                _t('تبلیغات ${_m(m.ads)}'),
              ]),
              if (flag) ...[
                const SizedBox(height: 4),
                Row(key: ValueKey('biz-month-flag-${m.month}'), children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.negative),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                        'درآمد با سود معاملات فروخته‌شدهٔ این ماه ${_m((m.income - tp).abs())} فرق دارد',
                        style: const TextStyle(color: AppTheme.negative, fontSize: 11)),
                  ),
                ]),
              ],
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
    builder: (_) => _MonthDialog(
        m: m, tradeProfit: tradeProfitInMonth(store.snap.trades, m.year, m.month)),
  );
  if (res == null || !context.mounted) return;
  if (res.delete) {
    await _guard(context, () => store.clearMonth(m.year, m.month));
  } else {
    await _guard(context, () => store.saveMonth(m.year, m.month, res.body));
  }
}

class _MonthDialog extends StatefulWidget {
  const _MonthDialog({required this.m, this.tradeProfit = 0});
  final BizMonth m;
  final double tradeProfit;

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
            if (widget.tradeProfit > 0)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey('biz-m-fill'),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => Directionality(
                        textDirection: TextDirection.rtl,
                        child: AlertDialog(
                          title: const Text('پر کردن درآمد؟'),
                          content: Text(
                              'درآمد این ماه با سود معاملات فروخته‌شده (${_m(widget.tradeProfit)}) جایگزین شود؟ تا «ذخیره» را نزنید چیزی ثبت نمی‌شود.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
                            FilledButton(
                                key: const ValueKey('biz-m-fill-ok'),
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('جایگزین کن')),
                          ],
                        ),
                      ),
                    );
                    if (ok == true && mounted) {
                      setState(() => _income.text = formatNumber(widget.tradeProfit));
                    }
                  },
                  child: Text('پر کردن با سود معاملات این ماه: ${_m(widget.tradeProfit)}',
                      textAlign: TextAlign.right),
                ),
              ),
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

/// Summary of ملک و دفتر on the dashboard (current year). Tap opens the page.
class BizDashboardCard extends StatefulWidget {
  const BizDashboardCard({super.key, this.store, this.pwoStore});
  final BizStore? store;
  final PwoStore? pwoStore;

  @override
  State<BizDashboardCard> createState() => _BizDashboardCardState();
}

class _BizDashboardCardState extends State<BizDashboardCard> {
  BizStore get _store => widget.store ?? BizStore.instance;
  PwoStore get _pwo => widget.pwoStore ?? PwoStore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ensureBizReady(context, _store, refresh: false).catchError((_) {});
      if (!_pwo.loaded) ensurePwoReady(context, _pwo, refresh: false).catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return ListenableBuilder(
      listenable: Listenable.merge([store, _pwo]),
      builder: (context, _) {
        final s = store.snap;
        final has = store.loaded && s.raw.isNotEmpty;
        final pwoT = _pwo.loaded ? _pwo.ledger.target : null;
        final pwoMonths = [for (final m in s.months) if (m.pwo > 0) m];
        final trades = s.trades;
        final open = trades.where((t) => !t.sold).length;
        final soldN = trades.where((t) => t.sold).length;
        final y = s.year;
        var mism = 0;
        if (y != null) {
          for (final m in s.months) {
            final tp = tradeProfitInMonth(trades, y, m.month);
            if ((!m.isEmpty || tp != 0) && incomeMismatch(m.income, tp)) mism++;
          }
        }
        Widget stat(String k, String label, String value, {Color? color}) =>
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Flexible(
                  child: Text(value,
                      key: ValueKey('biz-dash-$k'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: color ?? AppTheme.title,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                ),
              ]),
            );
        final net = s.monthTotals['net'] ?? 0;
        return Material(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: const ValueKey('biz-dash-card'),
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BizPage(store: widget.store))),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.chevron_left_rounded, color: AppTheme.muted),
                    const Spacer(),
                    Flexible(
                      child: Text(y == null ? 'ملک و دفتر' : 'ملک و دفتر · $y',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.title,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.home_work_outlined,
                        color: AppTheme.positive, size: 20),
                  ]),
                  if (!has)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                          store.syncing
                              ? 'در حال دریافت…'
                              : 'سابقه خرید و فروش ملک و جدول ماهانهٔ دفتر',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 12)),
                    )
                  else ...[
                    stat('profit', 'سود معاملات فروخته‌شده ($soldN)',
                        _m(s.totalProfit),
                        color: s.totalProfit < 0
                            ? AppTheme.negative
                            : AppTheme.positive),
                    stat('open', 'معاملات باز', '$open'),
                    stat('income', 'درآمد دفتر امسال',
                        _m(s.monthTotals['income'] ?? 0)),
                    stat('net', 'خالص ماهانه امسال', _m(net),
                        color: net < 0 ? AppTheme.negative : null),
                    if (pwoT != null && pwoT > 0 && pwoMonths.isNotEmpty) ...[
                      stat(
                          'pwo',
                          'PWO ماه ${pwoMonths.last.month} از هدف ${_m(pwoT)}',
                          _m(pwoMonths.last.pwo),
                          color: pwoMonths.last.pwo >= pwoT
                              ? AppTheme.positive
                              : AppTheme.negative),
                      stat(
                          'pwo-hit',
                          'ماه‌های رسیده به هدف PWO',
                          '${pwoMonths.where((m) => m.pwo >= pwoT).length} از ${pwoMonths.length}'),
                    ],
                    if (mism > 0)
                      stat('mismatch', 'ماه با مغایرت درآمد', '$mism',
                          color: AppTheme.negative),
                    if (store.showingCache)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('نسخهٔ ذخیره‌شده (آفلاین)',
                            textAlign: TextAlign.right,
                            style:
                                TextStyle(color: AppTheme.muted, fontSize: 11)),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
