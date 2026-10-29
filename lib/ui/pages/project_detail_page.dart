import 'package:flutter/material.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/ui/theme/app_theme.dart';

/// Opens one project independently of the list's filters and scroll position.
/// Its ID is resolved against the live store on every rebuild, so edits,
/// archives, restores and offline queued changes are reflected immediately.
class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({
    super.key,
    required this.store,
    required this.projectId,
    this.onEdit,
  });

  final ProjectsStore store;
  final int projectId;
  final Future<void> Function(BuildContext context, Project project)? onEdit;

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  Project? _currentProject() {
    for (final project in widget.store.snap.items) {
      if (project.id == widget.projectId) return project;
    }
    return null;
  }

  Future<void> _edit(Project project) async {
    final edit = widget.onEdit;
    if (edit == null || widget.store.readOnly) return;
    await edit(context, project);
    if (!mounted) return;
    // A deleted project must not leave a stale, editable detail screen.
    if (_currentProject() == null) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final project = _currentProject();
          final canEdit = project != null &&
              !widget.store.readOnly &&
              widget.onEdit != null;
          return Scaffold(
            appBar: AppBar(
              title: const Text('جزئیات پروژه'),
              actions: [
                if (widget.store.isRemote)
                  IconButton(
                    key: const ValueKey('proj-detail-refresh'),
                    tooltip: 'به‌روزرسانی',
                    onPressed: widget.store.syncing
                        ? null
                        : () => widget.store.refresh(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
            bottomNavigationBar: canEdit
                ? SafeArea(
                    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton.icon(
                      key: const ValueKey('proj-detail-edit'),
                      onPressed: () => _edit(project!),
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      label: const Text('ویرایش و مدیریت پروژه'),
                    ),
                  )
                : null,
            body: project == null
                ? _MissingProject(onBack: () => Navigator.of(context).maybePop())
                : RefreshIndicator(
                    onRefresh: widget.store.refresh,
                    child: ListView(
                      key: ValueKey('proj-detail-list-${project.id}'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      children: [
                        _ProjectIdentity(project: project),
                        const SizedBox(height: 12),
                        _ProjectFinance(project: project),
                        const SizedBox(height: 12),
                        _ProjectInformation(project: project),
                        const SizedBox(height: 12),
                        _ProjectStatusNote(project: project),
                        if (project.note.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _ProjectNotes(note: project.note),
                        ],
                        if (widget.store.readOnly || project.raw['pending_sync'] == true) ...[
                          const SizedBox(height: 12),
                          Text(
                            project.raw['pending_sync'] == true
                                ? 'تغییرات این پروژه در صف همگام‌سازی قرار دارد.'
                                : 'اطلاعات در حالت فقط‌خواندنی نمایش داده می‌شود.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}

Color _projectTone(ProjectStatus status) => switch (status) {
      ProjectStatus.finished => AppTheme.positive,
      ProjectStatus.active => const Color(0xFFE0C46A),
      ProjectStatus.pipeline => AppTheme.muted,
    };

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _ProjectIdentity extends StatelessWidget {
  const _ProjectIdentity({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('proj-detail-identity'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF23543F), Color(0xFF172B21)],
          ),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.engineering_outlined, color: AppTheme.positive, size: 19),
            const SizedBox(width: 7),
            Text('پروژه شماره ${formatNumber(project.id)}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Text(project.title.isEmpty ? 'پروژه بدون عنوان' : project.title,
              key: const ValueKey('proj-detail-title'),
              style: const TextStyle(
                  color: AppTheme.title, fontWeight: FontWeight.w800,
                  fontSize: 22, height: 1.4)),
          if (project.workType.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(project.workType,
                style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _StatusPill(projectStatusLabel(project.status), _projectTone(project.status)),
            if (project.archived)
              const _StatusPill('بایگانی‌شده', AppTheme.muted,
                  key: ValueKey('proj-detail-archived')),
            if (project.raw['pending_sync'] == true)
              const _StatusPill('در صف همگام‌سازی', Color(0xFFE0C46A)),
          ]),
        ]),
      );
}

class _ProjectFinance extends StatelessWidget {
  const _ProjectFinance({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    final profit = project.profit;
    final tone = profit == null
        ? AppTheme.muted
        : profit < 0
            ? AppTheme.negative
            : project.status == ProjectStatus.active
                ? const Color(0xFFE0C46A)
                : AppTheme.positive;
    final label = profit == null
        ? 'سود / زیان'
        : profit < 0
            ? 'زیان پروژه'
            : project.status == ProjectStatus.finished
                ? 'سود تحقق‌یافته'
                : 'سود پیش‌بینی‌شده';
    final ratio = project.contract > 0 ? project.cost / project.contract : null;
    return Card(
      key: const ValueKey('proj-detail-finance'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              profit == null ? 'هنوز محاسبه نشده' : formatMoney(profit.abs()),
              key: const ValueKey('proj-detail-profit'),
              style: TextStyle(
                  color: tone, fontSize: 27, fontWeight: FontWeight.w800),
            ),
          ),
          if (project.profitPct != null) ...[
            const SizedBox(height: 5),
            Text(
              '${formatNumber(project.profitPct!, decimals: 1)}٪ از مبلغ قرارداد',
              key: const ValueKey('proj-detail-margin'),
              textDirection: TextDirection.rtl,
              style: TextStyle(color: tone, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
          const Divider(height: 26, color: AppTheme.border),
          _DetailLine('مبلغ قرارداد', formatMoney(project.contract),
              key: const ValueKey('proj-detail-contract')),
          const SizedBox(height: 12),
          _DetailLine('هزینه ثبت‌شده', formatMoney(project.cost),
              key: const ValueKey('proj-detail-cost')),
          if (ratio != null) ...[
            const SizedBox(height: 18),
            _DetailLine('نسبت هزینه به قرارداد',
                '${formatNumber(ratio * 100, decimals: 1)}٪',
                valueColor: ratio > 1 ? AppTheme.negative : AppTheme.muted),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: LinearProgressIndicator(
                key: const ValueKey('proj-detail-cost-ratio'),
                value: ratio.clamp(0.0, 1.0).toDouble(),
                minHeight: 7,
                backgroundColor: AppTheme.bg,
                color: ratio > 1 ? AppTheme.negative : AppTheme.positive,
              ),
            ),
            const SizedBox(height: 5),
            const Text('این نوار سهم هزینه از مبلغ قرارداد است، نه درصد پیشرفت فیزیکی.',
                style: TextStyle(color: AppTheme.muted, fontSize: 10.5)),
          ],
        ]),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(color: valueColor ?? AppTheme.title,
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      );
}

class _ProjectInformation extends StatelessWidget {
  const _ProjectInformation({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('proj-detail-information'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.event_note_outlined, color: AppTheme.positive, size: 20),
              SizedBox(width: 8),
              Text('زمان‌بندی و مشخصات',
                  style: TextStyle(color: AppTheme.title,
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ]),
            const Divider(height: 26, color: AppTheme.border),
            _DetailLine('تاریخ شروع',
                project.startDate.isEmpty ? 'ثبت نشده' : project.startDate,
                key: const ValueKey('proj-detail-start')),
            const SizedBox(height: 12),
            _DetailLine('تاریخ پایان',
                project.endDate.isEmpty ? 'ثبت نشده' : project.endDate,
                key: const ValueKey('proj-detail-end')),
            if (project.days != null) ...[
              const SizedBox(height: 12),
              _DetailLine('مدت پروژه', '${formatNumber(project.days!)} روز'),
            ],
            if (project.monthKey != null) ...[
              const SizedBox(height: 12),
              _DetailLine('دوره مالی', project.monthKey!),
            ],
          ]),
        ),
      );
}

class _ProjectStatusNote extends StatelessWidget {
  const _ProjectStatusNote({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    final message = project.archived
        ? 'این پروژه بایگانی شده و در جمع سود و زیان و داشبورد محاسبه نمی‌شود.'
        : switch (project.status) {
            ProjectStatus.pipeline =>
              'این پروژه در صف قرار دارد؛ مبالغ آن در سود تحقق‌یافته محاسبه نمی‌شود.',
            ProjectStatus.active =>
              'سود این پروژه پیش‌بینی است و تا زمان اتمام، تحقق‌یافته محسوب نمی‌شود.',
            ProjectStatus.finished =>
              'سود این پروژه تحقق‌یافته است و در گزارش سود و زیان لحاظ می‌شود.',
          };
    return Container(
      key: const ValueKey('proj-detail-status-note'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: 18,
            color: _projectTone(project.status)),
        const SizedBox(width: 10),
        Expanded(child: Text(message,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.6))),
      ]),
    );
  }
}

class _ProjectNotes extends StatelessWidget {
  const _ProjectNotes({required this.note});
  final String note;

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('proj-detail-notes'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.notes_rounded, color: AppTheme.positive, size: 20),
              SizedBox(width: 8),
              Text('یادداشت‌ها', style: TextStyle(
                  color: AppTheme.title, fontSize: 15, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 12),
            SelectableText(note,
                style: const TextStyle(color: AppTheme.text, fontSize: 13, height: 1.65)),
          ]),
        ),
      );
}

class _MissingProject extends StatelessWidget {
  const _MissingProject({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.folder_off_outlined, size: 42, color: AppTheme.muted),
            const SizedBox(height: 12),
            const Text('این پروژه دیگر در فهرست موجود نیست.',
                key: ValueKey('proj-detail-missing'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.title)),
            const SizedBox(height: 10),
            TextButton(onPressed: onBack, child: const Text('بازگشت به پروژه‌ها')),
          ]),
        ),
      );
}
