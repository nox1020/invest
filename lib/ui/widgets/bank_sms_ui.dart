import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/data/pwo_store.dart';
import 'package:invest/data/write_queue.dart';
import 'package:invest/domain/services/bank_sms_parser.dart';
import 'package:invest/domain/services/pwo_ledger.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/pages/pwo_page.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/dashboard_kit.dart';
import 'package:provider/provider.dart';

enum BankSmsTarget { personal, system }

String _when(DateTime d) {
  final j = BankSmsItem(fp: '', bank: '', toman: 0, at: d).jalali;
  String two(int v) => v.toString().padLeft(2, '0');
  return fa(
      '${j.year}/${two(j.month)}/${two(j.day)} · ${two(d.hour)}:${two(d.minute)}');
}

/// Same SMS amount already recorded nearby (manual entry) → warn.
String? bankSmsDuplicateHint(
    BankSmsItem it, BankSmsTarget target, AppState? app, PwoStore pwo) {
  if (target == BankSmsTarget.personal) {
    final j = it.jalali;
    final txs =
        pwo.ledger.months[pwoMonthKey(j.year, j.month)]?.txs ?? const <PwoTx>[];
    if (txs.any((t) => (t.amount - it.toman).abs() < 1)) {
      return 'برداشتی با همین مبلغ در این ماه ثبت شده؛ احتمالاً تکراری است.';
    }
    return null;
  }
  for (final w in app?.withdrawals ?? const []) {
    if ((w.amount - it.toman).abs() >= 1) continue;
    final iso = tryNormalizeToIso(w.createdAt);
    if (iso == null) {
      return 'برداشتی با همین مبلغ قبلاً ثبت شده؛ احتمالاً تکراری است.';
    }
    final d = parseIsoDate(iso);
    if (d.difference(it.at).inHours.abs() <= 36) {
      return 'برداشتی با همین مبلغ در همین روزها ثبت شده؛ احتمالاً تکراری است.';
    }
  }
  return null;
}

/// Prefilled one-tap confirm. Returns true when recorded.
Future<bool> showBankSmsConfirm(BuildContext context, BankSmsItem it) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppTheme.card,
    builder: (_) => Directionality(
        textDirection: TextDirection.rtl, child: BankSmsConfirmSheet(item: it)),
  );
  return r == true;
}

class BankSmsConfirmSheet extends StatefulWidget {
  const BankSmsConfirmSheet({super.key, required this.item, this.pwo});
  final BankSmsItem item;
  final PwoStore? pwo;

  @override
  State<BankSmsConfirmSheet> createState() => _BankSmsConfirmSheetState();
}

class _BankSmsConfirmSheetState extends State<BankSmsConfirmSheet> {
  late final PwoStore _pwo = widget.pwo ?? PwoStore.instance;
  var _target = BankSmsTarget.personal;
  String? _person;
  late final _amount =
      TextEditingController(text: widget.item.toman.toStringAsFixed(0));
  late final _note = TextEditingController(text: widget.item.note);
  bool _busy = false;
  String? _error;

  AppState? get _app {
    try {
      return Provider.of<AppState>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await ensurePwoReady(context, _pwo, refresh: false);
      } catch (_) {}
      if (mounted) setState(_pickPerson);
    });
    _pickPerson();
  }

  void _pickPerson() {
    final people = _pwo.ledger.activePeople;
    if (_person != null && people.any((p) => p.id == _person)) return;
    final card = widget.item.card;
    final mapped = card == null ? null : BankSmsStore.instance.cardPerson[card];
    _person = (mapped != null && people.any((p) => p.id == mapped))
        ? mapped
        : (people.isNotEmpty ? people.first.id : null);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _reject() async {
    await BankSmsStore.instance.markHandled(widget.item.fp);
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _save() async {
    if (_busy) return;
    final v =
        double.tryParse(normalizeSmsText(_amount.text).replaceAll(',', ''));
    if (v == null || v <= 0) {
      setState(() => _error = 'مبلغ نامعتبر است.');
      return;
    }
    final it = widget.item;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_target == BankSmsTarget.personal) {
        if (_person == null) {
          throw ArgumentError(
              'اول در صفحهٔ PWO برداشت‌کننده‌ها را تعریف کنید.');
        }
        final j = it.jalali;
        try {
          await _pwo.addTx(j.year, j.month, _person!, v.roundToDouble(),
              note: _note.text.trim(), idempotencyKey: it.idempotencyKey);
        } on WriteQueuedException {
          // Queued with the same key: will be sent once when online.
        }
        if (it.card != null) {
          await BankSmsStore.instance.setCardPerson(it.card!, _person);
        }
      } else {
        final app = _app;
        if (app == null || !app.canMutate) {
          throw StateError('در حالت آفلاین ثبت برداشت سیستم ممکن نیست.');
        }
        await app.recordWithdrawal(
            amount: v.roundToDouble(),
            note: _note.text.trim(),
            createdAt: toIsoDate(it.at));
      }
      await BankSmsStore.instance.markHandled(it.fp);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('برداشت ثبت شد')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e
              .toString()
              .replaceFirst('Invalid argument(s): ', '')
              .replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final people = _pwo.ledger.activePeople;
    final dup = bankSmsDuplicateHint(it, _target, _app, _pwo);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          key: const ValueKey('sms-confirm'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.sms_rounded, color: AppTheme.negative),
              const SizedBox(width: 8),
              Expanded(
                child: Text('ثبت برداشت از پیامک بانک',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ]),
            const SizedBox(height: 4),
            Text('${it.bank} · ${_when(it.at)}', style: mutedStyle(12)),
            const SizedBox(height: 8),
            Text(
              '−${formatMoney(it.toman)}',
              key: const ValueKey('sms-amount-label'),
              style: const TextStyle(
                  color: AppTheme.negative,
                  fontSize: 22,
                  fontWeight: FontWeight.w800),
            ),
            if (it.balanceToman != null)
              Text('مانده: ${formatMoney(it.balanceToman!)}',
                  style: mutedStyle(12)),
            if (it.lowConfidence)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('مبلغ با اطمینان کم خوانده شد؛ بررسی کنید.',
                    style: TextStyle(color: Colors.orange, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            SegmentedButton<BankSmsTarget>(
              key: const ValueKey('sms-target'),
              segments: const [
                ButtonSegment(
                    value: BankSmsTarget.personal,
                    label: Text('شخصی'),
                    icon: Icon(Icons.person_rounded)),
                ButtonSegment(
                    value: BankSmsTarget.system,
                    label: Text('سیستم'),
                    icon: Icon(Icons.account_balance_rounded)),
              ],
              selected: {_target},
              onSelectionChanged: (s) => setState(() => _target = s.first),
            ),
            const SizedBox(height: 8),
            if (_target == BankSmsTarget.personal)
              DropdownButtonFormField<String>(
                key: const ValueKey('sms-person'),
                isExpanded: true,
                initialValue: _person,
                decoration: InputDecoration(
                    labelText:
                        'برداشت‌کننده · ${pwoMonthNames[it.jalali.month - 1]} ${fa('${it.jalali.year}')}'),
                items: [
                  for (final p in people)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(() => _person = v),
              ),
            TextField(
              key: const ValueKey('sms-amount'),
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹٠-٩,]'))
              ],
              decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
            ),
            TextField(
              key: const ValueKey('sms-note'),
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'توضیح'),
            ),
            if (dup != null)
              Container(
                key: const ValueKey('sms-dup'),
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(dup, style: const TextStyle(fontSize: 12))),
                ]),
              ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppTheme.negative)),
            const SizedBox(height: 8),
            Row(children: [
              TextButton(
                key: const ValueKey('sms-reject'),
                onPressed: _busy ? null : _reject,
                child: const Text('رد'),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const ValueKey('sms-save'),
                style:
                    FilledButton.styleFrom(backgroundColor: AppTheme.negative),
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('ثبت'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Dashboard card «برداشت‌های بانکی جدید».
class BankSmsCard extends StatelessWidget {
  const BankSmsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = BankSmsStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.enabled || store.pending.isEmpty) {
          return const SizedBox.shrink();
        }
        return Card(
          key: const ValueKey('bank-sms-card'),
          color: AppTheme.card,
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.sms_rounded, color: AppTheme.negative),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('برداشت‌های بانکی جدید',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  Text(fa('${store.pending.length} مورد'),
                      style: mutedStyle(12)),
                ]),
                const SizedBox(height: 6),
                for (final it in store.pending.take(5))
                  ListTile(
                    key: ValueKey('bank-sms-${it.fp}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('−${formatMoney(it.toman)}',
                        style: const TextStyle(
                            color: AppTheme.negative,
                            fontWeight: FontWeight.w700)),
                    subtitle: Text('${it.bank} · ${_when(it.at)}',
                        style: mutedStyle(11)),
                    trailing: const Text('ثبت',
                        style: TextStyle(
                            color: AppTheme.negative,
                            fontWeight: FontWeight.w700)),
                    onTap: () => showBankSmsConfirm(context, it),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Wraps the home shell: syncs on open/resume and pops the confirm sheet for
/// an SMS that just arrived (foreground) or a tapped notification.
class BankSmsWatcher extends StatefulWidget {
  const BankSmsWatcher({super.key, required this.child});
  final Widget child;

  @override
  State<BankSmsWatcher> createState() => _BankSmsWatcherState();
}

class _BankSmsWatcherState extends State<BankSmsWatcher>
    with WidgetsBindingObserver {
  StreamSubscription<BankSmsItem>? _sub;
  final _queue = <BankSmsItem>[];
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final s = BankSmsStore.instance;
    _sub = s.arrivals.listen(_pop);
    _sync();
  }

  Future<void> _sync() async {
    final items = await BankSmsStore.instance.syncOnOpen();
    for (final it in items) {
      _pop(it);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  void _pop(BankSmsItem it) {
    if (_queue.any((x) => x.fp == it.fp)) return;
    _queue.add(it);
    _drain();
  }

  Future<void> _drain() async {
    if (_showing || !mounted) return;
    _showing = true;
    while (_queue.isNotEmpty && mounted) {
      final it = _queue.removeAt(0);
      if (BankSmsStore.instance.isHandled(it.fp)) continue;
      await showBankSmsConfirm(context, it);
    }
    _showing = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Settings: opt-in switch, permissions and the Android 13+ guide.
Future<void> showBankSmsSettings(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppTheme.card,
      builder: (_) => const Directionality(
          textDirection: TextDirection.rtl, child: BankSmsSettingsSheet()),
    );

class BankSmsSettingsSheet extends StatefulWidget {
  const BankSmsSettingsSheet({super.key});

  @override
  State<BankSmsSettingsSheet> createState() => _BankSmsSettingsSheetState();
}

class _BankSmsSettingsSheetState extends State<BankSmsSettingsSheet>
    with WidgetsBindingObserver {
  final store = BankSmsStore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.recheck();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) store.recheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _toggle(bool v) async {
    try {
      if (v) {
        await store.tryEnable();
      } else {
        await store.disable();
      }
    } catch (e) {
      store.lastError = 'toggle: ${e.runtimeType}';
    }
    await store.refreshCaps();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = store.caps;
        Widget row(bool ok, String t) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Icon(
                    (c.unknown || !c.supported)
                        ? Icons.help_rounded
                        : ok
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                    size: 18,
                    color: (c.unknown || !c.supported)
                        ? Colors.orange
                        : ok
                            ? AppTheme.positive
                            : AppTheme.negative),
                const SizedBox(width: 6),
                Expanded(child: Text(t, style: const TextStyle(fontSize: 13))),
              ]),
            );
        final mq = MediaQuery.of(context);
        final bottom = 16 + mq.viewPadding.bottom + mq.viewInsets.bottom;
        final needGuide = c.denied;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
          child: SingleChildScrollView(
            child: Column(
              key: const ValueKey('bank-sms-settings'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  key: const ValueKey('bank-sms-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('خواندن خودکار پیامک‌های برداشت بانکی'),
                  subtitle: const Text(
                      'متن پیامک فقط روی همین گوشی خوانده می‌شود و جایی ارسال نمی‌شود؛ فقط برداشتی که تأیید کنید ثبت می‌شود.',
                      style: TextStyle(fontSize: 12)),
                  value: store.enabled,
                  onChanged: _toggle,
                ),
                const Divider(),
                if (!store.capsChecked)
                  const Padding(
                    key: ValueKey('bank-sms-checking'),
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('در حال بررسی مجوزها…',
                          style: TextStyle(fontSize: 13)),
                    ]),
                  )
                else ...[
                  row(c.receive, 'دریافت پیامک (تشخیص لحظه‌ای)'),
                  row(c.read, 'خواندن پیامک‌ها (بررسی هنگام باز کردن برنامه)'),
                  row(c.notify, 'اعلان‌ها'),
                  row(c.fullScreen, 'نمایش پنجرهٔ تمام‌صفحه روی قفل صفحه'),
                  if (c.unknown || !c.supported)
                    Text(
                      c.supported
                          ? 'وضعیت مجوزها از اندروید خوانده نشد (${c.error}). کلید را روشن کنید؛ اگر اجازه نباشد اندروید خودش می‌پرسد.'
                          : 'بخش اندرویدی پاسخ نداد؛ وضعیت مجوزها نامشخص است.',
                      key: const ValueKey('bank-sms-unknown'),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                ],
                if (store.cardPerson.isNotEmpty) ...[
                  const Divider(),
                  const Text('کارت ← برداشت‌کننده (برای انتخاب خودکار)',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final e in store.cardPerson.entries)
                    _CardPersonRow(card: e.key, personId: e.value),
                ],
                if (store.wantEnabled && !store.enabled)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                        'پس از دادن اجازهٔ پیامک، با برگشتن به برنامه خودکار فعال می‌شود.',
                        key: ValueKey('bank-sms-waiting'),
                        style: TextStyle(fontSize: 12, color: Colors.orange)),
                  ),
                if (needGuide) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'اگر اندروید اجازهٔ پیامک را نداد (اندروید ۱۳ به بعد برای برنامه‌های نصب‌شده با APK):\n'
                    '۱. «تنظیمات برنامه» را بزنید.\n'
                    '۲. منوی ⋮ بالای صفحه ← «اجازه دادن به تنظیمات محدودشده».\n'
                    '۳. برگردید، «مجوزها» ← «پیامک» ← «اجازه دادن».\n'
                    '۴. به برنامه برگردید؛ خودکار فعال می‌شود.',
                    key: ValueKey('bank-sms-guide'),
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ],
                const SizedBox(height: 8),
                const SizedBox(height: 8),
                SelectableText(
                  store.diagnostics,
                  key: const ValueKey('bank-sms-diag'),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 10, color: AppTheme.muted),
                ),
                Wrap(spacing: 8, children: [
                  if (needGuide)
                    OutlinedButton(
                      key: const ValueKey('bank-sms-app-settings'),
                      onPressed: store.openAppSettings,
                      child: const Text('تنظیمات برنامه'),
                    ),
                  if (c.supported && !c.fullScreen)
                    OutlinedButton(
                      onPressed: store.openFullScreenSettings,
                      child: const Text('اجازهٔ پنجرهٔ تمام‌صفحه'),
                    ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CardPersonRow extends StatelessWidget {
  const _CardPersonRow({required this.card, required this.personId});
  final String card, personId;

  @override
  Widget build(BuildContext context) {
    final pwo = PwoStore.instance;
    final people = pwo.ledger.activePeople;
    return Row(children: [
      Expanded(child: Text(fa('کارت …$card'))),
      DropdownButton<String>(
        key: ValueKey('card-person-$card'),
        value: people.any((p) => p.id == personId) ? personId : null,
        hint: const Text('انتخاب'),
        items: [
          for (final p in people)
            DropdownMenuItem(value: p.id, child: Text(p.name)),
        ],
        onChanged: (v) => BankSmsStore.instance.setCardPerson(card, v),
      ),
      IconButton(
        icon: const Icon(Icons.close_rounded, size: 18),
        onPressed: () => BankSmsStore.instance.setCardPerson(card, null),
      ),
    ]);
  }
}
