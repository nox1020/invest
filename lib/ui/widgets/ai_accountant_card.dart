import 'package:flutter/material.dart';
import 'package:invest/domain/models/ai_audit_report.dart';
import 'package:invest/domain/services/ai_accountant_service.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/ai_audit_detail_sheet.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:provider/provider.dart';

/// کارت حسابدار هوشمند در داشبورد برای بازبینی حساب‌ها و گزارش روزانه
class AiAccountantCard extends StatefulWidget {
  const AiAccountantCard({super.key});

  @override
  State<AiAccountantCard> createState() => _AiAccountantCardState();
}

class _AiAccountantCardState extends State<AiAccountantCard> {
  AiAuditReport? _report;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitialReport();
  }

  Future<void> _loadInitialReport() async {
    // ابتدا کش را بررسی می‌کنیم
    final cached = await AiAccountantService.instance.getLastCachedReport();
    if (mounted && cached != null) {
      setState(() => _report = cached);
      return;
    }

    // در غیر این صورت حسابرسی انجام می‌دهیم
    _performAudit(force: false);
  }

  Future<void> _performAudit({bool force = true}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final state = Provider.of<AppState>(context, listen: false);
      final report = await AiAccountantService.instance.auditAccounts(
        state: state,
        force: force,
      );
      if (mounted) {
        setState(() {
          _report = report;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Color _scoreColor(int score) {
    if (score >= 80) return AppTheme.positive;
    if (score >= 60) return const Color(0xFFFFB340);
    return AppTheme.negative;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (_report != null) {
              showAiAuditDetailSheet(
                context,
                report: _report!,
                onRefresh: () => _performAudit(force: true),
              );
            } else {
              _performAudit(force: true);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _report != null
                    ? _scoreColor(_report!.healthScore).withValues(alpha: 0.3)
                    : AppTheme.border,
              ),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ردیف هدر کارت
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
                      if (_report != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _scoreColor(_report!.healthScore)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _scoreColor(_report!.healthScore)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            fa('${_report!.healthScore}/۱۰۰'),
                            style: TextStyle(
                              color: _scoreColor(_report!.healthScore),
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        icon: _loading
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
                        onPressed: _loading ? null : () => _performAudit(force: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // محتوای خلاصه یا وضعیت لودینگ
                  if (_loading && _report == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.positive,
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'در حال بازبینی دفاتر...',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: AppTheme.muted, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_error != null && _report == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'خطا در بارگذاری: $_error',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.negative,
                          fontSize: 11,
                        ),
                      ),
                    )
                  else if (_report != null) ...[
                    // عنوان وضعیت
                    Text(
                      _report!.healthTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _scoreColor(_report!.healthScore),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // متن خلاصه کوتاه شده
                    Text(
                      fa(_report!.summary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // نوار پایینی دکمه و تعداد هشدارها
                    Row(
                      children: [
                        Expanded(
                          child: _report!.alerts.isNotEmpty
                              ? Row(
                                  children: [
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      size: 13,
                                      color: Color(0xFFFFB340),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        fa('${_report!.alerts.length} هشدار مالی'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFFFB340),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : const Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 13,
                                      color: AppTheme.positive,
                                    ),
                                    SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'تراز بدون مغایرت',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppTheme.positive,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(width: 8),
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'گزارش کامل',
                              style: TextStyle(
                                color: AppTheme.positive,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 10,
                              color: AppTheme.positive,
                            ),
                          ],
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
