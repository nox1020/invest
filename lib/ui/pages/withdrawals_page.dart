import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invest/domain/models/app_settings.dart';
import 'package:invest/domain/models/withdrawal.dart';
import 'package:invest/domain/services/withdrawal_allowance.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/app_date_picker.dart';
import 'package:invest/ui/widgets/tg_percent_wheel.dart';
import 'package:invest/ui/widgets/user_error.dart';
import 'package:provider/provider.dart';

/// Economist desk for withdrawal policy, capacity, and ledger history.
class WithdrawalsPage extends StatefulWidget {
  const WithdrawalsPage({super.key});

  @override
  State<WithdrawalsPage> createState() => _WithdrawalsPageState();
}

class _WithdrawalsPageState extends State<WithdrawalsPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));
    _enter.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.withdrawals;
    final allowance = state.withdrawalAllowance;

    return RefreshIndicator(
      onRefresh: () => state.refreshAll(),
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: shellPagePadding(extraForFab: state.canMutate),
            children: [
              _StatusRibbon(
                offline: state.offline,
                count: history.length,
                yearLabel: WithdrawalAllowance.yearCaption(
                  allowance.yearKey,
                  allowance.calendar,
                ),
              ),
              const SizedBox(height: 12),
              _CapacityHero(
                allowance: allowance,
                canEdit: state.canMutate,
                onEditAnnualPct: () => _editAnnualWithdrawalPct(context, state),
              ),
              const SizedBox(height: 20),
              const _SectionLabel(
                eyebrow: 'سیاست',
                title: 'سقف برداشت سالانه',
              ),
              const SizedBox(height: 10),
              _PolicyCard(
                annualPct: state.settings.annualWithdrawalPct,
                canEdit: state.canMutate,
                onEdit: () => _editAnnualWithdrawalPct(context, state),
              ),
              const SizedBox(height: 20),
              const _SectionLabel(
                eyebrow: 'تراز',
                title: 'سود و برداشت',
              ),
              const SizedBox(height: 10),
              _BalanceLedger(allowance: allowance),
              const SizedBox(height: 10),
              _CoveragePanel(allowance: allowance),
              const SizedBox(height: 10),
              _AnnualQuotaPanel(allowance: allowance),
              const SizedBox(height: 22),
              _SectionLabel(
                eyebrow: 'دفتر',
                title: 'سابقه برداشت',
                trailing: Text(
                  '${history.length} ردیف',
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (history.isEmpty)
                const _EmptyHistory()
              else
                for (var i = 0; i < history.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _WithdrawalTile(
                    item: history[i],
                    canEdit: state.canMutate,
                    rank: i + 1,
                  ),
                ],
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _editAnnualWithdrawalPct(
  BuildContext context,
  AppState state,
) async {
  if (!state.canMutate) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('در حالت آفلاین ذخیره ممکن نیست')),
    );
    return;
  }
  // Fire-and-forget: awaiting platform haptics can hang under widget tests.
  HapticFeedback.selectionClick();
  final picked = await showTgPercentWheel(
    context: context,
    title: 'سود سالانه قابل برداشت',
    subtitle: 'چرخ را بچرخانید · ۱ تا ۱۰۰ درصد از ورودی',
    selected: state.settings.annualWithdrawalPct,
  );
  if (picked == null || !context.mounted) return;
  if (picked == state.settings.annualWithdrawalPct) return;
  try {
    await state.saveSettings(
      state.settings.copyWith(annualWithdrawalPct: picked),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'سقف ${AppSettings.annualWithdrawalLabel(picked)} روی سرور ذخیره شد',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) showUserError(context, e);
  }
}

class _StatusRibbon extends StatelessWidget {
  const _StatusRibbon({
    required this.offline,
    required this.count,
    required this.yearLabel,
  });

  final bool offline;
  final int count;
  final String yearLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          offline ? Icons.cloud_off_outlined : Icons.account_balance_outlined,
          size: 14,
          color: offline ? AppTheme.negative : AppTheme.muted,
        ),
        const SizedBox(width: 6),
        Text(
          offline ? 'آفلاین' : 'میز نقدینگی',
          style: TextStyle(
            color: offline ? AppTheme.negative : AppTheme.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Text(
          '$yearLabel · $count برداشت',
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.eyebrow,
    required this.title,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (trailing != null) ...[
          trailing!,
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                eyebrow,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: AppTheme.muted.withValues(alpha: 0.9),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppTheme.title,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CapacityHero extends StatelessWidget {
  const _CapacityHero({
    required this.allowance,
    required this.canEdit,
    required this.onEditAnnualPct,
  });

  final WithdrawalAllowance allowance;
  final bool canEdit;
  final VoidCallback onEditAnnualPct;

  @override
  Widget build(BuildContext context) {
    final available = allowance.available;
    final yearLabel =
        WithdrawalAllowance.yearCaption(allowance.yearKey, allowance.calendar);
    final pctLabel = AppSettings.annualWithdrawalLabel(allowance.annualPct);
    final capped = allowance.remainingAnnual <= 1e-6 && allowance.annualCap > 0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xFF1C3F30),
            Color(0xFF13251C),
            Color(0xFF101C16),
          ],
          stops: [0, 0.55, 1],
        ),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.bg.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  yearLabel,
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'ظرفیت قابل برداشت',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: AppTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            formatMoney(available),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: available > 0 ? AppTheme.positive : AppTheme.title,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'سقف سیاستی $pctLabel',
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: allowance.usedAnnualFraction,
              minHeight: 6,
              backgroundColor: AppTheme.border,
              color: capped ? AppTheme.negative : AppTheme.positive,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            allowance.annualCap <= 0
                ? 'سقف سالانه صفر است؛ ورودی پرتفو ثبت نشده'
                : 'مصرف امسال ${formatMoney(allowance.yearWithdrawn)} از ${formatMoney(allowance.annualCap)}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: canEdit ? onEditAnnualPct : null,
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('تنظیم درصد سالانه'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({
    required this.annualPct,
    required this.canEdit,
    required this.onEdit,
  });

  final int annualPct;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: canEdit
            ? () {
                HapticFeedback.selectionClick();
                onEdit();
              }
            : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: canEdit ? AppTheme.muted : AppTheme.border,
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  AppSettings.annualWithdrawalShortLabel(annualPct),
                  style: const TextStyle(
                    color: AppTheme.positive,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'سود سالانه قابل برداشت',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: AppTheme.title,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'چرخ ۱ تا ۱۰۰٪ با ویبره · ذخیره روی سرور',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: AppTheme.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceLedger extends StatelessWidget {
  const _BalanceLedger({required this.allowance});
  final WithdrawalAllowance allowance;

  @override
  Widget build(BuildContext context) {
    final excess = allowance.excessOverRealized;
    final profitTone =
        allowance.realizedPnl < 0 ? AppTheme.negative : AppTheme.positive;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _LedgerRow(
            label: 'سود تحقق‌یافته',
            value: formatMoney(allowance.realizedPnl),
            caption: 'سود بسته‌شده معاملات',
            tone: profitTone,
            showDivider: true,
          ),
          _LedgerRow(
            label: 'اضافه برداشت',
            value: formatMoney(excess),
            caption: excess > 0
                ? 'فراتر از سود تحقق‌یافته'
                : 'داخل محدوده سود تحقق‌یافته',
            tone: excess > 0 ? AppTheme.negative : AppTheme.muted,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.label,
    required this.value,
    required this.caption,
    required this.tone,
    required this.showDivider,
  });

  final String label;
  final String value;
  final String caption;
  final Color tone;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: AppTheme.border))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: tone,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.title,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoveragePanel extends StatelessWidget {
  const _CoveragePanel({required this.allowance});
  final WithdrawalAllowance allowance;

  @override
  Widget build(BuildContext context) {
    final profit = allowance.realizedPnl > 0 ? allowance.realizedPnl : 0.0;
    final taken = allowance.withdrawnAllTime;
    final excess = allowance.excessOverRealized;
    final scale = profit > taken ? profit : taken;
    final within = taken - excess;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'پوشش برداشت نسبت به سود',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          _CoverageBar(
            within: scale <= 1e-9 ? 0 : within / scale,
            excess: scale <= 1e-9 ? 0 : excess / scale,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _LegendDot(
                color: AppTheme.positive,
                label: 'داخل سود ${formatMoney(within < 0 ? 0 : within)}',
              ),
              const SizedBox(width: 12),
              _LegendDot(
                color: AppTheme.negative,
                label: 'اضافه ${formatMoney(excess)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoverageBar extends StatelessWidget {
  const _CoverageBar({required this.within, required this.excess});
  final double within;
  final double excess;

  @override
  Widget build(BuildContext context) {
    var green = within <= 0 ? 0 : (within * 1000).round();
    var red = excess <= 0 ? 0 : (excess * 1000).round();
    final used = green + red;
    if (used > 1000) {
      green = (green * 1000 / used).round();
      red = 1000 - green;
    }
    final rest = 1000 - green - red;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 7,
        child: Row(
          children: [
            if (green > 0)
              Expanded(
                flex: green,
                child: const ColoredBox(color: AppTheme.positive),
              ),
            if (red > 0)
              Expanded(
                flex: red,
                child: const ColoredBox(color: AppTheme.negative),
              ),
            if (rest > 0)
              Expanded(
                flex: rest,
                child: const ColoredBox(color: AppTheme.border),
              ),
            if (green == 0 && red == 0 && rest <= 0)
              const Expanded(child: ColoredBox(color: AppTheme.border)),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.muted, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnualQuotaPanel extends StatelessWidget {
  const _AnnualQuotaPanel({required this.allowance});
  final WithdrawalAllowance allowance;

  @override
  Widget build(BuildContext context) {
    final pct = AppSettings.annualWithdrawalShortLabel(allowance.annualPct);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'کوتای سالانه ($pct)',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuietStat(
                  label: 'کل ورودی پرتفو',
                  value: formatMoney(allowance.inflows),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuietStat(
                  label: 'سقف سالانه',
                  value: formatMoney(allowance.annualCap),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _QuietStat(
                  label: 'برداشت امسال',
                  value: formatMoney(allowance.yearWithdrawn),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuietStat(
                  label: 'باقیمانده سقف',
                  value: formatMoney(allowance.remainingAnnual),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuietStat extends StatelessWidget {
  const _QuietStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            textAlign: TextAlign.right,
            style: const TextStyle(color: AppTheme.muted, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.menu_book_outlined, color: AppTheme.muted, size: 28),
          SizedBox(height: 8),
          Text(
            'دفتر برداشت هنوز خالی است',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'اولین برداشت به‌عنوان ردیف دفتر ثبت می‌شود.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

Future<void> showRecordWithdrawalDialog(
  BuildContext context, {
  Withdrawal? existing,
}) async {
  final state = context.read<AppState>();
  if (!state.canMutate) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'در حالت آفلاین فقط مشاهده ممکن است. برای ذخیره آنلاین شوید.',
        ),
      ),
    );
    return;
  }
  final draft = existing;
  if (draft != null && draft.id == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('این برداشت قابل ویرایش نیست.')),
    );
    return;
  }
  final editing = draft != null;
  final allowance = state.withdrawalAllowance;
  final available = allowance.available;
  final amountCtrl = TextEditingController(
    text: draft == null ? '' : _amountFieldText(draft.amount),
  );
  final noteCtrl = TextEditingController(text: draft?.note ?? '');
  var createdAt = todayIso();
  if (draft != null && draft.createdAt.trim().isNotEmpty) {
    createdAt = tryNormalizeToIso(draft.createdAt) ?? todayIso();
  }
  final pctLabel = AppSettings.annualWithdrawalLabel(allowance.annualPct);
  final calendar = state.settings.calendar;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(editing ? 'ویرایش برداشت' : 'ثبت برداشت'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'قابل برداشت: ${formatMoney(available)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: available > 0 ? AppTheme.positive : AppTheme.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'سقف امسال $pctLabel · باقیمانده سقف ${formatMoney(allowance.remainingAnnual)}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                'سود تحقق‌یافته: ${formatMoney(allowance.realizedPnl)}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'اضافه برداشت: ${formatMoney(allowance.excessOverRealized)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: allowance.excessOverRealized > 0
                      ? AppTheme.negative
                      : AppTheme.muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'مبلغ می‌تواند بیشتر از قابل برداشت باشد.',
                textAlign: TextAlign.right,
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.right,
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'توضیح (اختیاری)'),
                textAlign: TextAlign.right,
              ),
              if (editing)
                AppDateTile(
                  label: 'تاریخ برداشت',
                  isoDate: createdAt,
                  calendar: calendar,
                  onChanged: (v) => setLocal(() => createdAt = v),
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
            child: Text(editing ? 'ذخیره' : 'ثبت'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) {
    amountCtrl.dispose();
    noteCtrl.dispose();
    return;
  }
  final parsed = parseFlexibleNumber(amountCtrl.text);
  final note = noteCtrl.text.trim();
  amountCtrl.dispose();
  noteCtrl.dispose();
  if (parsed == null || parsed <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('مبلغ برداشت نامعتبر است')),
    );
    return;
  }
  try {
    if (draft != null) {
      await state.updateWithdrawal(
        item: draft,
        amount: parsed,
        note: note,
        createdAt: createdAt,
      );
    } else {
      await state.recordWithdrawal(
        amount: parsed,
        note: note,
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(editing ? 'برداشت ویرایش شد' : 'برداشت ثبت شد'),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) showUserError(context, e);
  }
}

String _amountFieldText(double amount) {
  if ((amount - amount.roundToDouble()).abs() < 1e-9) {
    return amount.round().toString();
  }
  var text = amount.toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text;
}

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile({
    required this.item,
    required this.canEdit,
    required this.rank,
  });

  final Withdrawal item;
  final bool canEdit;
  final int rank;

  Color get _statusColor => switch (item.status) {
        'rejected' => AppTheme.negative,
        'pending' => const Color(0xFFFFCC00),
        _ => AppTheme.positive,
      };

  @override
  Widget build(BuildContext context) {
    final calendar = context.read<AppState>().settings.calendar;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              color: _statusColor,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          '#$rank',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          formatMoney(item.amount),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: AppTheme.title,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        if (canEdit)
                          IconButton(
                            tooltip: 'ویرایش',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => showRecordWithdrawalDialog(
                              context,
                              existing: item,
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatDisplayDate(item.createdAt, calendar),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.statusLabel,
                            style: TextStyle(
                              color: _statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (item.note.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.note,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
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
