import 'package:flutter/material.dart';
import 'package:invest/domain/models/iran_inflation.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/inflation_detail_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

class IranInflationPane extends StatefulWidget {
  const IranInflationPane({super.key});

  @override
  State<IranInflationPane> createState() => _IranInflationPaneState();
}

class _IranInflationPaneState extends State<IranInflationPane> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshIranInflation(force: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final snap = state.iranInflation;
    final loading = state.iranInflationLoading && snap == null;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => state.refreshIranInflation(force: true),
      child: snap == null
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: shellPagePadding(),
              children: [
                const SizedBox(height: 48),
                const Icon(Icons.trending_up_rounded,
                    size: 40, color: AppTheme.muted),
                const SizedBox(height: 12),
                Text(
                  state.iranInflationError ?? 'داده تورم دریافت نشد',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 12),
                Center(
                  child: OutlinedButton(
                    onPressed: () => state.refreshIranInflation(force: true),
                    child: const Text('تلاش مجدد'),
                  ),
                ),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: shellPagePadding(),
              children: [
                if (state.iranInflationError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      state.iranInflationError!,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                _HeroCard(
                  snap: snap,
                  onTap: () => openInflationDetail(
                    context,
                    snap: snap,
                    kind: InflationMetricKind.pointToPoint,
                  ),
                ),
                const SizedBox(height: 14),
                const _SectionTitle('انواع تورم'),
                const SizedBox(height: 8),
                _TypeCard(
                  title: 'نقطه‌به‌نقطه',
                  subtitle:
                      'تغییر شاخص نسبت به همان ماه سال قبل — نشان‌دهنده فشار قیمتی جاری',
                  value: snap.pointToPointPct,
                  color: const Color(0xFFFF6B6B),
                  icon: Icons.timeline_rounded,
                  onTap: () => openInflationDetail(
                    context,
                    snap: snap,
                    kind: InflationMetricKind.pointToPoint,
                  ),
                ),
                const SizedBox(height: 8),
                _TypeCard(
                  title: 'ماهانه',
                  subtitle:
                      'تغییر شاخص نسبت به ماه قبل — نوسان کوتاه‌مدت سبد مصرف',
                  value: snap.monthlyPct,
                  color: const Color(0xFFFF9500),
                  icon: Icons.calendar_view_month_rounded,
                  onTap: () => openInflationDetail(
                    context,
                    snap: snap,
                    kind: InflationMetricKind.monthly,
                  ),
                ),
                const SizedBox(height: 8),
                _TypeCard(
                  title: 'سالانه (۱۲ماهه)',
                  subtitle:
                      'میانگین شاخص ۱۲ ماه اخیر نسبت به ۱۲ ماه پیش‌تر — معیار رایج گزارش‌ها',
                  value: snap.annualPct,
                  color: const Color(0xFF5B8DEF),
                  icon: Icons.stacked_line_chart_rounded,
                  onTap: () => openInflationDetail(
                    context,
                    snap: snap,
                    kind: InflationMetricKind.annual,
                  ),
                ),
                const SizedBox(height: 8),
                _CpiCard(
                  snap: snap,
                  onTap: () => openInflationDetail(
                    context,
                    snap: snap,
                    kind: InflationMetricKind.cpi,
                  ),
                ),
                const SizedBox(height: 16),
                const _SectionTitle('روند ۱۲ ماه اخیر (نقطه‌به‌نقطه)'),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => openInflationDetail(
                    context,
                    snap: snap,
                    kind: InflationMetricKind.pointToPoint,
                  ),
                  child: _HistoryBars(points: snap.history),
                ),
                const SizedBox(height: 14),
                Text(
                  'منبع: ${snap.sourceLabel}\n'
                  'دوره: ${snap.periodLabel} · گردآوری دادهٔ باز Farmaanaa',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: AppTheme.muted.withValues(alpha: 0.85),
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: AppTheme.title,
        fontWeight: FontWeight.w800,
        fontSize: 14,
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.snap, this.onTap});
  final IranInflationSnapshot snap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF3D1A1A), Color(0xFF241212)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Row(
                children: [
                  Icon(Icons.chevron_left_rounded,
                      color: Color(0xFFFFC9C9), size: 20),
                  Spacer(),
                  Text(
                    'تورم نقطه‌به‌نقطه ایران',
                    style: TextStyle(
                      color: Color(0xFFFFC9C9),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                formatPct(snap.pointToPointPct),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'آخرین گزارش: ${snap.periodLabel} · برای جزئیات و نمودار بزنید',
                style: const TextStyle(color: Color(0xFFD7B0B0), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final double value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.chevron_left_rounded,
                  color: AppTheme.muted, size: 20),
              const SizedBox(width: 4),
              Text(
                formatPct(value),
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppTheme.title,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CpiCard extends StatelessWidget {
  const _CpiCard({required this.snap, this.onTap});
  final IranInflationSnapshot snap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.chevron_left_rounded,
                  color: AppTheme.muted, size: 20),
              const SizedBox(width: 4),
              Text(
                formatNumber(snap.cpiIndex, decimals: 1),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: AppTheme.positive,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'شاخص قیمت مصرف‌کننده (CPI)',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: AppTheme.title,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'سطح قیمت سبد مصرف نسبت به سال پایه ۱۴۰۰ (=۱۰۰)',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.positive.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.speed_rounded,
                    color: AppTheme.positive, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryBars extends StatelessWidget {
  const _HistoryBars({required this.points});
  final List<IranInflationPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Text('—', textAlign: TextAlign.center);
    }
    final maxV = points
        .map((e) => e.pointToPointPct)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final scale = maxV <= 0 ? 1.0 : maxV;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final p in points)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        p.pointToPointPct.toStringAsFixed(0),
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 9,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 90,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            height: (90 *
                                    (p.pointToPointPct / scale)
                                        .clamp(0.08, 1.0))
                                .toDouble(),
                            decoration: BoxDecoration(
                              color: AppTheme.negative.withValues(alpha: 0.75),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.shortLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
