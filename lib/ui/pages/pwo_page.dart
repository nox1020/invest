import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shamsi_date/shamsi_date.dart';


import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';

const _good = AppTheme.positive;

/// Binds [store] to the signed-in Vinor account (server mode) when there is
/// one, otherwise loads the device-only ledger.
Future<void> ensurePwoReady(BuildContext context, PwoStore store,
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
    if (!refresh && store.account == phone && (store.loaded || store.syncing)) {
      return Future.value();
    }
    return store.bindAccount(remote.pwo, phone);
  }
  if (app != null && store.isRemote) store.unbind();
  return store.load();
}

Future<bool> _guard(BuildContext context, Future<void> Function() op) async {
  try {
    await op();
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Invalid argument(s): ', ''))),
      );
    }
    return false;
  }
}

const _bad = AppTheme.negative;

/// PWO — monthly personal withdrawals vs. monthly target.
class PwoPage extends StatefulWidget {
  const PwoPage({super.key, this.store});
  final PwoStore? store;

  @override
  State<PwoPage> createState() => _PwoPageState();
}

class _PwoPageState extends State<PwoPage> {
  late final PwoStore _store = widget.store ?? PwoStore.instance;
  int? _year;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensurePwoReady(context, _store);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PWO · برداشت ماهانه'),
          actions: [
            IconButton(
              tooltip: 'تنظیمات PWO',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => showPwoSettingsSheet(context, _store),
            ),
          ],
        ),
        floatingActionButton: ListenableBuilder(
          listenable: _store,
          builder: (context, _) => !_store.loaded
              ? const SizedBox.shrink()
              : FloatingActionButton.extended(
                  onPressed: _saving ? null : () => _edit(null),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('ثبت ماه'),
                ),
        ),
        body: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            if (!_store.loaded) {
              if (_store.lastError != null && !_store.syncing) {
                return _ErrorRetry(
                  message: _store.lastError!,
                  onRetry: () => _store.refresh(),
                );
              }
              return const Center(child: CircularProgressIndicator());
            }
            final l = _store.ledger;
            final years = l.years;
            final year = (_year != null && years.contains(_year))
                ? _year!
                : (years.isNotEmpty ? years.first : Jalali.now().year);
            final months = l.monthsOf(year);
            return RefreshIndicator(
              onRefresh: () => _store.refresh(),
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                if (_store.showingCache && _store.lastError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      key: const ValueKey('pwo-offline'),
                      color: _bad.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                            'نمایش دادهٔ ذخیره‌شده. ${_store.lastError}',
                            style: const TextStyle(color: _bad)),
                      ),
                    ),
                  ),
                if (years.length > 1)
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final y in years)
                        ChoiceChip(
                          label: Text('$y'),
                          selected: y == year,
                          onSelected: (_) => setState(() => _year = y),
                        ),
                    ],
                  ),
                _SummaryCard(
                  year: year,
                  total: l.yearTotal(year),
                  target: l.target,
                  met: l.monthsMeeting(year),
                  count: months.length,
                ),
                const SizedBox(height: 12),
                _PersonsCard(
                  names: [for (final p in l.peopleWithHistory) p.active ? p.name : '${p.name} (بایگانی)'],
                  totals: [for (final p in l.peopleWithHistory) l.personTotal(year, p.id)],
                ),
                const SizedBox(height: 12),
                _Card(
                  title: 'نمودار ماهانه',
                  child: SizedBox(
                    height: 200,
                    child: months.isEmpty
                        ? const Center(child: Text('هنوز ماهی ثبت نشده'))
                        : CustomPaint(
                            key: const ValueKey('pwo-chart'),
                            painter: _PwoChartPainter(
                              months: months,
                              target: l.target,
                              textColor:
                                  Theme.of(context).colorScheme.onSurface,
                            ),
                            size: Size.infinite,
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final m in months.reversed)
                  _MonthTile(
                    month: m,
                    prev: l.previousOf(m),
                    ledger: l,
                    target: l.target,
                    onTap: () => _edit(m),
                  ),
              ],
            ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _edit(PwoMonth? existing) async {
    final res = await showModalBottomSheet<PwoMonth>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _MonthEditor(
        existing: existing,
        people: _store.ledger.peopleFor(existing),
        defaultYear: _year ??
            (_store.ledger.years.isNotEmpty
                ? _store.ledger.years.first
                : Jalali.now().year),
        onDelete: existing == null
            ? null
            : () async {
                Navigator.pop(ctx);
                await _guard(context,
                    () => _store.deleteMonth(existing.year, existing.month));
              },
      ),
    );
    if (res == null || _saving) return;
    final clash = _store.ledger.months[res.key];
    if (clash != null && res.key != existing?.key) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(
              '${pwoMonthNames[res.month - 1]} ${res.year} قبلاً ثبت شده. جایگزین شود؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('جایگزین')),
          ],
        ),
      );
      if (ok != true) return;
      // Keep amounts the form did not show (e.g. archived people).
      final shown = _store.ledger.peopleFor(existing).map((p) => p.id).toSet();
      clash.amounts.forEach((k, v) {
        if (!shown.contains(k) && !res.amounts.containsKey(k)) {
          res.amounts[k] = v;
        }
      });
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final ok = await _guard(
        context, () => _store.saveMonth(res, replacing: existing));
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _year = res.year;
    });
  }
}

String _mil(num v) => formatCompactToman(v);

class _Card extends StatelessWidget {
  const _Card({this.title, required this.child});
  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title!,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.year,
    required this.total,
    required this.target,
    required this.met,
    required this.count,
  });
  final int year;
  final double total, target;
  final int met, count;

  @override
  Widget build(BuildContext context) {
    final avg = count == 0 ? 0.0 : total / count;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('جمع برداشت سال $year',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(_mil(total),
              key: const ValueKey('pwo-year-total'),
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('هدف ماهانه: ${_mil(target)} · میانگین: ${_mil(avg)}'),
          Text('رسیده به هدف: $met از $count ماه',
              style: TextStyle(color: met == count ? _good : _bad)),
        ],
      ),
    );
  }
}

class _PersonsCard extends StatelessWidget {
  const _PersonsCard({required this.names, required this.totals});
  final List<String> names;
  final List<double> totals;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'جمع هر نفر',
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        alignment: WrapAlignment.spaceAround,
        children: [
          for (var i = 0; i < names.length; i++)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 80),
              child: Column(
                children: [
                  Text(names[i],
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(_mil(totals[i]), textAlign: TextAlign.center),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.month,
    required this.prev,
    required this.ledger,
    required this.target,
    required this.onTap,
  });
  final PwoMonth month;
  final PwoMonth? prev;
  final PwoLedger ledger;
  final double target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ok = month.meets(target);
    final c = ok ? _good : _bad;
    String? delta;
    Color? dc;
    if (prev != null) {
      final d = month.total - prev!.total;
      final pct = prev!.total > 0 ? d / prev!.total * 100 : null;
      delta = 'نسبت به ماه قبل: ${formatCompactToman(d, showSign: true)}'
          '${pct == null ? '' : ' (${formatPct(pct)})'}';
      dc = d >= 0 ? _good : _bad;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.withValues(alpha: 0.7), width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: c, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        '${pwoMonthNames[month.month - 1]} ${month.year}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Text(_mil(month.total),
                      style: TextStyle(color: c, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              Text([
                for (final p in ledger.peopleFor(month))
                  '${p.name}: ${_mil(month.of(p.id))}'
              ].join('  ·  ')),
              if (delta != null)
                Text(delta, style: TextStyle(color: dc, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PwoChartPainter extends CustomPainter {
  _PwoChartPainter(
      {required this.months, required this.target, required this.textColor});
  final List<PwoMonth> months;
  final double target;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 22.0, top = 8.0;
    final h = size.height - bottom - top;
    final maxV = math.max(
        target * 1.15, months.map((e) => e.total).fold(0.0, math.max) * 1.05);
    if (maxV <= 0) return;
    final n = months.length;
    final slot = size.width / n;
    final barW = math.min(28.0, slot * 0.6);
    for (var i = 0; i < n; i++) {
      final m = months[i];
      // Right-to-left: first month on the right.
      final cx = size.width - slot * (i + 0.5);
      final bh = h * (m.total / maxV);
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - barW / 2, top + h - bh, barW, bh),
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      );
      canvas.drawRRect(
          r, Paint()..color = (m.meets(target) ? _good : _bad).withValues(alpha: 0.85));
      final tp = TextPainter(
        text: TextSpan(
            text: pwoChartLabel(m.month, slot),
            style: TextStyle(color: textColor, fontSize: 10)),
        textDirection: TextDirection.rtl,
      )..layout(maxWidth: slot);
      tp.paint(canvas, Offset(cx - tp.width / 2, size.height - bottom + 4));
    }
    final ty = top + h - h * (target / maxV);
    final dash = Paint()
      ..color = Colors.amber
      ..strokeWidth = 1.6;
    for (double x = 0; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, ty), Offset(math.min(x + 6, size.width), ty), dash);
    }
    final lp = TextPainter(
      text: TextSpan(
          text: 'هدف ${_mil(target)}',
          style: const TextStyle(color: Colors.amber, fontSize: 10)),
      textDirection: TextDirection.rtl,
    )..layout();
    lp.paint(canvas, Offset(2, math.max(0, ty - lp.height - 2)));
  }

  @override
  bool shouldRepaint(covariant _PwoChartPainter old) => true;
}

double? _parseToman(String raw) {
  const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in raw.split('')) {
    final i = fa.indexOf(ch), j = ar.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (j >= 0) {
      b.write(j);
    } else if (ch == '٫' || ch == '/') {
      b.write('.');
    } else if (RegExp(r'[0-9.]').hasMatch(ch)) {
      b.write(ch);
    }
  }
  final s = b.toString();
  if (s.isEmpty) return 0;
  final v = double.tryParse(s);
  if (v == null || !v.isFinite || v < 0) return null;
  return v;
}

String _millionsText(double toman) {
  if (toman == 0) return '';
  // 6 decimals of a million = 1 toman: exact round-trip, no silent rounding.
  var t = (toman / 1000000).toStringAsFixed(6);
  t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return t;
}

class _MonthEditor extends StatefulWidget {
  const _MonthEditor({
    required this.existing,
    required this.people,
    required this.defaultYear,
    this.onDelete,
  });
  final PwoMonth? existing;
  final List<PwoPerson> people;
  final int defaultYear;
  final VoidCallback? onDelete;

  @override
  State<_MonthEditor> createState() => _MonthEditorState();
}

class _MonthEditorState extends State<_MonthEditor> {
  late int _year = widget.existing?.year ?? widget.defaultYear;
  late int _month = widget.existing?.month ?? _nextMonth();
  late final List<TextEditingController> _c = [
    for (final p in widget.people)
      TextEditingController(text: _millionsText(widget.existing?.of(p.id) ?? 0)),
  ];
  String? _error;

  int _nextMonth() => Jalali.now().month;

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final years = [for (var y = _year - 2; y <= _year + 1; y++) y];
    return _SheetFrame(
      footer: Row(
        children: [
          if (widget.onDelete != null)
            Flexible(
              child: TextButton(
                key: const ValueKey('pwo-delete-month'),
                onPressed: widget.onDelete,
                child: const Text('حذف ماه', style: TextStyle(color: _bad)),
              ),
            ),
          const Spacer(),
          FilledButton(
            key: const ValueKey('pwo-save-month'),
            onPressed: _submit,
            child: const Text('ذخیره'),
          ),
        ],
      ),
      children: [
            Text(widget.existing == null ? 'ثبت برداشت ماه' : 'ویرایش ماه',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _month,
                    decoration: const InputDecoration(labelText: 'ماه'),
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(
                            value: m, child: Text(pwoMonthNames[m - 1])),
                    ],
                    onChanged: (v) => setState(() => _month = v ?? _month),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _year,
                    decoration: const InputDecoration(labelText: 'سال'),
                    items: [
                      for (final y in years)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (v) => setState(() => _year = v ?? _year),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < widget.people.length; i++) ...[
              TextField(
                key: ValueKey('pwo-amount-$i'),
                controller: _c[i],
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.۰-۹٠-٩٫]'))
                ],
                decoration: InputDecoration(
                  labelText: 'برداشت ${widget.people[i].name} (میلیون تومان)',
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_error != null)
              Text(_error!, style: const TextStyle(color: _bad)),
      ],
    );
  }

  void _submit() {
    final vals = <String, double>{};
    for (var i = 0; i < _c.length; i++) {
      final v = _parseToman(_c[i].text);
      if (v == null) {
        setState(() => _error = 'مبلغ نامعتبر است.');
        return;
      }
      if (v * 1000000 > pwoMaxToman) {
        setState(() => _error = 'مبلغ بیش از حد بزرگ است.');
        return;
      }
      vals[widget.people[i].id] = (v * 1000000).roundToDouble();
    }
    // Keep amounts of people not shown in this form (never drop data).
    final old = widget.existing;
    if (old != null) {
      old.amounts.forEach((k, v) {
        if (!widget.people.any((p) => p.id == k)) vals[k] = v;
      });
    }
    Navigator.pop(
        context, PwoMonth(year: _year, month: _month, amounts: vals));
  }
}

/// Bottom-sheet frame: scrollable body, pinned footer above keyboard and
/// system nav bar, so action buttons never overlap fields or each other.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.children, required this.footer});
  final List<Widget> children;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (mq.size.height - mq.viewInsets.bottom - mq.padding.top) * 0.95,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: footer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Target + withdrawers editor (also opened from Settings).
Future<void> showPwoSettingsSheet(BuildContext context, PwoStore store) async {
  await ensurePwoReady(context, store);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _PwoSettingsSheet(store: store),
  );
}

class _PwoSettingsSheet extends StatefulWidget {
  const _PwoSettingsSheet({required this.store});
  final PwoStore store;

  @override
  State<_PwoSettingsSheet> createState() => _PwoSettingsSheetState();
}

class _PwoSettingsSheetState extends State<_PwoSettingsSheet> {
  late final TextEditingController _target =
      TextEditingController(text: _millionsText(widget.store.ledger.target));
  final Map<String, TextEditingController> _names = {};
  String? _err;

  TextEditingController _nameCtl(PwoPerson p) =>
      _names.putIfAbsent(p.id, () => TextEditingController(text: p.name));

  @override
  void dispose() {
    _target.dispose();
    for (final c in _names.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _busy = false;

  /// Runs a store call; shows the server's error text in the sheet.
  Future<bool> _try(Future<void> Function() op) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await op();
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _err =
            e.toString().replaceFirst('Invalid argument(s): ', ''));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = await showDialog<String>(
      context: context,
      builder: (c) => const _NameDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    await _try(() => widget.store.addPerson(name));
  }

  Future<void> _remove(PwoPerson p) async {
    final l = widget.store.ledger;
    if (l.activePeople.length <= 1) {
      setState(() => _err = 'حداقل یک برداشت‌کننده لازم است.');
      return;
    }
    final has = l.hasEntries(p.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('حذف «${p.name}»؟'),
          content: Text(has
              ? 'این شخص برداشت ثبت‌شده دارد. سوابقش پاک نمی‌شود و در جمع ماه‌ها و سال باقی می‌ماند؛ فقط بایگانی می‌شود و در ثبت ماه‌های جدید نمی‌آید. بعداً می‌توانید برش گردانید.'
              : 'این شخص برداشتی ندارد و کامل حذف می‌شود.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('انصراف')),
            FilledButton(
                key: const ValueKey('pwo-remove-confirm'),
                style: FilledButton.styleFrom(backgroundColor: _bad),
                onPressed: () => Navigator.pop(c, true),
                child: Text(has ? 'بایگانی' : 'حذف')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _try(() => widget.store.removePerson(p.id));
  }

  Future<void> _save() async {
    final t = _parseToman(_target.text);
    if (t == null || t <= 0) {
      setState(() => _err = 'هدف باید بیشتر از صفر باشد.');
      return;
    }
    if (t * 1000000 > pwoMaxToman) {
      setState(() => _err = 'هدف بیش از حد بزرگ است.');
      return;
    }
    final ok = await _try(() async {
      await widget.store.setTarget((t * 1000000).roundToDouble());
      for (final e in _names.entries) {
        await widget.store.setName(e.key, e.value.text);
      }
    });
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.store.ledger;
    final archived = l.people.where((p) => !p.active).toList();
    return _SheetFrame(
      footer: Row(
        children: [
          Flexible(
            child: TextButton.icon(
              key: const ValueKey('pwo-add-person'),
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('افزودن نفر'),
            ),
          ),
          const Spacer(),
          FilledButton(
            key: const ValueKey('pwo-save-settings'),
            onPressed: _busy ? null : _save,
            child: const Text('ذخیره'),
          ),
        ],
      ),
      children: [
        Text('تنظیمات PWO', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('pwo-target'),
          controller: _target,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'هدف برداشت ماهانه (میلیون تومان)'),
        ),
        const SizedBox(height: 12),
        Text('برداشت‌کننده‌ها', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final p in l.activePeople)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('pwo-name-${p.id}'),
                    controller: _nameCtl(p),
                    decoration: const InputDecoration(labelText: 'نام'),
                  ),
                ),
                IconButton(
                  key: ValueKey('pwo-remove-${p.id}'),
                  tooltip: 'حذف',
                  onPressed: () => _remove(p),
                  icon: const Icon(Icons.remove_circle_outline_rounded,
                      color: _bad),
                ),
              ],
            ),
          ),
        if (archived.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('بایگانی‌شده', style: Theme.of(context).textTheme.bodySmall),
          for (final p in archived)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(p.name),
              trailing: TextButton(
                onPressed: () async {
                  await _try(() => widget.store.restorePerson(p.id));
                },
                child: const Text('بازگردانی'),
              ),
            ),
        ],
        if (_err != null) Text(_err!, style: const TextStyle(color: _bad)),
      ],
    );
  }
}

/// Shortcut card shown at the top of the withdrawals tab.
class PwoEntryCard extends StatelessWidget {
  const PwoEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = PwoStore.instance;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) ensurePwoReady(context, store, refresh: false);
    });
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        String sub = 'برداشت ماهانه M، A، N و هدف ماهانه';
        Color? c;
        if (store.loaded) {
          final l = store.ledger;
          if (l.years.isNotEmpty) {
            final ms = l.monthsOf(l.years.first);
            final last = ms.last;
            c = last.meets(l.target) ? _good : _bad;
            sub = '${pwoMonthNames[last.month - 1]} ${last.year}: '
                '${_mil(last.total)} · هدف ${_mil(l.target)}';
          }
        }
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            key: const ValueKey('pwo-entry'),
            leading: Icon(Icons.stacked_bar_chart_rounded, color: c ?? _good),
            title: const Text('PWO · برداشت ماهانه',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(sub, style: c == null ? null : TextStyle(color: c)),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const PwoPage())),
          ),
        );
      },
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('برداشت‌کننده جدید'),
        content: TextField(
          key: const ValueKey('pwo-new-person'),
          controller: _ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'نام'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف')),
          FilledButton(
              key: const ValueKey('pwo-add-confirm'),
              onPressed: () => Navigator.pop(context, _ctl.text),
              child: const Text('افزودن')),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                key: const ValueKey('pwo-error'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _bad)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
          ],
        ),
      ),
    );
  }
}

/// Month label for the chart: full name when it fits, else a Persian number.
String pwoChartLabel(int month, double slot) {
  if (slot >= 44) return pwoMonthNames[month - 1];
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  return month.toString().split('').map((c) => fa[int.parse(c)]).join();
}

/// Largest accepted amount (toman), same cap as the server.
const pwoMaxToman = 1e15;
