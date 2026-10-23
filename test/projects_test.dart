import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invest/data/projects_store.dart';
import 'package:invest/domain/services/backup_payload.dart';
import 'package:invest/ui/pages/projects_page.dart';
import 'package:invest/ui/theme/app_theme.dart';

Map<String, dynamic> row(int id, String title, String status,
        {double c = 0, double cost = 0, String start = '', String end = '', bool archived = false}) =>
    {
      'id': id,
      'title': title,
      'work_type': 'کار',
      'start_date': start,
      'end_date': end,
      'contract_amount': c,
      'cost': cost,
      'profit': c > 0 ? c - cost : null,
      'profit_pct': c > 0 ? (c - cost) / c * 100 : null,
      'status': status,
      'archived': archived,
    };

ProjectsSnapshot sample() => ProjectsSnapshot({
      'items': [
        row(1, 'الف', 'finished', c: 85, cost: 39, start: '1404/01/01', end: '1404/01/30'),
        row(2, 'ب', 'finished', c: 199, cost: 219, start: '1404/09/30', end: '1405/04/10'),
        row(3, 'ج', 'active', c: 100, cost: 40, start: '1405/07/01'),
        row(4, 'د', 'pipeline'),
        row(5, 'ه', 'finished', c: 50, cost: 10, start: '1404/02/01', end: '1404/03/01', archived: true),
      ],
    });

void main() {
  test('totals: finished is realized, active is expected, archived left out', () {
    final t = sample().totals;
    expect(t.realized, 46 - 20);
    expect(t.expected, 60);
    expect(t.sheetProfit, 86);
    expect(t.finishedCount, 2);
    expect(t.activeCount, 1);
    expect(t.pipelineCount, 1);
    expect(t.contract, 85 + 199 + 100);
    expect(sample().archivedCount, 1);
  });

  test('filters by status, archive, year and month', () {
    final items = sample().items;
    ids(Iterable<Project> l) => l.map((p) => p.id).toList();
    expect(ids(filterProjects(items, ProjectFilter.all)), [3, 2, 1, 4]);
    expect(ids(filterProjects(items, ProjectFilter.finished)), [2, 1]);
    expect(ids(filterProjects(items, ProjectFilter.pipeline)), [4]);
    expect(ids(filterProjects(items, ProjectFilter.archived)), [5]);
    // finished rows belong to their end month, others to the start month
    expect(ids(filterProjects(items, ProjectFilter.all, year: 1404)), [1]);
    expect(ids(filterProjects(items, ProjectFilter.all, year: 1405)), [3, 2]);
    expect(ids(filterProjects(items, ProjectFilter.all, year: 1405, month: '1405/04')), [2]);
  });

  test('preview uses the sheet formulas and sheet JSON parses', () {
    final p = projectPreview(85000000, 39025000);
    expect(p.profit, 45975000);
    expect(p.pct!.round(), 54);
    expect(projectPreview(0, 10).profit, isNull);
    expect(parseProjectsSheet('{"projects":[{"description":"x"}]}').single['description'], 'x');
    expect(parseProjectsSheet('[{"title":"y"}]').single['title'], 'y');
    expect(() => parseProjectsSheet('{"trades":[]}'), throwsFormatException);
    expect(() => parseProjectsSheet('nope'), throwsFormatException);
  });

  test('backup payload keeps projects', () {
    final json = {
      'format': backupFormatId,
      'format_version': backupFormatVersion,
      'exported_at': '2026-10-23',
      'settings': <String, dynamic>{},
      'assets': [],
      'trades': [],
      'withdrawals': [],
      'projects': {
        'projects': [
          {'title': 'الف', 'contract_amount': 10}
        ]
      },
    };
    final p = BackupPayload.fromJson(json);
    expect(p.projects!['projects'], hasLength(1));
    expect(p.toJson()['projects'], isNotNull);
    expect((p.toJson()['meta'] as Map)['includes'], contains('projects'));
  });

  testWidgets('projects page lists, filters and explains totals', (tester) async {
    final store = ProjectsStore.instance..debugSet(sample());
    addTearDown(store.debugReset);
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: ProjectsPage(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('پروژه‌ها / پیمانکاری'), findsOneWidget);
    expect(find.byKey(const ValueKey('proj-tile-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('proj-tile-5')), findsNothing);
    expect(find.text('سود پیش‌بینی در جریان'), findsOneWidget);
    expect(find.text('26 تومان'), findsWidgets);

    await tester.ensureVisible(find.byKey(const ValueKey('proj-f-archived')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('proj-f-archived')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('proj-tile-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('proj-archived-tag')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('proj-f-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('proj-f-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('proj-y-1404')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('proj-tile-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('proj-tile-2')), findsNothing);
    expect(find.byKey(const ValueKey('proj-m-1404/01')), findsOneWidget);
  });

  testWidgets('project dialog validates and previews profit', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => showDialog(context: c, builder: (_) => const ProjectDialog()),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('proj-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('proj-f-error')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('proj-f-title')), 'الف');
    await tester.enterText(find.byKey(const ValueKey('proj-f-contract')), '85,000,000');
    await tester.enterText(find.byKey(const ValueKey('proj-f-cost')), '39025000');
    await tester.pumpAndSettle();
    expect(find.textContaining('54.1٪'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('proj-f-start')), '1405/02/01');
    await tester.enterText(find.byKey(const ValueKey('proj-f-end')), '1405/01/01');
    await tester.tap(find.byKey(const ValueKey('proj-save')));
    await tester.pumpAndSettle();
    expect(find.text('تاریخ پایان نمی‌تواند قبل از تاریخ شروع باشد.'), findsOneWidget);
  });
}
