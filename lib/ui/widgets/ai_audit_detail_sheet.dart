import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invest/domain/models/ai_audit_report.dart';
import 'package:invest/domain/services/ai_accountant_service.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:provider/provider.dart';

/// پنجره مودال نمایش جزئیات گزارش روزانه حسابدار هوشمند
void showAiAuditDetailSheet(
  BuildContext context, {
  required AiAuditReport report,
  required VoidCallback onRefresh,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AiAuditDetailSheetContent(
      report: report,
      onRefresh: onRefresh,
    ),
  );
}

class _AiAuditDetailSheetContent extends StatefulWidget {
  const _AiAuditDetailSheetContent({
    required this.report,
    required this.onRefresh,
  });

  final AiAuditReport report;
  final VoidCallback onRefresh;

  @override
  State<_AiAuditDetailSheetContent> createState() =>
      _AiAuditDetailSheetContentState();
}

class _AiAuditDetailSheetContentState
    extends State<_AiAuditDetailSheetContent> {
  late AiAuditReport _report;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppTheme.positive;
    if (score >= 60) return const Color(0xFFFFB340);
    return AppTheme.negative;
  }

  void _copyReportToClipboard() {
    final buffer = StringBuffer();
    buffer.writeln('📋 گزارش حسابرسی هوشمند +V');
    buffer.writeln('تاریخ بازبینی: ${fa(_report.auditedAtIso.split('T').first)}');
    buffer.writeln('شاخص سلامت حساب‌ها: ${fa('${_report.healthScore}')} از ۱۰۰ (${_report.healthTitle})');
    buffer.writeln('');
    buffer.writeln('🔹 خلاصه ارزیابی حسابدار:');
    buffer.writeln(_report.summary);
    buffer.writeln('');
    if (_report.alerts.isNotEmpty) {
      buffer.writeln('⚠️ هشدارها و مغایرت‌ها:');
      for (final a in _report.alerts) {
        buffer.writeln('• [${a.category}] ${a.title}: ${a.detail}');
      }
      buffer.writeln('');
    }
    if (_report.recommendations.isNotEmpty) {
      buffer.writeln('💡 توصیه‌های حسابرسی:');
      for (var i = 0; i < _report.recommendations.length; i++) {
        buffer.writeln('${fa('${i + 1}')}. ${_report.recommendations[i]}');
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('متن گزارش حسابدار در کلیپ‌بورد کپی شد.'),
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    setState(() => _refreshing = true);
    try {
      final state = Provider.of<AppState>(context, listen: false);
      final newReport = await AiAccountantService.instance.auditAccounts(
        state: state,
        force: true,
      );
      if (mounted) {
        setState(() {
          _report = newReport;
          _refreshing = false;
        });
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _refreshing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در به‌روزرسانی گزارش: $e')),
        );
      }
    }
  }

  void _showApiKeyDialog() async {
    final currentKey = await AiAccountantService.instance.getSavedApiKey();
    final controller = TextEditingController(text: currentKey);

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppTheme.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.border),
          ),
          title: const Row(
            children: [
              Icon(Icons.key_rounded, color: AppTheme.positive, size: 20),
              SizedBox(width: 8),
              Text(
                'تنظیم کلید Gemini API',
                style: TextStyle(
                  color: AppTheme.title,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'برای حسابرسی عمیق آنلاین با هوش مصنوعی جمنای گوگل، کلید API خود را وارد کنید (در صورت خالی بودن، از موتور تحلیل خبره محلی استفاده می‌شود):',
                style: TextStyle(color: AppTheme.text, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: AppTheme.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'AIzaSy...',
                  hintStyle: const TextStyle(color: AppTheme.muted),
                  filled: true,
                  fillColor: AppTheme.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: const Text('انصراف', style: TextStyle(color: AppTheme.muted)),
            ),
            ElevatedButton(
              onPressed: () async {
                await AiAccountantService.instance.saveApiKey(controller.text);
                if (!dCtx.mounted) return;
                Navigator.of(dCtx).pop();
                _handleRefresh();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('ذخیره و بازبینی مجدد'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scoreColor = _scoreColor(_report.healthScore);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView(
            controller: scrollController,
            children: [
              // نوار عنوان
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.accent),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppTheme.positive,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'گزارش روزانه حسابدار هوشمند',
                          style: TextStyle(
                            color: AppTheme.title,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'بازبینی دفاتر و اسناد مالی · ${fa(_report.auditedAtIso.split('T').first)}',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.key_rounded, size: 20),
                    tooltip: 'تنظیم کلید هوش مصنوعی',
                    color: AppTheme.muted,
                    onPressed: _showApiKeyDialog,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    tooltip: 'کپی متن گزارش',
                    color: AppTheme.muted,
                    onPressed: _copyReportToClipboard,
                  ),
                  IconButton(
                    icon: _refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.positive,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded, size: 22),
                    tooltip: 'حسابرسی مجدد',
                    color: AppTheme.text,
                    onPressed: _refreshing ? null : _handleRefresh,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // بنر شاخص سلامت حساب‌ها
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scoreColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: scoreColor, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        fa('${_report.healthScore}'),
                        style: TextStyle(
                          color: scoreColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _report.healthTitle,
                            style: TextStyle(
                              color: scoreColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _report.isAiGenerated
                                ? 'تحلیل شده با هوش مصنوعی Google Gemini'
                                : 'محاسبه شده با موتور جامع قواعد حسابداری محلی',
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // کارت‌های کلیدی آمار مالی بازبینی شده
              Row(
                children: [
                  Expanded(
                    child: _buildMetricMiniCard(
                      'چک‌های پرداختی',
                      fa(formatMoney(_report.pendingChecksPayableToman)),
                      'تومان در انتظار تسویه',
                      _report.pendingChecksPayableToman > 0
                          ? const Color(0xFFFFB340)
                          : AppTheme.muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricMiniCard(
                      'چک‌های دریافتی',
                      fa(formatMoney(_report.pendingChecksReceivableToman)),
                      'تومان در انتظار وصول',
                      AppTheme.positive,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // متن خلاصه اجرایی حسابدار
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.notes_rounded,
                            size: 16, color: AppTheme.positive),
                        SizedBox(width: 6),
                        Text(
                          'ارزیابی و یادداشت تحلیلی حسابدار',
                          style: TextStyle(
                            color: AppTheme.title,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fa(_report.summary),
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // لیست هشدارها و مغایرت‌ها
              if (_report.alerts.isNotEmpty) ...[
                const Text(
                  'هشدارها و مغایرت‌های نیازمند اقدام',
                  style: TextStyle(
                    color: AppTheme.title,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                for (final a in _report.alerts) _buildAlertTile(a),
                const SizedBox(height: 16),
              ],

              // لیست توصیه‌های راهبردی
              if (_report.recommendations.isNotEmpty) ...[
                const Text(
                  'توصیه‌های راهبردی برای انضباط مالی',
                  style: TextStyle(
                    color: AppTheme.title,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < _report.recommendations.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fa('${i + 1}. '),
                                style: const TextStyle(
                                  color: AppTheme.positive,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  fa(_report.recommendations[i]),
                                  style: const TextStyle(
                                    color: AppTheme.text,
                                    fontSize: 12.5,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricMiniCard(
    String title,
    String value,
    String subtitle,
    Color accentColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: accentColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: AppTheme.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertTile(AiAuditAlert alert) {
    Color bg;
    Color border;
    Color iconColor;
    IconData icon;

    switch (alert.severity) {
      case 'high':
        bg = AppTheme.negative.withValues(alpha: 0.1);
        border = AppTheme.negative.withValues(alpha: 0.4);
        iconColor = AppTheme.negative;
        icon = Icons.error_rounded;
        break;
      case 'medium':
        bg = const Color(0xFFFFB340).withValues(alpha: 0.1);
        border = const Color(0xFFFFB340).withValues(alpha: 0.4);
        iconColor = const Color(0xFFFFB340);
        icon = Icons.warning_rounded;
        break;
      default:
        bg = AppTheme.bg;
        border = AppTheme.border;
        iconColor = AppTheme.muted;
        icon = Icons.info_outline_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        fa(alert.title),
                        style: const TextStyle(
                          color: AppTheme.title,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '[${alert.category}]',
                      style: TextStyle(color: iconColor, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  fa(alert.detail),
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
