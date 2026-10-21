import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'package:invest/data/pwo_store.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';

const _good = AppTheme.positive;
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

  @override
  void initState() {
    super.initState();
    _store.load();
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(null),
          icon: const Icon(Icons.add_rounded),
          label: const Text('ثبت ماه'),
        ),
        body: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            if (!_store.loaded) {
              return const Center(child: CircularProgressIndicator());
            }
            final l = _store.ledger;
            final years = l.years;
            final year = (_year != null && years.contains(_year))
                ? _year!
                : (years.isNotEmpty ? years.first : Jalali.now().year);
            final months = l.monthsOf(year);
            final persons = l.personTotals(year);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
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
                _PersonsCard(names: l.names, totals: persons),
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
                    names: l.names,
                    target: l.target,
                    onTap: () => _edit(m),
                  ),
              ],
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
      builder: (ctx) => _MonthEditor(
        existing: existing,
        names: _store.ledger.names,
        defaultYear: _year ??
            (_store.ledger.years.isNotEmpty
                ? _store.ledger.years.first
                : Jalali.now().year),
        onDelete: existing == null
            ? null
            : () async {
                Navigator.pop(ctx);
                await _store.deleteMonth(existing.year, existing.month);
              },
      ),
    );
    if (res == null) return;
    if (existing == null && _store.ledger.months.containsKey(res.key)) {
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
    }
    if (existing != null && existing.key != res.key) {
      await _store.deleteMonth(existing.year, existing.month);
    }
    await _store.saveMonth(res);
    setState(() => _year = res.year);
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
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
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
    required this.names,
    required this.target,
    required this.onTap,
  });
  final PwoMonth month;
  final PwoMonth? prev;
  final List<String> names;
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
                for (var i = 0; i < 3; i++)
                  '${names[i]}: ${_mil(month.amounts[i])}'
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
            text: pwoMonthNames[m.month - 1],
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
  final m = toman / 1000000;
  return m == m.roundToDouble() ? m.toStringAsFixed(0) : '${double.parse(m.toStringAsFixed(4))}';
}

class _MonthEditor extends StatefulWidget {
  const _MonthEditor({
    required this.existing,
    required this.names,
    required this.defaultYear,
    this.onDelete,
  });
  final PwoMonth? existing;
  final List<String> names;
  final int defaultYear;
  final VoidCallback? onDelete;

  @override
  State<_MonthEditor> createState() => _MonthEditorState();
}

class _MonthEditorState extends State<_MonthEditor> {
  late int _year = widget.existing?.year ?? widget.defaultYear;
  late int _month = widget.existing?.month ?? _nextMonth();
  late final List<TextEditingController> _c = [
    for (var i = 0; i < 3; i++)
      TextEditingController(
          text: _millionsText(widget.existing?.amounts[i] ?? 0)),
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'ثبت برداشت ماه' : 'ویرایش ماه',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
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
            for (var i = 0; i < 3; i++) ...[
              TextField(
                key: ValueKey('pwo-amount-$i'),
                controller: _c[i],
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.۰-۹٠-٩٫]'))
                ],
                decoration: InputDecoration(
                  labelText: 'برداشت ${widget.names[i]} (میلیون تومان)',
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_error != null)
              Text(_error!, style: const TextStyle(color: _bad)),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.onDelete != null)
                  TextButton(
                    onPressed: widget.onDelete,
                    child: const Text('حذف ماه', style: TextStyle(color: _bad)),
                  ),
                const Spacer(),
                FilledButton(onPressed: _submit, child: const Text('ذخیره')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final vals = <double>[];
    for (final c in _c) {
      final v = _parseToman(c.text);
      if (v == null) {
        setState(() => _error = 'مبلغ نامعتبر است.');
        return;
      }
      vals.add((v * 1000000).roundToDouble());
    }
    Navigator.pop(
        context, PwoMonth(year: _year, month: _month, amounts: vals));
  }
}

/// Target + names editor (also opened from Settings).
Future<void> showPwoSettingsSheet(BuildContext context, PwoStore store) async {
  await store.load();
  if (!context.mounted) return;
  final l = store.ledger;
  final target = TextEditingController(text: _millionsText(l.target));
  final names = [for (final n in l.names) TextEditingController(text: n)];
  String? err;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('تنظیمات PWO', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('pwo-target'),
                controller: target,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'هدف برداشت ماهانه (میلیون تومان)'),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < 3; i++) ...[
                TextField(
                  controller: names[i],
                  decoration:
                      InputDecoration(labelText: 'نام برداشت‌کننده ${i + 1}'),
                ),
                const SizedBox(height: 8),
              ],
              if (err != null) Text(err!, style: const TextStyle(color: _bad)),
              FilledButton(
                onPressed: () async {
                  final t = _parseToman(target.text);
                  if (t == null || t <= 0) {
                    setS(() => err = 'هدف باید بیشتر از صفر باشد.');
                    return;
                  }
                  await store.setTarget((t * 1000000).roundToDouble());
                  for (var i = 0; i < 3; i++) {
                    await store.setName(i, names[i].text);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('ذخیره'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Shortcut card shown at the top of the withdrawals tab.
class PwoEntryCard extends StatelessWidget {
  const PwoEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = PwoStore.instance;
    store.load();
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
