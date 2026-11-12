import 'package:flutter/material.dart';
import 'package:invest/domain/services/ai_accountant_controller.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/ai_audit_detail_sheet.dart';
import 'package:invest/ui/widgets/ai_health_style.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:provider/provider.dart';

/// Dashboard card for the on-device accountant.
class AiAccountantCard extends StatefulWidget {
  const AiAccountantCard({super.key});

  @override
  State<AiAccountantCard> createState() => _AiAccountantCardState();
}

class _AiAccountantCardState extends State<AiAccountantCard> {
  String? _phone;

  @override
  Widget build(BuildContext context) {
    final phone =
        context.select<AppState, String>((state) => state.userPhone ?? '');
    if (_phone != phone) {
      _phone = phone;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _phone != phone) return;
        AiAccountantController.instance.load(context.read<AppState>());
      });
    }
    return ListenableBuilder(
      listenable: AiAccountantController.instance,
      builder: (context, _) => _buildCard(context),
    );
  }

  Future<void> _refresh() {
    return AiAccountantController.instance.load(
      context.read<AppState>(),
      force: true,
    );
  }

  void _open() {
    final controller = AiAccountantController.instance;
    if (controller.report == null && !controller.loading) {
      _refresh();
      return;
    }
    showAiAuditDetailSheet(context);
  }

  Widget _buildCard(BuildContext context) {
    final controller = AiAccountantController.instance;
    final report = controller.report;
    final loading = controller.loading;
    final color =
        report == null ? AppTheme.border : aiHealthColor(report.healthScore);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _open,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: color.withValues(alpha: report == null ? 1 : 0.3)),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 15,
                          color: AppTheme.positive,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'حسابدار هوشمند +V',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.title,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (report != null) ...[
                        Container(
                          key: const Key('ai-card-score'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: color.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            fa('${report.healthScore}/100'),
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        icon: loading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.positive,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                        color: AppTheme.muted,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: loading ? null : _refresh,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (controller.stale)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        'این گزارش برای امروز نیست و در حال به‌روزرسانی است.',
                        key: Key('ai-card-stale'),
                        style: TextStyle(
                          color: aiHealthAmber,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (loading && report == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'در حال بازبینی دفاتر...',
                        style: TextStyle(color: AppTheme.muted, fontSize: 11),
                      ),
                    )
                  else if (controller.error != null && report == null)
                    Text(
                      controller.error!,
                      style: const TextStyle(
                          color: AppTheme.negative, fontSize: 11),
                    )
                  else if (report != null) ...[
                    Text(
                      report.healthTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      fa(report.summary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                    if (report.fallbackReason != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'گزارش محلی نشان داده می‌شود: ${report.fallbackReason}',
                        key: const Key('ai-card-fallback'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: aiHealthAmber, fontSize: 11),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.alerts.isEmpty
                                ? 'تراز بدون مغایرت'
                                : fa('${report.alerts.length} هشدار مالی'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: report.alerts.isEmpty
                                  ? AppTheme.positive
                                  : aiHealthAmber,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Text(
                          'گزارش کامل',
                          style: TextStyle(
                            color: AppTheme.positive,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 10,
                          color: AppTheme.positive,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
