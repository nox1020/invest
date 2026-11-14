import 'package:flutter/material.dart';
import 'package:invest/domain/services/ai_accountant_controller.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/ai_audit_detail_sheet.dart';
import 'package:provider/provider.dart';

/// Embedded AI Accountant pane inside the Market Index page.
class AiAccountantPane extends StatefulWidget {
  const AiAccountantPane({super.key, this.controller});

  final AiAccountantController? controller;

  @override
  State<AiAccountantPane> createState() => _AiAccountantPaneState();
}

class _AiAccountantPaneState extends State<AiAccountantPane> {
  AiAccountantController get _controller =>
      widget.controller ?? AiAccountantController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.load(context.read<AppState>());
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final report = _controller.report;
        if (report == null) {
          return RefreshIndicator(
            onRefresh: () => _controller.load(state, force: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: shellPagePadding(),
              children: [
                const SizedBox(height: 48),
                if (_controller.loading) ...[
                  const Center(
                    child: CircularProgressIndicator(color: AppTheme.positive),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'در حال بازبینی دفاتر و حساب‌های مالی...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted, fontSize: 12.5),
                  ),
                ] else ...[
                  const Icon(
                    Icons.auto_awesome_outlined,
                    size: 40,
                    color: AppTheme.muted,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _controller.error ?? 'گزارش حسابدار هنوز ساخته نشده است.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _controller.error != null
                          ? AppTheme.negative
                          : AppTheme.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: OutlinedButton.icon(
                      key: const ValueKey('ai-pane-retry'),
                      onPressed: () => _controller.load(state, force: true),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('حسابرسی مجدد'),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return AiAuditDetailSheet(
          key: const ValueKey('ai-accountant-inline'),
          report: report,
          inline: true,
          stale: _controller.stale,
          refreshing: _controller.loading,
          canRephrase: _controller.geminiReady,
          onRefresh: () => _controller.load(state, force: true),
          onAlert: (alert) => openAuditTarget(context, alert),
          onRephrase: (text) => _controller.service.rephrase(state, text),
        );
      },
    );
  }
}
