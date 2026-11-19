import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:invest/ui/widgets/pending_sync_mark.dart';
import 'package:invest/ui/widgets/pending_writes_panel.dart';
import 'package:invest/domain/utils/biz_dates.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/domain/services/dashboard_snapshot.dart';
import 'package:invest/domain/services/full_export.dart';
import 'package:invest/ui/layout/home_tabs.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/ui/pages/projects_page.dart' show ensureProjectsReady, importProjectsText;
import 'package:invest/data/write_queue.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:invest/domain/services/biz_annual_report.dart';
import 'package:invest/domain/services/performance_aggregator.dart';
import 'package:invest/ui/widgets/performance_sections.dart';
import 'package:invest/ui/widgets/header_status.dart';
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

export 'package:invest/domain/utils/biz_dates.dart' show parseBizDate, bizDateText;

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
  if (store.isRemote && (app == null || (remote == null && phone.isEmpty))) {
    return store.refresh();
  }
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
  } on WriteQueuedException catch (e) {
    // Saved in this account's queue: the edit is done from the user's side.
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
    return false;
  }
}

/// Loading / error / ready switch shared by the trades page and the
/// monthly table in «عملکرد».
Widget _bizBody(BuildContext context, BizStore store, Widget Function() ready) {
  if (!store.loaded) {
    // Never spin forever: details/retry are in the header status.
    if (store.lastError != null && !store.syncing) {
      return Center(
        child: TextButton(
            onPressed: () => ensureBizReady(context, store),
            child: const Text('بارگیری نشد · تلاش دوباره')),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
  return ready();
}

/// Keeps the PWO column of the monthly table in step with PWO edits and
/// re-binds when account / remote connectivity transitions.
mixin _BizPwoSync<T extends StatefulWidget> on State<T> {
  BizStore get bizStore;
  Object? _pwoLedger;
  String? _lastAuthSig;

  @override
  void initState() {
    super.initState();
    _pwoLedger = PwoStore.instance.ledger;
    PwoStore.instance.addListener(_onPwo);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureBizReady(context, bizStore);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppState? app;
    try {
      app = Provider.of<AppState>(context);
    } on ProviderNotFoundException {
      app = null;
    }
    if (app != null) {
      final sig = '${app.useRemote}:${(app.userPhone ?? '').trim()}';
      if (_lastAuthSig != null && _lastAuthSig != sig) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ensureBizReady(context, bizStore);
        });
      }
      _lastAuthSig = sig;
    }
  }

  /// PWO column is read from the PWO module on the server: refresh after a
  /// PWO edit so both views agree.
  void _onPwo() {
    final l = PwoStore.instance.ledger;
    if (!identical(l, _pwoLedger) && !PwoStore.instance.syncing) {
      _pwoLedger = l;
      if (bizStore.isRemote) bizStore.refresh();
    }
  }

  @override
  void dispose() {
    PwoStore.instance.removeListener(_onPwo);
    super.dispose();
  }
}

/// «ملک و دفتر» — property buy/sell history. The office monthly table
/// lives in the «عملکرد» tab ([BizMonthsPane]).
class BizPage extends StatefulWidget {
  const BizPage({super.key, this.store});
  final BizStore? store;

  @override
  State<BizPage> createState() => _BizPageState();
}

class _BizPageState extends State<BizPage> with _BizPwoSync<BizPage> {
  late final BizStore _store = widget.store ?? BizStore.instance;
  @override
  BizStore get bizStore => _store;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: HeaderStatusTitle(
              title: 'ملک و دفتر', source: StoreStatusSource.biz(_store)),
          actions: [
            IconButton(
              key: const ValueKey('biz-open-months'),
              tooltip: 'جدول ماهانه (عملکرد)',
              icon: const Icon(Icons.table_chart_outlined),
              onPressed: () => openHomeTab(context, HomeTabs.performance, popToRoot: true),
            ),
            ListenableBuilder(
              listenable: _store,
              builder: (context, _) => IconButton(
                key: const ValueKey('biz-export'),
                tooltip: 'خروجی سالانه (Excel / PDF)',
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: _store.loaded && _store.snap.raw.isNotEmpty
                    ? () => _exportAnnual(context, _store)
                    : null,
              ),
            ),
          ],
        ),
        // Scaffold places the FAB above system insets / keyboard.
        floatingActionButton: ListenableBuilder(
          listenable: _store,
          builder: (context, _) => _store.loaded && !_store.readOnly
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
          builder: (context, _) =>
              _bizBody(context, _store, () => _TradesTab(store: _store)),
        ),
      ),
    );
  }
}

/// «جدول ماهانه» of the office (income, staff, PWO, ads, net) — the body of
/// the «عملکرد» tab. No Scaffold: the home shell provides the header.
class BizMonthsPane extends StatefulWidget {
  const BizMonthsPane({super.key, this.store});
  final BizStore? store;

  @override
  State<BizMonthsPane> createState() => _BizMonthsPaneState();
}

class _BizMonthsPaneState extends State<BizMonthsPane> with _BizPwoSync<BizMonthsPane> {
  late final BizStore _store = widget.store ?? BizStore.instance;
  final ProjectsStore _projects = ProjectsStore.instance;
  @override
  BizStore get bizStore => _store;

  @override
  Widget build(BuildContext context) {
    AppState? app;
    try {
      app = Provider.of<AppState>(context);
    } on ProviderNotFoundException {
      app = null;
    }
    if (app != null) {
      CurrencyMode.update(
        currency: app.settings.currency,
        liveUsdt: app.liveUsdt ?? app.settings.usdtTmnRate,
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([_store, _projects]),
      builder: (context, _) {
        final hasExternal = (app != null &&
                (app.openTrades.isNotEmpty ||
                    app.closedTrades.isNotEmpty ||
                    app.assets.isNotEmpty)) ||
            (_projects.loaded && _projects.snap.hasData);

        Widget content() => Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
                child: Row(children: [
                  const Icon(Icons.table_chart_outlined, size: 18, color: AppTheme.positive),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('عملکرد یکپارچه و دفتر',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppTheme.title, fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  TextButton.icon(
                    key: const ValueKey('perf-open-biz'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.positive,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => BizPage(store: widget.store))),
                    icon: const Icon(Icons.home_work_outlined, size: 17),
                    label: const Text('ملک و دفتر', style: TextStyle(fontSize: 12.5)),
                  ),
                  IconButton(
                    key: const ValueKey('perf-export'),
                    tooltip: 'خروجی سالانه (Excel / PDF)',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.ios_share_rounded, size: 20),
                    onPressed: (_store.snap.raw.isNotEmpty || hasExternal)
                        ? () => _exportAnnual(context, _store)
                        : null,
                  ),
                ]),
              ),
              Expanded(
                child: _MonthsTab(
                  store: _store,
                  app: app,
                  projectsStore: _projects,
                ),
              ),
            ]);

        if (_store.loaded || hasExternal) {
          return content();
        }
        return _bizBody(context, _store, content);
      },
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

/// Filter key of a trade: Jalali sell month 'YYYY/MM', 'open' when unsold,
/// 'invalid' when sold with a date that cannot be read (never a guessed
/// month from the first 7 characters).
String _tradeKey(PropertyTrade t) =>
    t.sellMonth ?? (t.sold ? 'invalid' : 'open');

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
    int rank(String k) => k == 'open' ? 0 : k == 'invalid' ? 1 : 2;
    final keys = <String>{for (final t in all) _tradeKey(t)}.toList()
      ..sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : b.compareTo(a));
    final filter = keys.contains(_filter) ? _filter : null;
    final trades = [
      for (final t in all)
        if (filter == null || _tradeKey(t) == filter) t
    ]..sort((a, b) => (b.sellDate.isEmpty ? '9' : b.sellDate)
        .compareTo(a.sellDate.isEmpty ? '9' : a.sellDate));
    final profit = trades.fold<double>(0, (v, t) => v + (t.profit ?? 0));
    final extra = trades.fold<double>(0, (v, t) => v + t.extraCost);
    String label(String k) {
      if (k == 'open') return 'فروش نرفته';
      if (k == 'invalid') return 'تاریخ فروش نامعتبر';
      final p = k.split('/');
      final m = int.tryParse(p.last) ?? 1;
      return '${pwoMonthNames[(m - 1).clamp(0, 11)]} ${p.first}';
    }

    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        padding: _listPad(context, fab: !store.readOnly),
        children: [
          PendingWritesPanel(queue: store.queue, onSendNow: store.refresh),
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
  Widget build(BuildContext context) =>
      PendingSyncMark(pending: t.raw['pending_sync'] == true, child: _inner(context));

  Widget _inner(BuildContext context) {
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
                  _kv('٪ سود/زیان از مبلغ فروش', '${t.profitPct!.round()}٪'),
                if (t.extraCost > 0) _kv('کد و نقشه', _m(t.extraCost)),
                if (t.extraCost > 0 && t.grossProfit != null)
                  _kv('سود پیش از کد و نقشه', _m(t.grossProfit!)),
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
  var text = await showDialog<String>(
    context: context,
    builder: (c) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('ورود از شیت'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'متن JSON شیت را اینجا بچسبانید. معاملات و جدول ماهانه فقط یک بار و فقط روی حساب خالی اعمال می‌شوند؛ ردیف‌های «projects» (پیمانکاری) به پروژه‌ها اضافه می‌شوند. دادهٔ موجود هرگز بازنویسی نمی‌شود.',
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
  // The same paste box takes the «پیمانکاری» tab: {"projects": [...]}.
  Map? parsed;
  try {
    final d = jsonDecode(text.trim());
    if (d is Map) parsed = d;
  } catch (_) {}
  if (parsed != null && parsed['projects'] is List) {
    final projects = ProjectsStore.instance;
    await ensureProjectsReady(context, projects, refresh: false);
    if (!context.mounted) return;
    await importProjectsText(context, projects, jsonEncode({'projects': parsed['projects']}));
    if (parsed['trades'] is! List && parsed['months'] is! List) return;
    if (!context.mounted) return;
    text = jsonEncode({
      if (parsed['trades'] is List) 'trades': parsed['trades'],
      if (parsed['months'] is List) 'months': parsed['months'],
    });
  }
  if (!context.mounted) return;
  int n = 0;
  final body = text;
  final ok = await _guard(context, () async => n = await store.importSheet(body));
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
  Map<String, dynamic>? draft;
  String? error;
  for (;;) {
    if (!context.mounted) return;
    final res = await showDialog<_DialogResult>(
      context: context,
      builder: (_) => _TradeDialog(t: t, draft: draft, error: error),
    );
    if (res == null || !context.mounted) return;
    if (res.delete && t != null) {
      await _guard(context, () => store.deleteTrade(t.id));
      return;
    }
    try {
      if (t == null) {
        await store.addTrade(res.body);
      } else {
        await store.updateTrade(t.id, res.body);
      }
      return;
    } on WriteQueuedException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return;
    } catch (e) {
      // Refused by the server: reopen the form with what was typed and the
      // reason, instead of a snackbar that disappears.
      if (!context.mounted) return;
      draft = res.body;
      error = 'سرور معامله را ثبت نکرد: $e';
    }
  }
}

class _DialogResult {
  _DialogResult(this.body, {this.delete = false});
  final Map<String, dynamic> body;
  final bool delete;
}

/// Same checks as vinor `_trade_fields`, so a deal is refused here with a
/// clear reason instead of failing on the server (or later in the queue).
/// Null when [b] is valid.
String? validateBizTrade(Map<String, dynamic> b) {
  final buyText = '${b['buy_date'] ?? ''}'.trim();
  final sellText = '${b['sell_date'] ?? ''}'.trim();
  final buy = b['buy_amount'] is num ? (b['buy_amount'] as num).toDouble() : null;
  final sell = b['sell_amount'] is num ? (b['sell_amount'] as num).toDouble() : 0.0;
  if (buyText.isEmpty || buy == null || buy <= 0) return 'تاریخ خرید و مبلغ خرید لازم است.';
  final bd = parseBizDate(buyText);
  if (bd == null) return 'تاریخ خرید نامعتبر است.';
  final sd = sellText.isEmpty ? null : parseBizDate(sellText);
  if (sellText.isNotEmpty && sd == null) return 'تاریخ فروش نامعتبر است.';
  if (sell > 0 && sd == null) return 'برای مبلغ فروش، تاریخ فروش لازم است.';
  if (sd != null && sell <= 0) return 'برای تاریخ فروش، مبلغ فروش لازم است.';
  if (sd != null && sd.compareTo(bd) < 0) {
    return 'تاریخ فروش نمی‌تواند قبل از تاریخ خرید باشد.';
  }
  final extra = b['extra_cost'];
  if (extra is num && extra < 0) return 'کد و نقشه نمی‌تواند منفی باشد.';
  if (sell < 0) return 'مبلغ فروش نمی‌تواند منفی باشد.';
  return null;
}

/// Live preview of a trade, same formulas as the server.
class BizTradePreview {
  BizTradePreview({this.days, this.profit, this.pct});
  final int? days;
  final double? profit;
  final double? pct;

  /// Net profit = sell − buy − extra cost (کد و نقشه); % of the sell amount.
  static BizTradePreview compute(Jalali? buyD, Jalali? sellD, double buy, double sell,
      [double extra = 0]) {
    final sold = sellD != null && sell > 0;
    final profit = sold ? sell - buy - extra : null;
    final days = (buyD != null && sellD != null)
        ? sellD.toDateTime().difference(buyD.toDateTime()).inDays
        : null;
    return BizTradePreview(
        days: days, profit: profit, pct: profit != null && sell > 0 ? profit / sell * 100 : null);
  }
}

class _TradeDialog extends StatefulWidget {
  const _TradeDialog({this.t, this.draft, this.error});
  final PropertyTrade? t;

  /// Values typed before the server refused them (reopened form).
  final Map<String, dynamic>? draft;
  final String? error;

  @override
  State<_TradeDialog> createState() => _TradeDialogState();
}

class _TradeDialogState extends State<_TradeDialog> {
  late final PropertyTrade? _src = widget.draft == null
      ? widget.t
      : PropertyTrade({'id': widget.t?.id ?? 0, ...widget.draft!});
  late final _buyDate = TextEditingController(text: _src?.buyDate ?? '');
  late final _sellDate = TextEditingController(text: _src?.sellDate ?? '');
  late final _buy = TextEditingController(text: _amountText(_src?.buyAmount ?? 0));
  late final _sell = TextEditingController(text: _amountText(_src?.sellAmount ?? 0));
  late final _area = TextEditingController(
      text: _src?.area == null ? '' : formatNumber(_src!.area!, decimals: _src.area! % 1 == 0 ? 0 : 2));
  late final _title = TextEditingController(text: _src?.title ?? '');
  late final _extra = TextEditingController(text: _amountText(_src?.extraCost ?? 0));
  late final _note = TextEditingController(text: _src?.note ?? '');
  late String? _err = widget.error;

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
    for (final c in [_buyDate, _sellDate, _buy, _sell, _extra]) {
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
    final p = BizTradePreview.compute(buyD, sellD, parseFlexibleNumber(_buy.text) ?? 0,
        parseFlexibleNumber(_sell.text) ?? 0, parseFlexibleNumber(_extra.text) ?? 0);
    final parts = <String>[
      if (p.days != null) 'مدت نگهداری ${p.days} روز',
      if (p.profit != null)
        '${p.profit! < 0 ? 'زیان' : 'سود'} خالص ${_m(p.profit!.abs())}${p.pct == null ? '' : ' (${p.pct!.toStringAsFixed(1)}٪ از مبلغ فروش)'}',
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
    final body = <String, dynamic>{
      'buy_date': _buyDate.text,
      'sell_date': _sellDate.text,
      'buy_amount': parseFlexibleNumber(_buy.text),
      'sell_amount': parseFlexibleNumber(_sell.text) ?? 0,
      'area': parseFlexibleNumber(_area.text),
      'title': _title.text.trim(),
      'extra_cost': parseFlexibleNumber(_extra.text) ?? 0,
      'note': _note.text.trim(),
    };
    final err = validateBizTrade(body);
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    Navigator.of(context).pop(_DialogResult(BizStore.normalizeTradeBody(body)));
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

class _MonthsTab extends StatefulWidget {
  const _MonthsTab({
    required this.store,
    this.app,
    this.projectsStore,
  });
  final BizStore store;
  final AppState? app;
  final ProjectsStore? projectsStore;

  @override
  State<_MonthsTab> createState() => _MonthsTabState();
}

class _MonthsTabState extends State<_MonthsTab> {
  String _filter = 'all'; // 'all', 'active', 'dup'
  final Set<PerfDomain> _selectedDomains = {};
  late int _localYear = currentJalaliYear();

  Future<void> _selectYear(BizStore store, int nextYear) async {
    setState(() => _localYear = nextYear);
    if (store.loaded || store.isRemote) {
      await store.selectYear(nextYear);
    }
  }

  void _toggleDomain(PerfDomain d, List<PerfDomain> activeDomains) {
    setState(() {
      if (_selectedDomains.contains(d)) {
        _selectedDomains.remove(d);
      } else {
        _selectedDomains.add(d);
        if (activeDomains.isNotEmpty &&
            activeDomains.every(_selectedDomains.contains)) {
          _selectedDomains.clear();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final s = store.snap;
    final app = widget.app;
    final ps = widget.projectsStore ?? ProjectsStore.instance;
    final year = store.year ?? s.year ?? _localYear;
    // While another year is loading, the rows still belong to the old year:
    // hide them so an edit can never land on the wrong year.
    final stale =
        store.loaded && store.year != null && s.year != null && s.year != year;

    final useBizForYear = store.loaded && (s.year == null || s.year == year);
    final summary = PerformanceAggregator.build(
      year: year,
      biz: useBizForYear ? s : BizSnapshot.empty,
      assets: app?.assets ?? const [],
      openTrades: app?.openTrades ?? const [],
      closedTrades: app?.closedTrades ?? const [],
      projects: ps.loaded ? ps.snap.items : const [],
      useBizMonthsForYear: useBizForYear && s.months.isNotEmpty,
    );

    final effectiveFilter =
        _selectedDomains.where(summary.activeDomains.contains).toSet();
    final months = summary.months;
    final dup = summary.mismatchCountFor(effectiveFilter);
    final filter = (_filter == 'dup' && dup == 0) ? 'all' : _filter;
    final activeMonths = summary.activeMonthsFor(effectiveFilter);
    final visible = [
      for (final m in months)
        if (filter == 'all' ||
            (filter == 'active' && !m.isEmptyFor(effectiveFilter)) ||
            (filter == 'dup' && m.incomeDupTrades))
          m,
    ];

    final netTotal = summary.totalNetFor(effectiveFilter);
    final incomeTotal = summary.totalIncomeEffectiveFor(effectiveFilter);
    final yearSoldProfit = summary.totalTradeProfitFor(effectiveFilter);
    final staffTotal = summary.totalStaffFor(effectiveFilter);
    final pwoTotal = summary.totalPwoFor(effectiveFilter);
    final adsTotal = summary.totalAdsFor(effectiveFilter);
    final avgNet = summary.avgNetFor(effectiveFilter);
    final marginPct = summary.marginPctFor(effectiveFilter);
    final boughtN = summary.totalBoughtCountFor(effectiveFilter);
    final boughtAmt = summary.totalBoughtAmountFor(effectiveFilter);
    final soldN = summary.totalSoldCountFor(effectiveFilter);
    final showOfficeMetrics =
        summary.hasOfficeData && summary.includesOffice(effectiveFilter);
    final showMultiDomains = summary.activeDomains.length > 1;
    final showBreakdownCard = summary.activeDomains.length >= 2 ||
        (summary.activeDomains.isNotEmpty &&
            !summary.activeDomains.contains(PerfDomain.office));
    final emptyState =
        !summary.hasAnyYearData && !summary.hasAnyOpen && s.months.isEmpty;

    final onlineErr =
        store.lastError != null && store.lastError != offlineQueueNote;

    return RefreshIndicator(
      onRefresh: () async {
        final futures = <Future<void>>[];
        if (store.isRemote || !store.loaded) {
          futures.add(store.refresh());
        }
        if (app != null) {
          futures.add(app.refreshAll());
        }
        if (ps.isRemote) {
          futures.add(ps.refresh());
        }
        await Future.wait(futures);
      },
      child: ListView(
        padding: _listPad(context),
        children: [
          PendingWritesPanel(queue: store.queue, onSendNow: store.refresh),
          Row(children: [
            IconButton(
              key: const ValueKey('biz-year-prev'),
              tooltip: 'سال قبل',
              visualDensity: VisualDensity.compact,
              onPressed: year > 1300 ? () => _selectYear(store, year - 1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            Expanded(
              child: Text('سال $year',
                  key: const ValueKey('biz-year'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
            IconButton(
              key: const ValueKey('biz-year-next'),
              tooltip: 'سال بعد',
              visualDensity: VisualDensity.compact,
              onPressed: year < 1600 ? () => _selectYear(store, year + 1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ]),
          if (onlineErr || store.showingCache) ...[
            const SizedBox(height: 4),
            Container(
              key: const ValueKey('perf-status-banner'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (onlineErr ? AppTheme.negative : AppTheme.muted)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (onlineErr ? AppTheme.negative : AppTheme.border)
                      .withValues(alpha: 0.5),
                ),
              ),
              child: Row(children: [
                Icon(
                  onlineErr
                      ? Icons.cloud_off_rounded
                      : Icons.offline_bolt_outlined,
                  size: 15,
                  color: onlineErr ? AppTheme.negative : AppTheme.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    onlineErr
                        ? 'خطا در همگام‌سازی · نمایش دادهٔ ذخیره‌شده'
                        : 'نسخهٔ ذخیره‌شده (آفلاین)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onlineErr ? AppTheme.negative : AppTheme.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onlineErr && store.isRemote && !store.syncing)
                  InkWell(
                    onTap: store.refresh,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text('تلاش دوباره',
                          style: TextStyle(
                              color: AppTheme.positive,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ),
          ],
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
          else if (emptyState)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              child: Column(children: [
                const Icon(Icons.table_rows_outlined,
                    size: 40, color: AppTheme.muted),
                const SizedBox(height: 10),
                const Text('داده‌ای برای عملکرد این سال ثبت نشده است',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppTheme.title, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text(
                  'تمام معاملات دارایی‌ها، ملک و دفتر و پروژه‌های پیمانکاری به محض ثبت یا همگام‌سازی اینجا جمع‌بندی می‌شوند.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
                if (store.isRemote && !store.syncing) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: store.refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('بارگیری مجدد'),
                  ),
                ],
              ]),
            )
          else ...[
            if (showMultiDomains) ...[
              PerfDomainFilterBar(
                activeDomains: summary.activeDomains,
                selected: effectiveFilter,
                onClear: () => setState(() => _selectedDomains.clear()),
                onToggle: (d) => _toggleDomain(d, summary.activeDomains),
              ),
              const SizedBox(height: 6),
            ],
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Stat(
                        effectiveFilter.isEmpty
                            ? 'جمع کل خالص $year'
                            : 'خالص ${effectiveFilter.map((d) => d.shortLabel).join('، ')} · $year',
                        _m(netTotal),
                        color: _sign(netTotal),
                        valueKey: const ValueKey('biz-total-net'),
                      ),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                            child: _CompactMetric(
                                'سود معاملات ($soldN)', _m(yearSoldProfit),
                                valueKey:
                                    const ValueKey('biz-total-trade-profit'))),
                        const SizedBox(width: 6),
                        Expanded(
                            child: _CompactMetric(
                                'خرید / سرمایه‌گذاری ($boughtN)', _m(boughtAmt),
                                valueKey: const ValueKey('biz-total-bought'))),
                      ]),
                      if (showOfficeMetrics) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(
                              child: _CompactMetric(
                                  'درآمد دفتر', _m(incomeTotal))),
                          const SizedBox(width: 6),
                          Expanded(
                              child:
                                  _CompactMetric('کارمندان', _m(staffTotal))),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(child: _CompactMetric('PWO', _m(pwoTotal))),
                          const SizedBox(width: 6),
                          Expanded(
                              child: _CompactMetric(
                                  'دیوار - تبلیغات دفتر', _m(adsTotal))),
                        ]),
                      ],
                      if (activeMonths.isNotEmpty || dup > 0) ...[
                        const SizedBox(height: 6),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          if (activeMonths.isNotEmpty)
                            _KpiChip('میانگین خالص ماهانه', _m(avgNet),
                                color: _sign(avgNet)),
                          if (marginPct != null)
                            _KpiChip(
                              'حاشیه خالص',
                              '${formatNumber(marginPct, decimals: 1)}٪',
                              color: _sign(marginPct),
                            ),
                          if (dup > 0)
                            InkWell(
                              key: const ValueKey('biz-mismatch-pill'),
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(() {
                                _filter = _filter == 'dup' ? 'all' : 'dup';
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.negative.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppTheme.negative
                                          .withValues(alpha: 0.45)),
                                ),
                                child: Text(
                                  '$dup ماه درآمد تکراری',
                                  style: const TextStyle(
                                      color: AppTheme.negative,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                        ]),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        effectiveFilter.isEmpty
                            ? 'خالص کل = عملکرد دفتر + سود قطعی تمام معاملات بسته‌شده (ملک، طلا، ارز، رمزارز، بورس، خودرو، پیمانکاری و سایر) در ماه تحقق'
                            : 'مقادیر بر اساس زمینه‌های انتخاب‌شده محاسبه شده‌اند؛ سود هر معامله در ماه فروش/پایان لحاظ می‌شود.',
                        key: const ValueKey('biz-net-formula'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 10),
                      ),
                    ]),
              ),
            ),
            if (showBreakdownCard) ...[
              const SizedBox(height: 6),
              PerfDomainBreakdownCard(
                summary: summary,
                selected: effectiveFilter,
                onToggleDomain: (d) => _toggleDomain(d, summary.activeDomains),
              ),
            ],
            if (summary.hasAnyOpen) ...[
              const SizedBox(height: 6),
              PerfOpenExposureCard(summary: summary),
            ],
            if (activeMonths.isNotEmpty) ...[
              const SizedBox(height: 6),
              _BizMonthsChart(
                months: months,
                filter: effectiveFilter,
                avgNet: avgNet,
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _FilterChipBtn(
                  key: const ValueKey('biz-months-filter-all'),
                  label: 'همه (${months.length})',
                  selected: filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                _FilterChipBtn(
                  key: const ValueKey('biz-months-filter-active'),
                  label: 'فعال (${activeMonths.length})',
                  selected: filter == 'active',
                  onTap: () => setState(() => _filter = 'active'),
                ),
                if (dup > 0)
                  _FilterChipBtn(
                    key: const ValueKey('biz-months-filter-mismatch'),
                    label: 'درآمد تکراری ($dup)',
                    selected: filter == 'dup',
                    tone: AppTheme.negative,
                    onTap: () => setState(() => _filter = 'dup'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(children: [
                  const Text('ماهی با این فیلتر وجود ندارد',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => setState(() => _filter = 'all'),
                    child: const Text('نمایش همه ماه‌ها'),
                  ),
                ]),
              )
            else
              for (final m in visible) ...[
                _MonthTile(
                  store: store,
                  m: m,
                  filter: effectiveFilter,
                ),
                const SizedBox(height: 6),
              ],
          ],
        ],
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric(this.label, this.value, {this.valueKey});
  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.bg.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                key: valueKey,
                style: const TextStyle(
                    color: AppTheme.title, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 11),
        children: [
          TextSpan(text: '$label: ', style: const TextStyle(color: AppTheme.muted)),
          TextSpan(
            text: value,
            style: TextStyle(
                color: color ?? AppTheme.title, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _FilterChipBtn extends StatelessWidget {
  const _FilterChipBtn({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = tone ?? AppTheme.positive;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.16) : AppTheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? c : AppTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c : AppTheme.muted,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _BizMonthsChart extends StatelessWidget {
  const _BizMonthsChart({
    required this.months,
    required this.filter,
    required this.avgNet,
  });
  final List<PerfMonthSummary> months;
  final Set<PerfDomain> filter;
  final double avgNet;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(
              child: Text('نمودار خالص ماهانه',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppTheme.title,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5)),
            ),
            const SizedBox(width: 8),
            Text('میانگین ${formatCompactToman(avgNet)}',
                style: TextStyle(
                    color: _sign(avgNet),
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          SizedBox(
            height: 62,
            child: CustomPaint(
              key: const ValueKey('biz-months-chart'),
              painter: _BizMonthsChartPainter(
                months: months,
                filter: filter,
                avgNet: avgNet,
                textColor: AppTheme.muted,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _BizMonthsChartPainter extends CustomPainter {
  _BizMonthsChartPainter({
    required this.months,
    required this.filter,
    required this.avgNet,
    required this.textColor,
  });
  final List<PerfMonthSummary> months;
  final Set<PerfDomain> filter;
  final double avgNet;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;
    const bottom = 18.0, top = 6.0;
    final h = size.height - bottom - top;
    if (h <= 0) return;

    var maxPos = 0.0;
    var maxNeg = 0.0;
    for (final m in months) {
      if (m.isEmptyFor(filter)) continue;
      final n = m.netFor(filter);
      if (n > maxPos) maxPos = n;
      if (n < 0 && n.abs() > maxNeg) maxNeg = n.abs();
    }
    if (avgNet > maxPos) maxPos = avgNet;
    if (avgNet < 0 && avgNet.abs() > maxNeg) maxNeg = avgNet.abs();
    final span = math.max(1.0, (maxPos + maxNeg) * 1.12);
    final zeroY = top + h * (maxPos * 1.06 / span);

    // Zero baseline
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = AppTheme.border
        ..strokeWidth = 1,
    );

    final n = months.length;
    final slot = size.width / n;
    final barW = math.min(20.0, slot * 0.58);
    for (var i = 0; i < n; i++) {
      final m = months[i];
      // RTL: month 1 on the right.
      final cx = size.width - slot * (i + 0.5);
      if (!m.isEmptyFor(filter)) {
        final net = m.netFor(filter);
        final bh = math.max(2.0, h * (net.abs() / span));
        final isPos = net >= 0;
        final rect = isPos
            ? RRect.fromRectAndCorners(
                Rect.fromLTWH(cx - barW / 2, zeroY - bh, barW, bh),
                topLeft: const Radius.circular(4),
                topRight: const Radius.circular(4),
              )
            : RRect.fromRectAndCorners(
                Rect.fromLTWH(cx - barW / 2, zeroY, barW, bh),
                bottomLeft: const Radius.circular(4),
                bottomRight: const Radius.circular(4),
              );
        canvas.drawRRect(
          rect,
          Paint()
            ..color = (isPos ? AppTheme.positive : AppTheme.negative)
                .withValues(alpha: 0.85),
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - barW / 2, zeroY - 1.5, barW, 3),
            const Radius.circular(1.5),
          ),
          Paint()..color = AppTheme.border.withValues(alpha: 0.5),
        );
      }
      final tp = TextPainter(
        text: TextSpan(
            text: pwoChartLabel(m.month, slot),
            style: TextStyle(color: textColor, fontSize: 9.5)),
        textDirection: TextDirection.rtl,
      )..layout(maxWidth: slot);
      tp.paint(canvas, Offset(cx - tp.width / 2, size.height - bottom + 3));
    }

    // Average net dashed line
    final ay = (zeroY - h * (avgNet / span)).clamp(top, top + h);
    final avgPaint = Paint()
      ..color = Colors.amber.withValues(alpha: 0.85)
      ..strokeWidth = 1.3;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(
          Offset(x, ay), Offset(math.min(x + 4, size.width), ay), avgPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BizMonthsChartPainter old) =>
      old.months != months ||
      old.filter != filter ||
      old.avgNet != avgNet ||
      old.textColor != textColor;
}

/// Net profit of deals sold in Jalali [year]/[month] (by sell date, after
/// کد و نقشه). The same figure is added to that month's net.
double tradeProfitInMonth(Iterable<PropertyTrade> trades, int year, int month) {
  final key = bizMonthKeyOf(year, month);
  var sum = 0.0;
  for (final t in trades) {
    if (t.sellMonth == key) sum += t.profit!;
  }
  return sum;
}

/// Months of the snapshot year whose typed income only repeats the deal
/// profit (old «پر کردن درآمد»). That income is left out of net so the deal
/// is not counted twice; the user is asked to clear or correct it.
int bizMismatchMonths(BizSnapshot s) =>
    s.months.where((m) => m.incomeDupTrades).length;

class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.store,
    required this.m,
    required this.filter,
  });
  final BizStore store;
  final PerfMonthSummary m;
  final Set<PerfDomain> filter;

  @override
  Widget build(BuildContext context) {
    final bm = m.bizMonth;
    final canEditOffice = !store.readOnly && m.includesOffice(filter);
    final flag = m.includesOffice(filter) && m.incomeDupTrades;
    final empty = m.isEmptyFor(filter);
    final net = m.netFor(filter);
    final soldCount = m.soldCountFor(filter);
    final tradeProfit = m.tradeProfitFor(filter);
    final boughtCount = m.boughtCountFor(filter);
    final boughtAmount = m.boughtAmountFor(filter);
    final dealDomains = m.activeDealDomainsFor(filter);
    final monthDeals = m.dealsFor(filter);

    return PendingSyncMark(
      pending: bm?.raw['pending_sync'] == true,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          key: ValueKey('biz-month-${m.month}'),
          borderRadius: BorderRadius.circular(12),
          onTap: canEditOffice
              ? () => _editMonth(
                    context,
                    store,
                    bm ?? placeholderBizMonth(m.year, m.month),
                  )
              : (monthDeals.isNotEmpty
                  ? () => showPerfMonthDealsSheet(context, month: m, filter: filter)
                  : null),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Row(children: [
                    Flexible(
                      child: Text('برج ${m.month} · ${pwoMonthNames[m.month - 1]}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    if (canEditOffice) ...[
                      const SizedBox(width: 5),
                      const Icon(Icons.edit_outlined, size: 13, color: AppTheme.muted),
                    ],
                  ]),
                ),
                const SizedBox(width: 8),
                _fit(Text(empty ? '—' : _m(net),
                    key: ValueKey('biz-month-net-${m.month}'),
                    style: TextStyle(
                        color: empty ? AppTheme.muted : _sign(net),
                        fontWeight: FontWeight.w800))),
              ]),
              if (!empty) ...[
                const SizedBox(height: 4),
                Wrap(spacing: 12, runSpacing: 2, children: [
                  if (m.hasOfficeActivityFor(filter))
                    _t(flag
                        ? 'درآمد ${_m(m.income)} (تکراری، حساب نشد)'
                        : 'درآمد ${_m(m.income)}'),
                  if (soldCount > 0)
                    Text('سود معاملات ($soldCount مورد) ${_m(tradeProfit)}',
                        key: ValueKey('biz-month-tp-${m.month}'),
                        style: TextStyle(
                            color: _sign(tradeProfit),
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  if (m.hasOfficeActivityFor(filter)) ...[
                    _t('کارمندان ${_m(m.staff)}'),
                    _t('PWO ${_m(m.pwo)}'),
                    _t('تبلیغات ${_m(m.ads)}'),
                  ],
                ]),
                if (dealDomains.length > 1 ||
                    (dealDomains.length == 1 &&
                        dealDomains.single != PerfDomain.property)) ...[
                  const SizedBox(height: 5),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final d in dealDomains)
                      if ((m.profitByDomain[d] ?? 0) != 0 ||
                          (m.soldCountByDomain[d] ?? 0) > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: perfDomainColor(d).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: perfDomainColor(d).withValues(alpha: 0.35),
                              width: 0.7,
                            ),
                          ),
                          child: Text(
                            '${d.shortLabel}: ${(m.profitByDomain[d] ?? 0) >= 0 ? '+' : '-'}${formatCompactToman((m.profitByDomain[d] ?? 0).abs())}',
                            style: TextStyle(
                              color: _sign(m.profitByDomain[d] ?? 0),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                  ]),
                ],
                if (boughtCount > 0) ...[
                  const SizedBox(height: 3),
                  Row(key: ValueKey('biz-month-bought-${m.month}'), children: [
                    const Icon(Icons.shopping_bag_outlined,
                        size: 13, color: AppTheme.muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                          'خرید / سرمایه‌گذاری: $boughtCount مورد · ${_m(boughtAmount)} (در خالص حساب نمی‌شود)',
                          style: const TextStyle(color: AppTheme.muted, fontSize: 11.5)),
                    ),
                  ]),
                ],
                if (m.note.isNotEmpty && m.includesOffice(filter)) ...[
                  const SizedBox(height: 5),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.notes_rounded, size: 13, color: AppTheme.muted),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(m.note,
                          key: ValueKey('biz-month-note-${m.month}'),
                          style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                    ),
                  ]),
                ],
                if (flag) ...[
                  const SizedBox(height: 4),
                  Row(key: ValueKey('biz-month-flag-${m.month}'), children: const [
                    Icon(Icons.info_outline_rounded, size: 13, color: AppTheme.negative),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                          'درآمد این ماه همان سود معاملات است و دوبار حساب نشد؛ برای اصلاح، ماه را باز کنید.',
                          style: TextStyle(color: AppTheme.negative, fontSize: 11)),
                    ),
                  ]),
                ],
                if (monthDeals.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: InkWell(
                      key: ValueKey('biz-month-deals-${m.month}'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => showPerfMonthDealsSheet(
                        context,
                        month: m,
                        filter: filter,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.receipt_long_outlined,
                                size: 13, color: AppTheme.accent),
                            const SizedBox(width: 4),
                            Text(
                              'جزئیات ${monthDeals.length} معامله',
                              style: const TextStyle(
                                color: AppTheme.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ]),
          ),
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
    builder: (_) => _MonthDialog(m: m, tradeProfit: m.tradeProfit),
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
  late final _note = TextEditingController(text: widget.m.note);

  @override
  void initState() {
    super.initState();
    for (final c in [_staff, _ads, _income]) {
      c.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _staff.dispose();
    _ads.dispose();
    _income.dispose();
    _note.dispose();
    super.dispose();
  }

  Widget _f(TextEditingController c, String label, Key key, {bool num = true, int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: key,
          controller: c,
          maxLines: maxLines,
          keyboardType: num ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final inc = parseFlexibleNumber(_income.text) ?? 0;
    final stf = parseFlexibleNumber(_staff.text) ?? 0;
    final ads = parseFlexibleNumber(_ads.text) ?? 0;
    // Same rule as the table: income equal to the deal profit is not
    // counted twice; the deal profit itself is always added.
    final dup = incomeDuplicatesTrades(inc, widget.tradeProfit, m.tradeGross);
    final previewNet = (dup ? 0 : inc) - stf - m.pwo - ads + widget.tradeProfit;
    final tradeToman = formatMoney(widget.tradeProfit, forceToman: true);
    final pwoToman = formatMoney(m.pwo, forceToman: true);
    final netToman = formatMoney(previewNet, forceToman: true);
    final netUsd = CurrencyMode.isUsd ? ' (${formatMoney(previewNet)})' : '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('برج ${m.month} · ${pwoMonthNames[m.month - 1]} ${m.year}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _f(_income, 'درآمد (تومان)', const ValueKey('biz-m-income')),
            if (m.soldCount > 0 || m.boughtCount > 0)
              Container(
                key: const ValueKey('biz-m-trades-info'),
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  [
                    if (m.soldCount > 0)
                      'سود ${m.soldCount} معاملهٔ فروخته‌شدهٔ این ماه ($tradeToman) خودکار به خالص اضافه می‌شود؛ آن را در «درآمد» وارد نکنید.',
                    if (m.boughtCount > 0)
                      'خرید ملک این ماه: ${m.boughtCount} مورد · ${formatMoney(m.boughtAmount, forceToman: true)}',
                  ].join('\n'),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ),
            if (dup)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('biz-m-clear-dup'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.negative),
                  onPressed: () => setState(() => _income.text = ''),
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: const Text('درآمد تکراری است (همان سود معاملات) — صفر کن',
                      textAlign: TextAlign.right),
                ),
              ),
            _f(_staff, 'کارمندان (تومان)', const ValueKey('biz-m-staff')),
            _f(_ads, 'دیوار - تبلیغات دفتر (تومان)', const ValueKey('biz-m-ads')),
            _f(_note, 'یادداشت ماه', const ValueKey('biz-m-note'), num: false, maxLines: 2),
            Container(
              key: const ValueKey('biz-m-net-preview'),
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                'خالص ماه: $netToman$netUsd${widget.tradeProfit != 0 ? ' (با سود معاملات)' : ''}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: previewNet < 0 ? AppTheme.negative : AppTheme.positive,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(MaterialPageRoute(builder: (_) => const PwoPage()));
                },
                child: Text('PWO این ماه: $pwoToman\nویرایش در بخش PWO',
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
            onPressed: () {
              final nextNote = _note.text.trim();
              final body = <String, dynamic>{
                'staff': parseFlexibleNumber(_staff.text) ?? 0,
                'ads': parseFlexibleNumber(_ads.text) ?? 0,
                'income': parseFlexibleNumber(_income.text) ?? 0,
                if (nextNote != widget.m.note) 'note': nextNote,
              };
              Navigator.pop(context, _DialogResult(body));
            },
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
  const BizDashboardCard({super.key, this.store, this.pwoStore, this.digits = _same});
  final BizStore? store;
  final PwoStore? pwoStore;

  /// Digit style for the figures (the dashboard passes Persian digits).
  final String Function(String) digits;
  static String _same(String s) => s;

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
        final mism = bizMismatchMonths(s);
        Widget tile(String k, String label, String value, {Color? color}) =>
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                decoration: BoxDecoration(
                  color: AppTheme.bg.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.digits(label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(widget.digits(value),
                        key: ValueKey('biz-dash-$k'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: color ?? AppTheme.title,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5)),
                  ],
                ),
              ),
            );
        Widget stat(String k, String label, String value, {Color? color}) =>
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: Text(widget.digits(label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Text(widget.digits(value),
                    key: ValueKey('biz-dash-$k'),
                    style: TextStyle(
                        color: color ?? AppTheme.title,
                        fontWeight: FontWeight.w700)),
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
                    const Icon(Icons.home_work_outlined,
                        color: AppTheme.positive, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(y == null ? 'ملک و دفتر' : widget.digits('ملک و دفتر · $y'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.title,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                    ),
                    const Icon(Icons.chevron_left_rounded, color: AppTheme.muted),
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
                    const SizedBox(height: 10),
                    Row(children: [
                      tile('profit', 'سود معاملات فروخته‌شده ($soldN)',
                          _m(s.totalProfit),
                          color: s.totalProfit < 0
                              ? AppTheme.negative
                              : AppTheme.positive),
                      const SizedBox(width: 8),
                      tile('open', 'معاملات باز', '$open'),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      tile('income', 'درآمد دفتر امسال',
                          _m(s.monthTotals['income_effective'] ?? s.monthTotals['income'] ?? 0)),
                      const SizedBox(width: 8),
                      tile('net', 'خالص ماهانه امسال', _m(net),
                          color: net < 0 ? AppTheme.negative : null),
                    ]),
                    if (pwoT != null && pwoT > 0 && pwoMonths.isNotEmpty) ...[
                      stat(
                          'pwo',
                          'PWO ماه ${pwoMonths.last.month} از هدف ${_m(pwoT)}',
                          _m(pwoMonths.last.pwo),
                          color: pwoMonths.last.pwo <= pwoT
                              ? AppTheme.positive
                              : AppTheme.negative),
                      stat(
                          'pwo-hit',
                          'ماه‌های در محدودهٔ هدف PWO',
                          '${pwoMonths.where((m) => m.pwo <= pwoT).length} از ${pwoMonths.length}'),
                    ],
                    if (mism > 0)
                      stat('mismatch', 'ماه با درآمد تکراری', '$mism',
                          color: AppTheme.negative),
                    if (store.showingCache)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('نسخهٔ ذخیره‌شده (آفلاین)',
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


/// Every module's data for the comprehensive export; empty when there is no
/// app state (then the report stays biz-only).
Future<Map<String, List<List<Object?>>>> _fullSheets(BuildContext context, BizStore store) async {
  AppState? state;
  try {
    state = Provider.of<AppState>(context, listen: false);
  } catch (_) {
    return const {};
  }
  final months = await store.monthsAllYears();
  final usdt = state.liveUsdt ?? state.settings.usdtTmnRate;
  final snap = DashboardSnapshot.compute(
    assets: state.assets,
    openTrades: state.openTrades,
    closedTrades: state.closedTrades,
    usdtTmn: usdt,
    calendar: state.settings.calendar,
    metrics: state.metrics,
    checks: state.checks,
  );
  final now = DateTime.now();
  final yearKey = '${store.snap.year ?? currentJalaliYear()}';
  final b = state.realizedBreakdown;
  final ps = ProjectsStore.instance;
  final pwo = PwoStore.instance;
  final sms = BankSmsStore.instance;
  return buildFullExport(
    now: now,
    yearKey: yearKey,
    holdings: snap.holdings,
    holdingsValue: snap.holdingsValue,
    nav: snap.marketValue,
    openTrades: state.openTrades,
    closedTrades: state.closedTrades,
    tradesRealized: b.trades,
    yearTradesRealized: snap.yearRealizedPnl,
    biz: store.snap,
    bizMonths: months,
    projects: ps.loaded ? ps.snap.items : const [],
    pwo: pwo.loaded ? pwo.ledger : null,
    withdrawals: state.withdrawals,
    checks: state.checks,
    smsHistory: sms.history,
    priceAlerts: state.settings.priceAlerts,
    usdtTmn: usdt,
  );
}

/// Test hook: replaces the share sheet.
@visibleForTesting
Future<void> Function(Uint8List bytes, String name, String mime)? bizShareOverride;

/// Annual Excel/PDF export of ملک و دفتر (also a dashboard quick action).
Future<void> exportBizAnnual(BuildContext context, BizStore store) async {
  // From Settings the office data may not be loaded yet.
  if (!store.loaded) {
    try {
      await ensureBizReady(context, store);
    } catch (_) {}
  }
  if (context.mounted) await _exportAnnual(context, store);
}

Future<void> _exportAnnual(BuildContext context, BizStore store) async {
  final year = store.snap.year;
  final kind = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text('خروجی سالانهٔ ${year ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('گزارش جامع تا این لحظه: خلاصه، دارایی‌ها، معاملات، ملک، جدول ماهانه، تبلیغات، PWO، برداشت‌ها، چک‌ها، پروژه‌ها، پیامک بانکی و هشدارها'),
          ),
          ListTile(
            key: const ValueKey('biz-export-xlsx'),
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Excel (xlsx)'),
            onTap: () => Navigator.pop(c, 'xlsx'),
          ),
          ListTile(
            key: const ValueKey('biz-export-pdf'),
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF'),
            onTap: () => Navigator.pop(c, 'pdf'),
          ),
        ]),
      ),
    ),
  );
  if (kind == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    store.lastFailedYears = const [];
    final r = BizAnnualReport.from(store.snap, year: store.snap.year ?? currentJalaliYear(), extra: await _fullSheets(context, store));
    final failed = store.lastFailedYears;
    late Uint8List bytes;
    late String mime;
    if (kind == 'xlsx') {
      bytes = r.toXlsx();
      mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    } else {
      bytes = await r.toPdf(
          font: await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'),
          bold: await rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf'));
      mime = 'application/pdf';
    }
    final name = '${r.fileStem}.$kind';
    final o = bizShareOverride;
    if (o != null) {
      await o(bytes, name, mime);
    } else {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: mime, name: name)],
        subject: 'گزارش سالانهٔ ملک و دفتر ${r.year}',
      ));
    }
    if (failed.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
          key: const ValueKey('biz-export-failed-years'),
          duration: const Duration(seconds: 8),
          content: Text(
              'جدول ماهانهٔ سال ${failed.join('، ')} دریافت نشد و در خروجی نیست؛ با اینترنت دوباره بگیرید.')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('ساخت خروجی انجام نشد: $e')));
  }
}

/// «ثبت مبلغ تبلیغات» (dashboard shortcut): adds an advertising cost to the
/// office monthly table of the entry's month (→ «عملکرد», ads and net).
Future<void> showAddAdsSheet(BuildContext context, {BizStore? store}) async {
  final s = store ?? BizStore.instance;
  if (!s.loaded) await ensureBizReady(context, s);
  if (!context.mounted) return;
  if (s.readOnly) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('برای ثبت تبلیغات وارد حساب شوید (ملک و دفتر فقط‌خواندنی است).')));
    return;
  }
  final j = Jalali.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final dateCtl = TextEditingController(text: '${j.year}/${two(j.month)}/${two(j.day)}');
  final amountCtl = TextEditingController();
  final noteCtl = TextEditingController();
  String? err;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(builder: (c, set) {
        final inset = MediaQuery.viewInsetsOf(c).bottom;
        final pad = MediaQuery.viewPaddingOf(c).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + (inset > pad ? inset : pad)),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('ثبت مبلغ تبلیغات',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.title)),
              const SizedBox(height: 4),
              const Text('به ستون «تبلیغات» همان ماه در جدول ماهانه (عملکرد) اضافه می‌شود و خالص ماه را کم می‌کند.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12)),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('ads-amount'),
                controller: amountCtl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('ads-date'),
                controller: dateCtl,
                keyboardType: TextInputType.datetime,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'تاریخ (شمسی)', hintText: '1405/08/03'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('ads-note'),
                controller: noteCtl,
                decoration: const InputDecoration(labelText: 'یادداشت (اختیاری) — مثلاً دیوار'),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, key: const ValueKey('ads-error'), style: const TextStyle(color: AppTheme.negative, fontSize: 12)),
              ],
              const SizedBox(height: 14),
              FilledButton(
                key: const ValueKey('ads-save'),
                onPressed: () {
                  final a = parseFlexibleNumber(amountCtl.text);
                  final d = _parseJalali(dateCtl.text);
                  if (a == null || a <= 0) return set(() => err = 'مبلغ معتبر وارد کنید');
                  if (d == null) return set(() => err = 'تاریخ را به شکل ۱۴۰۵/۰۸/۰۳ وارد کنید');
                  Navigator.pop(c, true);
                },
                child: const Text('ثبت'),
              ),
            ]),
          ),
        );
      }),
    ),
  );
  if (ok != true || !context.mounted) return;
  final amount = parseFlexibleNumber(amountCtl.text)!;
  final d = _parseJalali(dateCtl.text)!;
  final date = '${d.year}/${two(d.month)}/${two(d.day)}';
  final done = await _guard(context, () => s.addAds(d.year, d.month, amount, date: date, note: noteCtl.text));
  if (done && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text('تبلیغات ${formatMoney(amount)} برای ${pwoMonthNames[d.month - 1]} ${d.year} ثبت شد')));
  }
}

Jalali? _parseJalali(String raw) {
  final t = raw.trim().replaceAllMapped(RegExp('[۰-۹]'), (m) => '${'۰۱۲۳۴۵۶۷۸۹'.indexOf(m[0]!)}').replaceAll('-', '/');
  final p = t.split('/');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  if (y == null || m == null || d == null || y < 1300 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  try {
    final j = Jalali(y, m, d);
    return j.day == d ? j : null;
  } catch (_) {
    return null;
  }
}
