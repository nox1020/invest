import 'package:flutter/material.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/data/biz_store.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/models/asset.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/services/full_export.dart' show adsLine, jDate;
import 'package:invest/domain/services/global_search.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/home_tabs.dart';
import 'package:invest/ui/pages/asset_detail_page.dart';
import 'package:invest/ui/pages/biz_page.dart';
import 'package:invest/ui/pages/checks_page.dart';
import 'package:invest/ui/pages/price_alerts_page.dart';
import 'package:invest/ui/pages/projects_page.dart';
import 'package:invest/ui/pages/pwo_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/bank_sms_ui.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart' show fa;
import 'package:provider/provider.dart';

void openGlobalSearch(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const GlobalSearchPage()));

String _amt(num v) => '${v.round()} ${formatMoney(v)}';

/// Everything searchable in the app right now.
List<SearchItem> buildSearchItems(AppState s) {
  final out = <SearchItem>[];
  for (final c in s.checks) {
    out.add(SearchItem(
      kind: SearchKind.cheque,
      title: '${c.directionLabel} · ${c.counterparty.isEmpty ? 'بدون نام' : c.counterparty}',
      subtitle: '${formatMoney(c.amount)} · سررسید ${jDate(c.dueDate)} · ${c.statusLabel}'
          '${c.checkNumber.isEmpty ? '' : ' · ش ${c.checkNumber}'}'
          '${c.endorseSummary.isEmpty ? '' : ' · ${c.endorseSummary}'}',
      fields: [c.checkNumber, c.sayadId, c.counterparty, c.purpose, c.endorsedTo, c.endorsedFor, c.note, c.bankName, c.branch,
        c.directionLabel, c.statusLabel, _amt(c.amount), jDate(c.dueDate), jDate(c.issueDate)],
      ref: c,
    ));
  }
  for (final a in s.assets) {
    out.add(SearchItem(kind: SearchKind.asset, title: a.name, subtitle: a.symbol,
        fields: [a.name, a.symbol, a.notes], ref: a));
  }
  for (final t in [...s.openTrades, ...s.closedTrades]) {
    final closed = t.sellPrice != null;
    out.add(SearchItem(
      kind: SearchKind.trade,
      title: '${t.assetName} · ${closed ? 'بسته' : 'باز'}',
      subtitle: 'خرید ${jDate(t.buyDate)}${closed ? ' · فروش ${jDate(t.sellDate)}' : ''}',
      fields: [t.assetName, t.assetSymbol, t.buyNote, t.sellNote, jDate(t.buyDate), jDate(t.sellDate), _amt(t.buyPrice)],
      ref: t,
    ));
  }
  final biz = BizStore.instance.snap;
  for (final t in biz.trades) {
    out.add(SearchItem(
      kind: SearchKind.property,
      title: t.title.isEmpty ? 'معامله ملک' : t.title,
      subtitle: 'خرید ${t.buyDate}${t.sold ? ' · سود ${formatMoney(t.profit ?? 0)}' : ' · فروش نرفته'}',
      fields: [t.title, t.note, t.buyDate, t.sellDate, _amt(t.buyAmount), _amt(t.sellAmount)],
    ));
  }
  for (final m in biz.months) {
    for (final line in m.note.split('\n')) {
      final x = adsLine.firstMatch(line.trim());
      if (x == null) continue;
      out.add(SearchItem(kind: SearchKind.ads, title: 'تبلیغات ${x[1]}', subtitle: '${x[2]} تومان${x[3] == null ? '' : ' · ${x[3]}'}',
          fields: [line, '${pwoMonthNames[m.month - 1]} ${m.year}']));
    }
  }
  final ps = ProjectsStore.instance;
  if (ps.loaded) {
    for (final p in ps.snap.items) {
      out.add(SearchItem(kind: SearchKind.project, title: p.title, subtitle: '${p.workType} · قرارداد ${formatMoney(p.contract)}',
          fields: [p.title, p.workType, p.description, p.note, p.startDate, p.endDate, _amt(p.contract)]));
    }
  }
  final pwo = PwoStore.instance;
  if (pwo.loaded) {
    final l = pwo.ledger;
    for (final m in l.months.values) {
      for (final t in m.txs) {
        final who = l.personById(t.personId)?.name ?? t.personId;
        out.add(SearchItem(kind: SearchKind.pwo, title: '$who · ${pwoMonthNames[m.month - 1]} ${m.year}',
            subtitle: '${formatMoney(t.amount)}${t.note.isEmpty ? '' : ' · ${t.note}'}',
            fields: [who, t.note, _amt(t.amount), '${pwoMonthNames[m.month - 1]} ${m.year}']));
      }
      for (final e in m.amounts.entries) {
        if (e.value <= 0) continue;
        final who = l.personById(e.key)?.name ?? e.key;
        out.add(SearchItem(kind: SearchKind.pwo, title: '$who · ${pwoMonthNames[m.month - 1]} ${m.year}',
            subtitle: formatMoney(e.value), fields: [who, _amt(e.value), '${pwoMonthNames[m.month - 1]} ${m.year}']));
      }
    }
  }
  for (final w in s.withdrawals) {
    out.add(SearchItem(kind: SearchKind.withdrawal, title: formatMoney(w.amount), subtitle: '${jDate(w.createdAt)}${w.note.isEmpty ? '' : ' · ${w.note}'}',
        fields: [w.note, _amt(w.amount), jDate(w.createdAt), w.status]));
  }
  final sms = BankSmsStore.instance;
  for (final p in sms.pending) {
    out.add(SearchItem(kind: SearchKind.sms, title: '${p.bank} · در انتظار', subtitle: formatMoney(p.toman),
        fields: [p.bank, _amt(p.toman), p.card ?? '', 'در انتظار']));
  }
  for (final d in sms.history) {
    out.add(SearchItem(kind: SearchKind.sms, title: '${d.bank} · ${d.saved ? 'ثبت شد' : 'رد شد'}', subtitle: '${formatMoney(d.toman)} · ${jDate(d.at)}',
        fields: [d.bank, _amt(d.toman), jDate(d.at)]));
  }
  for (final a in s.settings.priceAlerts) {
    out.add(SearchItem(kind: SearchKind.alert, title: a.displayName,
        subtitle: [if (a.above != null) 'بالای ${formatMoney(a.above!)}', if (a.below != null) 'زیر ${formatMoney(a.below!)}'].join(' · '),
        fields: [a.displayName, a.id, a.symbol]));
  }
  return out;
}

IconData _icon(SearchKind k) => switch (k) {
      SearchKind.cheque => Icons.receipt_long_rounded,
      SearchKind.asset => Icons.account_balance_wallet_rounded,
      SearchKind.trade => Icons.swap_horiz_rounded,
      SearchKind.property => Icons.home_work_rounded,
      SearchKind.project => Icons.engineering_rounded,
      SearchKind.pwo => Icons.flag_rounded,
      SearchKind.withdrawal => Icons.payments_rounded,
      SearchKind.ads => Icons.campaign_rounded,
      SearchKind.sms => Icons.sms_rounded,
      SearchKind.alert => Icons.notifications_active_rounded,
    };

void _open(BuildContext context, SearchItem i) {
  final nav = Navigator.of(context);
  void push(Widget w) => nav.push(MaterialPageRoute<void>(builder: (_) => w));
  switch (i.kind) {
    case SearchKind.cheque:
      final c = i.ref as BankCheck;
      if (context.read<AppState>().canMutate) {
        openCheckEditor(context, existing: c);
      } else {
        openChecksPage(context);
      }
    case SearchKind.asset:
      final a = i.ref as Asset;
      if (a.id != null) openAssetDetail(context, asset: a);
    case SearchKind.trade:
      openHomeTab(context, HomeTabs.trades, popToRoot: true);
    case SearchKind.property:
      push(const BizPage());
    case SearchKind.ads:
      openHomeTab(context, HomeTabs.performance, popToRoot: true);
    case SearchKind.project:
      openProjectsPage(context);
    case SearchKind.pwo:
      push(const PwoPage());
    case SearchKind.withdrawal:
      openHomeTab(context, HomeTabs.withdrawals, popToRoot: true);
    case SearchKind.sms:
      openBankSmsPage(context);
    case SearchKind.alert:
      push(const PriceAlertsPage());
  }
}

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});
  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final _ctl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final groups = _q.trim().isEmpty
        ? const <SearchKind, List<SearchItem>>{}
        : searchAll(buildSearchItems(state), _q);
    final total = groups.values.fold<int>(0, (s, l) => s + l.length);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: TextField(
            key: const ValueKey('search-field'),
            controller: _ctl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'جستجو: شماره چک، نام، دارایی، ملک، پروژه…',
              border: InputBorder.none,
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('search-clear'),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() { _ctl.clear(); _q = ''; }),
                    ),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        body: _q.trim().isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('در چک‌ها (شماره، صیادی، صادرکننده / در وجه، بابت)، دارایی‌ها، معاملات، ملک، پروژه‌ها، PWO، برداشت‌ها، تبلیغات، پیامک‌های بانکی و هشدارها جستجو کنید.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted, height: 1.6)),
                ))
            : total == 0
                ? const Center(child: Text('چیزی پیدا نشد', key: ValueKey('search-empty'), style: TextStyle(color: AppTheme.muted)))
                : ListView(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 16 + MediaQuery.paddingOf(context).bottom),
                    children: [
                      for (final e in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                          child: Text(fa('${e.key.label} · ${e.value.length}'),
                              key: ValueKey('search-group-${e.key.name}'),
                              style: const TextStyle(color: AppTheme.title, fontWeight: FontWeight.w800)),
                        ),
                        for (final i in e.value)
                          Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              leading: Icon(_icon(i.kind), color: AppTheme.positive),
                              title: Text(i.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: i.subtitle.isEmpty ? null : Text(fa(i.subtitle), maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.chevron_left_rounded),
                              onTap: () => _open(context, i),
                            ),
                          ),
                      ],
                    ],
                  ),
      ),
    );
  }
}
