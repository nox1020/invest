import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invest/domain/models/ai_audit_report.dart';
import 'package:invest/domain/services/ai_accountant_controller.dart';
import 'package:invest/domain/services/ai_accountant_engine.dart';
import 'package:invest/domain/services/ai_accountant_service.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/checks_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/ai_health_style.dart';
import 'package:invest/ui/widgets/bank_sms_ui.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:provider/provider.dart';

void showAiAuditDetailSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return ListenableBuilder(
        listenable: AiAccountantController.instance,
        builder: (context, _) {
          final controller = AiAccountantController.instance;
          final report = controller.report;
          if (report == null) {
            return const SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  'در حال آماده‌سازی گزارش...',
                  style: TextStyle(color: AppTheme.muted),
                ),
              ),
            );
          }
          return AiAuditDetailSheet(
            report: report,
            stale: controller.stale,
            refreshing: controller.loading,
            canRephrase: controller.geminiReady,
            onRefresh: () {
              final state = Provider.of<AppState>(context, listen: false);
              return controller.load(state, force: true);
            },
            onAlert: (alert) {
              Navigator.of(sheetContext).pop();
              openAuditTarget(context, alert);
            },
            onRephrase: (text) {
              final state = Provider.of<AppState>(context, listen: false);
              return controller.service.rephrase(state, text);
            },
          );
        },
      );
    },
  );
}

void openAuditTarget(BuildContext context, AiAuditAlert alert) {
  if (auditTargetOpensSms(alert.target)) {
    openBankSmsPage(context);
    return;
  }
  final filter = filterForAuditTarget(alert.target);
  if (filter != null) openChecksPage(context, filter: filter);
}

class AiAuditDetailSheet extends StatefulWidget {
  const AiAuditDetailSheet({
    super.key,
    required this.report,
    this.stale = false,
    this.refreshing = false,
    this.canRephrase = false,
    this.onRefresh,
    this.onAlert,
    this.onRephrase,
  });

  final AiAuditReport report;
  final bool stale;
  final bool refreshing;
  final bool canRephrase;
  final Future<void> Function()? onRefresh;
  final void Function(AiAuditAlert alert)? onAlert;
  final Future<String?> Function(String redacted)? onRephrase;

  @override
  State<AiAuditDetailSheet> createState() => _AiAuditDetailSheetState();
}

class _AiAuditDetailSheetState extends State<AiAuditDetailSheet> {
  final _question = TextEditingController();
  AiQaAnswer? _answer;
  bool _rephrasing = false;
  String? _rephrased;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    setState(() {
      _answer = answerAccountantQuestion(text, widget.report.snapshot);
      _rephrased = null;
    });
  }

  Future<void> _rephrase() async {
    final answer = _answer;
    final rephrase = widget.onRephrase;
    if (answer == null || !answer.understood || rephrase == null) return;
    setState(() => _rephrasing = true);
    final text = await rephrase(answer.redacted);
    if (!mounted) return;
    setState(() {
      _rephrasing = false;
      _rephrased = text;
    });
  }

  void _copy() {
    final report = widget.report;
    final buffer = StringBuffer()
      ..writeln('گزارش حسابدار هوشمند +V')
      ..writeln('زمان بازبینی: ${report.auditedAtLabel}')
      ..writeln('شاخص: ${report.healthScore} از ۱۰۰')
      ..writeln(report.summary);
    for (final alert in report.alerts) {
      buffer.writeln('• ${alert.title}: ${alert.detail}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('متن گزارش در کلیپ‌بورد کپی شد.')),
    );
  }

  Future<void> _access() async {
    final service = AiAccountantService.instance;
    final state = Provider.of<AppState>(context, listen: false);
    final account = state.userPhone ?? '';
    final key = await service.readApiKey();
    final consent = await service.hasConsent(account);
    if (!mounted) return;
    final controller = TextEditingController(text: key);
    var allowed = consent;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: AppTheme.card,
                title: const Text(
                  'حسابرسی آنلاین',
                  style: TextStyle(color: AppTheme.title, fontSize: 16),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        geminiConsentExplainer,
                        style: TextStyle(
                            color: AppTheme.text, fontSize: 13, height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: allowed,
                        title: const Text(
                          'ارسال جمع‌های بی‌نام به جمنای',
                          style: TextStyle(color: AppTheme.title, fontSize: 13),
                        ),
                        onChanged: (value) => setLocal(() => allowed = value),
                      ),
                      TextField(
                        controller: controller,
                        textDirection: TextDirection.ltr,
                        obscureText: true,
                        style:
                            const TextStyle(color: AppTheme.text, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'کلید Gemini',
                          hintStyle: TextStyle(color: AppTheme.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('انصراف'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      await service.saveApiKey(controller.text);
                      await service.setConsent(account, allowed);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                    child: const Text('ذخیره'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final color = aiHealthColor(report.healthScore);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: DraggableScrollableSheet(
          key: const Key('ai-audit-sheet'),
          initialChildSize: 0.88,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'گزارش حسابدار هوشمند',
                        style: TextStyle(
                          color: AppTheme.title,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'رضایت و کلید',
                      onPressed: _access,
                      icon: const Icon(Icons.key_rounded,
                          size: 20, color: AppTheme.muted),
                    ),
                    IconButton(
                      tooltip: 'کپی',
                      onPressed: _copy,
                      icon: const Icon(Icons.copy_rounded,
                          size: 20, color: AppTheme.muted),
                    ),
                    IconButton(
                      tooltip: 'حسابرسی مجدد',
                      onPressed: widget.refreshing ? null : widget.onRefresh,
                      icon: widget.refreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded,
                              size: 22, color: AppTheme.text),
                    ),
                  ],
                ),
                Text(
                  report.auditedAtLabel,
                  key: const Key('ai-audit-stamp'),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (widget.stale)
                  const _Banner(
                    key: Key('ai-stale-banner'),
                    text:
                        'این نسخه مربوط به امروز نیست. به‌روزرسانی را بزنید تا گزارش امروز ساخته شود.',
                  ),
                if (report.fallbackReason != null)
                  _Banner(
                    key: const Key('ai-fallback-banner'),
                    text:
                        'پاسخ جمنای نرسید و گزارش قواعد دستگاه نشان داده می‌شود. ${report.fallbackReason}',
                  ),
                _ScoreBanner(report: report, color: color),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Metric('چک پرداختی', report.pendingChecksPayableToman,
                        'مانده باز'),
                    _Metric('چک دریافتی', report.pendingChecksReceivableToman,
                        'مانده باز'),
                    _Metric('ودیعه پرداختی', report.pendingDepositsPayableToman,
                        'جدا از چک'),
                    _Metric('ودیعه دریافتی',
                        report.pendingDepositsReceivableToman, 'جدا از چک'),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'پیش‌بینی جریان',
                  key: Key('ai-forecast'),
                  style: TextStyle(
                    color: AppTheme.title,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                for (final bucket in report.snapshot.buckets)
                  _ForecastTile(bucket: bucket),
                if (report.snapshot.cashWarning != null) ...[
                  const SizedBox(height: 8),
                  _Banner(
                    key: const Key('ai-cash-warning'),
                    text: report.snapshot.cashWarning!,
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'خلاصه این ماه',
                  key: Key('ai-monthly'),
                  style: TextStyle(
                    color: AppTheme.title,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _MonthlyBlock(summary: report.snapshot.monthly),
                const SizedBox(height: 16),
                Text(
                  fa(report.summary),
                  style: const TextStyle(
                      color: AppTheme.text, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 16),
                if (report.alerts.isNotEmpty) ...[
                  const Text(
                    'هشدارها',
                    style: TextStyle(
                      color: AppTheme.title,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final alert in report.alerts)
                    _AlertTile(
                      alert: alert,
                      onTap: alert.actionable && widget.onAlert != null
                          ? () => widget.onAlert!(alert)
                          : null,
                    ),
                  const SizedBox(height: 8),
                ],
                for (var i = 0; i < report.recommendations.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      fa('${i + 1}. ${report.recommendations[i]}'),
                      style: const TextStyle(
                          color: AppTheme.text, fontSize: 12.5, height: 1.45),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'پرسش از دفاتر',
                  style: TextStyle(
                    color: AppTheme.title,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'پاسخ از اعداد روی دستگاه است. جمنای فقط اگر خودتان بازنویسی را بخواهید و رضایت داده باشید، همان جمع‌ها را روان‌تر می‌کند.',
                  style: TextStyle(
                      color: AppTheme.muted, fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('ai-qa-field'),
                  controller: _question,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(color: AppTheme.text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'مثلاً تا ۷ روز آینده چقدر باید بپردازم؟',
                    hintStyle:
                        const TextStyle(color: AppTheme.muted, fontSize: 12),
                    filled: true,
                    fillColor: AppTheme.bg,
                    suffixIcon: IconButton(
                      tooltip: 'بپرس',
                      onPressed: () => _ask(_question.text),
                      icon: const Icon(Icons.send_rounded,
                          color: AppTheme.positive),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: _ask,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final suggestion in aiQaSuggestions)
                      ActionChip(
                        label: Text(
                          suggestion,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.text),
                        ),
                        onPressed: () {
                          _question.text = suggestion;
                          _ask(suggestion);
                        },
                      ),
                  ],
                ),
                if (_answer != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    key: const Key('ai-qa-answer'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      fa(_rephrased ?? _answer!.text),
                      style: const TextStyle(
                          color: AppTheme.text, fontSize: 12.5, height: 1.5),
                    ),
                  ),
                  if (widget.canRephrase && _answer!.understood)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _rephrasing ? null : _rephrase,
                        child: Text(_rephrasing
                            ? 'در حال بازنویسی...'
                            : 'بازنویسی با جمنای'),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ScoreBanner extends StatelessWidget {
  const _ScoreBanner({required this.report, required this.color});

  final AiAuditReport report;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            fa('${report.healthScore}'),
            key: const Key('ai-health-score'),
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.healthTitle,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  report.isAiGenerated
                      ? 'متن جمنای روی جمع‌های بی‌نام؛ اعداد از دستگاه است.'
                      : 'محاسبه با قواعد روی دستگاه',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.title, this.amount, this.subtitle);

  final String title;
  final double amount;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              fa(formatMoneyLabel(amount)),
              style: const TextStyle(
                color: AppTheme.title,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(subtitle,
                style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _ForecastTile extends StatelessWidget {
  const _ForecastTile({required this.bucket});

  final CashflowBucket bucket;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            bucket.label,
            style: const TextStyle(
              color: AppTheme.title,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'پرداختی چک ${fa(formatMoneyLabel(bucket.payableCheques))} · دریافتی چک ${fa(formatMoneyLabel(bucket.receivableCheques))}',
            style: const TextStyle(
                color: AppTheme.text, fontSize: 11, height: 1.4),
          ),
          Text(
            'پرداختی ودیعه ${fa(formatMoneyLabel(bucket.payableDeposits))} · دریافتی ودیعه ${fa(formatMoneyLabel(bucket.receivableDeposits))}',
            style: const TextStyle(
                color: AppTheme.text, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MonthlyBlock extends StatelessWidget {
  const _MonthlyBlock({required this.summary});

  final AiMonthlySummary summary;

  @override
  Widget build(BuildContext context) {
    final pwo = summary.pwoLoaded
        ? 'PWO ${fa(summary.label)}: ${fa(formatMoneyLabel(summary.pwoTotal))} از هدف ${fa(formatMoneyLabel(summary.pwoTarget))}'
        : 'دفتر PWO هنوز بارگذاری نشده است.';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(pwo,
              style: const TextStyle(
                  color: AppTheme.text, fontSize: 12, height: 1.4)),
          Text(
            'برداشت تکمیل‌شده: ${fa(formatMoneyLabel(summary.withdrawalsTotal))}',
            style: const TextStyle(
                color: AppTheme.text, fontSize: 12, height: 1.4),
          ),
          Text(
            'سود باز (${fa('${summary.openPricedTrades}')} معامله با قیمت): ${fa(formatMoneyLabel(summary.openUnrealizedPnl))}',
            style: const TextStyle(
                color: AppTheme.text, fontSize: 12, height: 1.4),
          ),
          if (summary.openUnpricedTrades > 0)
            Text(
              fa('${summary.openUnpricedTrades} معاملهٔ باز قیمت روز ندارد و در سود باز نیست.'),
              style: const TextStyle(
                  color: AppTheme.muted, fontSize: 11, height: 1.4),
            ),
          Text(
            'سود تحقق‌یافتهٔ ماه: ${fa(formatMoneyLabel(summary.monthRealizedPnl))} · کل: ${fa(formatMoneyLabel(summary.totalRealizedPnl))}',
            style: const TextStyle(
                color: AppTheme.text, fontSize: 12, height: 1.4),
          ),
          if (summary.doubleCountHits > 0)
            Text(
              fa('${summary.doubleCountHits} مورد احتمال هم‌پوشانی برداشت و PWO در این ماه.'),
              style: const TextStyle(
                  color: aiHealthAmber, fontSize: 12, height: 1.4),
            ),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, this.onTap});

  final AiAuditAlert alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (alert.severity) {
      'high' => AppTheme.negative,
      'medium' => aiHealthAmber,
      _ => AppTheme.muted,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: Key(
              'ai-alert-${alert.target.isEmpty ? alert.title : alert.target}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  fa(alert.title),
                  style: const TextStyle(
                    color: AppTheme.title,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  fa(alert.detail),
                  style: const TextStyle(
                      color: AppTheme.text, fontSize: 11.5, height: 1.4),
                ),
                if (onTap != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'برای دیدن فهرست بزنید',
                      style: TextStyle(color: AppTheme.positive, fontSize: 11),
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

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: aiHealthAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: aiHealthAmber.withValues(alpha: 0.4)),
      ),
      child: Text(
        fa(text),
        style:
            const TextStyle(color: AppTheme.text, fontSize: 12, height: 1.45),
      ),
    );
  }
}

/// Toman label even when the app display currency is dollar.
String formatMoneyLabel(num value) {
  return formatMoney(value, forceToman: true);
}
