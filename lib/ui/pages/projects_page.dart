import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invest/ui/widgets/offline_banner.dart';
import 'package:provider/provider.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'package:invest/config/app_config.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/data/write_queue.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/biz_page.dart' show parseBizDate, bizDateText;
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/app_date_picker.dart';
import 'package:invest/ui/widgets/pending_writes_panel.dart';

/// Binds [store] to the signed-in Vinor account, or shows its cache offline.
Future<void> ensureProjectsReady(BuildContext context, ProjectsStore store,
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
    return store.bindAccount(remote.projects, phone);
  }
  if (app == null && store.isRemote) return store.refresh();
  if (app == null && store.loaded) return Future.value();
  return store.loadOffline();
}

void openProjectsPage(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const ProjectsPage()));

String _m(num v) => formatMoney(v);
Color _sign(num v) => v < 0 ? AppTheme.negative : AppTheme.positive;
String _pct(double? p) => p == null ? '' : '\u2066${p.round()}٪\u2069';

Color projectStatusColor(ProjectStatus s) => switch (s) {
      ProjectStatus.finished => AppTheme.positive,
      ProjectStatus.active => const Color(0xFFE0C46A),
      ProjectStatus.pipeline => AppTheme.muted,
    };

Future<bool> _guard(BuildContext context, Future<void> Function() op) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await op();
    return true;
  } on WriteQueuedException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    return false;
  }
}

/// Status filter of the list. [archived] shows only archived rows.
enum ProjectFilter { all, active, finished, pipeline, archived }

/// Rows matching [filter], the optional [year] and 'YYYY/MM' [month].
List<Project> filterProjects(
  Iterable<Project> rows,
  ProjectFilter filter, {
  int? year,
  String? month,
}) {
  final out = <Project>[];
  for (final p in rows) {
    if (filter == ProjectFilter.archived) {
      if (!p.archived) continue;
    } else {
      if (p.archived) continue;
      final ok = switch (filter) {
        ProjectFilter.active => p.status == ProjectStatus.active,
        ProjectFilter.finished => p.status == ProjectStatus.finished,
        ProjectFilter.pipeline => p.status == ProjectStatus.pipeline,
        _ => true,
      };
      if (!ok) continue;
    }
    if (month != null && p.monthKey != month) continue;
    if (month == null && year != null && p.year != year) continue;
    out.add(p);
  }
  int rank(Project p) => switch (p.status) {
        ProjectStatus.active => 0,
        ProjectStatus.finished => 1,
        ProjectStatus.pipeline => 2,
      };
  out.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return (b.monthKey ?? '').compareTo(a.monthKey ?? '');
  });
  return out;
}

String projectMonthLabel(String key) {
  final p = key.split('/');
  final m = int.tryParse(p.last) ?? 1;
  return '${pwoMonthNames[(m - 1).clamp(0, 11)]} ${p.first}';
}

/// «پروژه‌ها / پیمانکاری»: the contracting sheet as a list.
class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key, this.store});
  final ProjectsStore? store;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  late final ProjectsStore _store = widget.store ?? ProjectsStore.instance;
  ProjectFilter _filter = ProjectFilter.all;
  int? _year;
  String? _month;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureProjectsReady(context, _store);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('پروژه‌ها / پیمانکاری'),
          bottom: connectionStripFor(context, queuesWrites: true),
          actions: [
            ListenableBuilder(
              listenable: _store,
              builder: (context, _) => IconButton(
                key: const ValueKey('proj-import'),
                tooltip: 'ورود از شیت',
                icon: const Icon(Icons.upload_file_rounded),
                onPressed: _store.isRemote
                    ? () => importProjectsSheet(context, _store)
                    : null,
              ),
            ),
          ],
        ),
        floatingActionButton: ListenableBuilder(
          listenable: _store,
          builder: (context, _) => _store.loaded && !_store.readOnly
              ? FloatingActionButton.extended(
                  key: const ValueKey('proj-add'),
                  heroTag: 'proj-add',
                  onPressed: () => editProject(context, _store, null),
                  icon: const Icon(Icons.add),
                  label: const Text('ثبت پروژه'),
                )
              : const SizedBox.shrink(),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        body: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            final err = _store.lastError;
            final banner = _store.showingCache || err != null
                ? MaterialBanner(
                    content: Text(err ?? offlineQueueNote),
                    actions: [
                      TextButton(
                          onPressed: () => ensureProjectsReady(context, _store),
                          child: const Text('تلاش دوباره')),
                    ],
                  )
                : null;
            if (!_store.loaded) {
              if (banner != null && !_store.syncing) {
                return Column(children: [banner]);
              }
              return const Center(child: CircularProgressIndicator());
            }
            return Column(children: [
              if (banner != null) banner,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: PendingWritesPanel(
                    queue: _store.queue,
                    onSendNow: () => ensureProjectsReady(context, _store)),
              ),
              if (_store.syncing) const LinearProgressIndicator(minHeight: 2),
              Expanded(child: _list(context)),
            ]);
          },
        ),
      ),
    );
  }

  Widget _chips(List<(Object?, String, Key)> items, Object? selected,
      ValueChanged<Object?> onTap) {
    return SizedBox(
      height: 40,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (v, label, key) in items) ...[
            ChoiceChip(
              key: key,
              label: Text(label),
              selected: v == selected,
              onSelected: (_) => onTap(v),
            ),
            const SizedBox(width: 6),
          ],
        ]),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final store = _store;
    final all = store.snap.items;
    final live = [for (final p in all) if (!p.archived) p];
    final years = <int>{for (final p in all) if (p.year != null) p.year!}.toList()
      ..sort((a, b) => b.compareTo(a));
    final year = years.contains(_year) ? _year : null;
    final months = year == null
        ? const <String>[]
        : (<String>{
            for (final p in all)
              if (p.year == year && p.monthKey != null) p.monthKey!
          }.toList()
          ..sort((a, b) => b.compareTo(a)));
    final month = months.contains(_month) ? _month : null;
    final rows = filterProjects(all, _filter, year: year, month: month);
    final t = ProjectTotals.of(
        _filter == ProjectFilter.archived ? const <Project>[] : rows);
    final shownTotals = _filter == ProjectFilter.archived
        ? ProjectTotals.of([
            for (final p in rows) Project({...p.raw, 'archived': false})
          ])
        : t;
    int count(ProjectStatus s) => live.where((p) => p.status == s).length;
    final period = month != null
        ? projectMonthLabel(month)
        : year != null
            ? 'سال $year'
            : 'همهٔ دوره‌ها';

    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 96 + MediaQuery.paddingOf(context).bottom),
        children: [
          _chips([
            (ProjectFilter.all, 'همه (${live.length})', const ValueKey('proj-f-all')),
            (ProjectFilter.active, 'در جریان (${count(ProjectStatus.active)})',
                const ValueKey('proj-f-active')),
            (ProjectFilter.finished, 'تمام‌شده (${count(ProjectStatus.finished)})',
                const ValueKey('proj-f-finished')),
            (ProjectFilter.pipeline, 'در صف (${count(ProjectStatus.pipeline)})',
                const ValueKey('proj-f-pipeline')),
            (ProjectFilter.archived, 'بایگانی (${store.snap.archivedCount})',
                const ValueKey('proj-f-archived')),
          ], _filter, (v) => setState(() => _filter = v as ProjectFilter)),
          if (years.isNotEmpty) ...[
            const SizedBox(height: 6),
            _chips([
              (null, 'همهٔ سال‌ها', const ValueKey('proj-y-all')),
              for (final y in years) (y, '$y', ValueKey('proj-y-$y')),
            ], year, (v) => setState(() {
                  _year = v as int?;
                  _month = null;
                })),
          ],
          if (months.isNotEmpty) ...[
            const SizedBox(height: 6),
            _chips([
              (null, 'همهٔ ماه‌ها', const ValueKey('proj-m-all')),
              for (final m in months)
                (m, projectMonthLabel(m), ValueKey('proj-m-$m')),
            ], month, (v) => setState(() => _month = v as String?)),
          ],
          const SizedBox(height: 10),
          _TotalsCard(t: shownTotals, period: period, archived: _filter == ProjectFilter.archived),
          const SizedBox(height: 10),
          if (!store.readOnly && all.isEmpty && store.isRemote) ...[
            OutlinedButton.icon(
              key: const ValueKey('proj-import-empty'),
              onPressed: () => importProjectsSheet(context, store),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('ورود از شیت'),
            ),
            const SizedBox(height: 10),
          ],
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                  _filter == ProjectFilter.archived
                      ? 'پروژهٔ بایگانی‌شده‌ای ندارید.'
                      : 'پروژه‌ای در این فیلتر نیست.',
                  key: const ValueKey('proj-empty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.muted)),
            ),
          for (final p in rows) ...[
            ProjectTile(store: store, p: p),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.t, required this.period, required this.archived});
  final ProjectTotals t;
  final String period;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    Widget row(String k, String label, String value, {Color? color, String? hint}) =>
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                if (hint != null)
                  Text(hint,
                      style: TextStyle(
                          color: AppTheme.muted.withValues(alpha: 0.8), fontSize: 10.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(value,
                    key: ValueKey('proj-t-$k'),
                    style: TextStyle(
                        color: color ?? AppTheme.title,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5)),
              ),
            ),
          ]),
        );
    return Card(
      key: const ValueKey('proj-totals'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(archived ? 'بایگانی · $period' : period,
              style: const TextStyle(color: AppTheme.title, fontWeight: FontWeight.w800)),
          if (archived)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                  'پروژه‌های بایگانی‌شده پاک نشده‌اند ولی در سود و زیان و داشبورد حساب نمی‌شوند.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 11.5)),
            ),
          row('realized', 'سود تحقق‌یافته', _m(t.realized),
              color: _sign(t.realized),
              hint: '${t.finishedCount} پروژهٔ تمام‌شده · در سود و زیان کل حساب می‌شود'),
          row('expected', 'سود پیش‌بینی در جریان', _m(t.expected),
              color: t.expected == 0 ? AppTheme.muted : const Color(0xFFE0C46A),
              hint: '${t.activeCount} پروژه · قرارداد − هزینه تا امروز، هنوز حساب نشده'),
          row('sheet', 'جمع سود (مثل شیت)', _m(t.sheetProfit),
              color: _sign(t.sheetProfit)),
          row('contract', 'جمع قرارداد', _m(t.contract)),
          row('cost', 'جمع هزینه', _m(t.cost)),
          if (t.pipelineCount > 0)
            row('pipeline', 'در صف (بدون مبلغ)', '${t.pipelineCount} مورد'),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color, {super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            maxLines: 1,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class ProjectTile extends StatelessWidget {
  const ProjectTile({super.key, required this.store, required this.p});
  final ProjectsStore store;
  final Project p;

  @override
  Widget build(BuildContext context) {
    final profit = p.profit;
    final c = projectStatusColor(p.status);
    Widget kv(String k, String v) => Text('$k: $v',
        style: const TextStyle(color: AppTheme.muted, fontSize: 12));
    return Card(
      key: ValueKey('proj-tile-${p.id}'),
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: store.readOnly ? null : () => editProject(context, store, p),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(p.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
              _Tag(projectStatusLabel(p.status), c),
              if (p.archived) ...[
                const SizedBox(width: 4),
                const _Tag('بایگانی', AppTheme.muted, key: ValueKey('proj-archived-tag')),
              ],
            ]),
            const SizedBox(height: 6),
            if (profit != null)
              Row(children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                        '${profit < 0 ? 'زیان' : p.status == ProjectStatus.active ? 'سود پیش‌بینی' : 'سود'} ${_m(profit.abs())}',
                        style: TextStyle(
                            color: p.status == ProjectStatus.active
                                ? const Color(0xFFE0C46A)
                                : _sign(profit),
                            fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_pct(p.profitPct),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: _sign(profit), fontWeight: FontWeight.w700, fontSize: 12)),
              ])
            else
              const Text('هنوز مبلغی ثبت نشده',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(spacing: 12, runSpacing: 2, children: [
              if (p.contract > 0) kv('قرارداد', _m(p.contract)),
              if (p.cost > 0) kv('هزینه', _m(p.cost)),
              if (p.startDate.isNotEmpty) kv('شروع', p.startDate),
              if (p.endDate.isNotEmpty) kv('پایان', p.endDate),
              if (p.days != null) kv('مدت', '${p.days} روز'),
            ]),
            if (p.note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(p.note, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            ],
          ]),
        ),
      ),
    );
  }
}

Future<void> importProjectsSheet(BuildContext context, ProjectsStore store,
    {String? initial}) async {
  final ctl = TextEditingController(text: initial ?? '');
  final text = await showDialog<String>(
    context: context,
    builder: (c) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('ورود از شیت پیمانکاری'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'متن JSON شیت را بچسبانید. فقط ردیف‌های تازه اضافه می‌شوند؛ ردیف تکراری رد می‌شود و هیچ دادهٔ موجودی تغییر نمی‌کند.',
            style: TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('proj-import-text'),
            controller: ctl,
            maxLines: 6,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
                hintText: '{"projects": [...]}', isDense: true),
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
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('انصراف')),
          FilledButton(
              key: const ValueKey('proj-import-go'),
              onPressed: () => Navigator.pop(c, ctl.text),
              child: const Text('ورود')),
        ],
      ),
    ),
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  await importProjectsText(context, store, text);
}

/// Shared by the projects page and the biz «ورود از شیت» dialog.
Future<void> importProjectsText(
    BuildContext context, ProjectsStore store, String text) async {
  var res = (0, 0);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await _guard(context, () async => res = await store.importSheet(text));
  if (ok) {
    messenger?.showSnackBar(SnackBar(
        content: Text(res.$1 == 0
            ? 'ردیف تازه‌ای نبود؛ ${res.$2} ردیف از قبل ثبت شده بود.'
            : '${res.$1} پروژه وارد شد${res.$2 > 0 ? ' · ${res.$2} ردیف تکراری رد شد' : ''}.')));
  }
}

String _amountText(double v) => v == 0 ? '' : formatNumber(v);

class _ProjectResult {
  _ProjectResult(this.body, {this.action});
  final Map<String, dynamic> body;

  /// null = save, 'delete', 'archive', 'restore'.
  final String? action;
}

Future<void> editProject(BuildContext context, ProjectsStore store, Project? p) async {
  final res = await showDialog<_ProjectResult>(
    context: context,
    builder: (_) => ProjectDialog(p: p),
  );
  if (res == null || !context.mounted) return;
  switch (res.action) {
    case 'delete':
      await _guard(context, () => store.delete(p!));
    case 'archive':
      await _guard(context, () => store.setArchived(p!, true));
    case 'restore':
      await _guard(context, () => store.setArchived(p!, false));
    default:
      if (p == null) {
        await _guard(context, () => store.add(res.body));
      } else {
        await _guard(context, () => store.update(p.id, res.body));
      }
  }
}

/// Live preview, same formulas as the server (سود = قرارداد − هزینه، ٪ از قرارداد).
({double? profit, double? pct}) projectPreview(double contract, double cost) {
  if (contract <= 0) return (profit: null, pct: null);
  final profit = contract - cost;
  return (profit: profit, pct: profit / contract * 100);
}

class ProjectDialog extends StatefulWidget {
  const ProjectDialog({super.key, this.p});
  final Project? p;

  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  late final _title = TextEditingController(text: widget.p?.title ?? '');
  late final _work = TextEditingController(text: widget.p?.workType ?? '');
  late final _start = TextEditingController(text: widget.p?.startDate ?? '');
  late final _end = TextEditingController(text: widget.p?.endDate ?? '');
  late final _contract = TextEditingController(text: _amountText(widget.p?.contract ?? 0));
  late final _cost = TextEditingController(text: _amountText(widget.p?.cost ?? 0));
  late final _note = TextEditingController(text: widget.p?.note ?? '');
  late String _mode = widget.p?.statusMode ?? 'auto';
  String? _err;

  @override
  void initState() {
    super.initState();
    for (final c in [_start, _end, _contract, _cost]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _work, _start, _end, _contract, _cost, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _f(TextEditingController c, String label, {bool num = false, String? hint, required String k}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          key: ValueKey(k),
          controller: c,
          keyboardType: num ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
        ),
      );

  Future<void> _pick(TextEditingController c, String label) async {
    final cur = parseBizDate(c.text) ?? parseBizDate(_start.text);
    final iso = await pickAppDate(context,
        calendar: AppConfig.calendarJalali,
        initialIso: cur == null ? null : toIsoDate(cur.toDateTime()),
        firstDate: Jalali(1390, 1, 1).toDateTime(),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
        helpText: label);
    if (iso == null) return;
    c.text = bizDateText(Jalali.fromDateTime(parseIsoDate(iso)));
  }

  Widget _date(TextEditingController c, String label, String k) {
    final txt = c.text.trim();
    final j = txt.isEmpty ? null : parseBizDate(txt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        key: ValueKey(k),
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          hintText: '1405/01/20',
          isDense: true,
          errorText: txt.isNotEmpty && j == null ? 'تاریخ نامعتبر است.' : null,
          suffixIcon: IconButton(
            tooltip: 'انتخاب از تقویم',
            icon: const Icon(Icons.calendar_month_outlined, size: 20),
            onPressed: () => _pick(c, label),
          ),
        ),
      ),
    );
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _err = 'نام کارفرما یا عنوان لازم است.');
      return;
    }
    String? date(TextEditingController c) {
      final t = c.text.trim();
      if (t.isEmpty) return '';
      final j = parseBizDate(t);
      return j == null ? null : bizDateText(j);
    }

    final s = date(_start), e = date(_end);
    if (s == null || e == null) {
      setState(() => _err = 'تاریخ نامعتبر است.');
      return;
    }
    if (s.isNotEmpty && e.isNotEmpty && e.compareTo(s) < 0) {
      setState(() => _err = 'تاریخ پایان نمی‌تواند قبل از تاریخ شروع باشد.');
      return;
    }
    final contract = parseFlexibleNumber(_contract.text) ?? 0;
    final cost = parseFlexibleNumber(_cost.text) ?? 0;
    if (contract < 0 || cost < 0) {
      setState(() => _err = 'مبلغ نمی‌تواند منفی باشد.');
      return;
    }
    if ((_mode == 'active' || _mode == 'finished') && contract <= 0) {
      setState(() => _err = 'برای پروژهٔ در جریان یا تمام‌شده، مبلغ قرارداد لازم است.');
      return;
    }
    Navigator.pop(
        context,
        _ProjectResult({
          'title': title,
          'work_type': _work.text.trim(),
          'start_date': s,
          'end_date': e,
          'contract_amount': contract,
          'cost': cost,
          'status_mode': _mode,
          'note': _note.text.trim(),
        }));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final pv = projectPreview(
        parseFlexibleNumber(_contract.text) ?? 0, parseFlexibleNumber(_cost.text) ?? 0);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(p == null ? 'ثبت پروژه' : 'ویرایش پروژه'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _f(_title, 'کارفرما / عنوان', k: 'proj-f-title', hint: 'مثلاً نام کارفرما'),
            _f(_work, 'نوع کار', k: 'proj-f-work', hint: 'مثلاً دیوارکشی'),
            _date(_start, 'تاریخ شروع', 'proj-f-start'),
            _date(_end, 'تاریخ پایان', 'proj-f-end'),
            _f(_contract, 'مبلغ قرارداد (تومان)', num: true, k: 'proj-f-contract'),
            _f(_cost, 'هزینه (تومان)', num: true, k: 'proj-f-cost'),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DropdownButtonFormField<String>(
                key: const ValueKey('proj-f-mode'),
                initialValue: _mode,
                isDense: true,
                decoration: const InputDecoration(labelText: 'وضعیت', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('خودکار (از روی تاریخ و مبلغ)')),
                  DropdownMenuItem(value: 'pipeline', child: Text('در صف')),
                  DropdownMenuItem(value: 'active', child: Text('در جریان')),
                  DropdownMenuItem(value: 'finished', child: Text('تمام‌شده')),
                ],
                onChanged: (v) => setState(() => _mode = v ?? 'auto'),
              ),
            ),
            _f(_note, 'یادداشت', k: 'proj-f-note'),
            Container(
              key: const ValueKey('proj-f-preview'),
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border)),
              child: Text(
                pv.profit == null
                    ? 'بدون مبلغ قرارداد، پروژه «در صف» است'
                    : '${pv.profit! < 0 ? 'زیان' : 'سود'} ${_m(pv.profit!.abs())} (\u2066${pv.pct!.toStringAsFixed(1)}٪\u2069 از قرارداد)',
                style: TextStyle(
                    color: (pv.profit ?? 0) < 0 ? AppTheme.negative : AppTheme.positive,
                    fontSize: 12),
              ),
            ),
            if (p != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
            TextButton(
              key: const ValueKey('proj-delete'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: AlertDialog(
                      title: const Text('حذف پروژه'),
                      content: const Text('این پروژه برای همیشه حذف شود؟ برای کنار گذاشتن بدون حذف، «بایگانی» را بزنید.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
                      ],
                    ),
                  ),
                );
                if (ok == true && context.mounted) {
                  Navigator.pop(context, _ProjectResult(const {}, action: 'delete'));
                }
              },
              child: const Text('حذف', style: TextStyle(color: AppTheme.negative)),
            ),
            TextButton(
              key: const ValueKey('proj-archive'),
              onPressed: () => Navigator.pop(context,
                  _ProjectResult(const {}, action: p.archived ? 'restore' : 'archive')),
              child: Text(p.archived ? 'بازگردانی' : 'بایگانی'),
            ),
          
                ]),
              ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_err!,
                    key: const ValueKey('proj-f-error'),
                    style: const TextStyle(color: AppTheme.negative, fontSize: 12)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
              key: const ValueKey('proj-save'), onPressed: _save, child: const Text('ذخیره')),
        ],
      ),
    );
  }
}

/// Dashboard card: realized and expected profit plus counts.
class ProjectsDashboardCard extends StatefulWidget {
  const ProjectsDashboardCard({super.key, this.store, this.digits = _same});
  final ProjectsStore? store;
  final String Function(String) digits;
  static String _same(String s) => s;

  @override
  State<ProjectsDashboardCard> createState() => _ProjectsDashboardCardState();
}

class _ProjectsDashboardCardState extends State<ProjectsDashboardCard> {
  ProjectsStore get _store => widget.store ?? ProjectsStore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureProjectsReady(context, _store, refresh: false).catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        // Nothing to show yet: stay invisible (the card still binds the store).
        if (!_store.snap.hasData) return const SizedBox.shrink();
        final t = _store.snap.totals;
        final d = widget.digits;
        Widget tile(String k, String label, String value, {Color? color}) => Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                decoration: BoxDecoration(
                  color: AppTheme.bg.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d(label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(d(value),
                        key: ValueKey('proj-dash-$k'),
                        maxLines: 1,
                        style: TextStyle(
                            color: color ?? AppTheme.title,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5)),
                  ),
                ]),
              ),
            );
        return Material(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: const ValueKey('proj-dash-card'),
            borderRadius: BorderRadius.circular(18),
            onTap: () => openProjectsPage(context),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Row(children: [
                  Icon(Icons.engineering_rounded, color: AppTheme.accent, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('پروژه‌ها / پیمانکاری',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppTheme.title, fontWeight: FontWeight.w800)),
                  ),
                  Icon(Icons.chevron_left_rounded, color: AppTheme.muted),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  tile('realized', 'سود تحقق‌یافته', _m(t.realized), color: _sign(t.realized)),
                  const SizedBox(width: 8),
                  tile('expected', 'پیش‌بینی در جریان', _m(t.expected),
                      color: t.expected == 0 ? AppTheme.muted : const Color(0xFFE0C46A)),
                ]),
                const SizedBox(height: 8),
                Wrap(
                  key: const ValueKey('proj-dash-counts'),
                  spacing: 14,
                  children: [
                    for (final (n, l) in [
                      (t.finishedCount, 'تمام‌شده'),
                      (t.activeCount, 'در جریان'),
                      (t.pipelineCount, 'در صف'),
                    ])
                      Text(d('$n $l'),
                          style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                  ],
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
