import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:invest/domain/models/profit_alert.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/settings_ui.dart';
import 'package:provider/provider.dart';

Future<void> showProfitAlertEditor(
  BuildContext context, {
  required String id,
  String name = '',
  String symbol = '',
  double? currentPnl,
  double? currentPnlPct,
}) async {
  final state = context.read<AppState>();
  if (state.readOnlyOffline) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('در حالت آفلاین ذخیره ممکن نیست')),
    );
    return;
  }
  final existing = state.settings.profitAlertFor(
    id,
    name: name,
    symbol: symbol,
  );
  final saved = await showModalBottomSheet<ProfitAlert>(
    context: context,
    isScrollControlled: true,
    backgroundColor: tgSettingsGroupBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => _ProfitAlertSheet(
      initial: existing,
      currentPnl: currentPnl,
      currentPnlPct: currentPnlPct,
    ),
  );
  if (saved == null || !context.mounted) return;
  if (saved.isArmed) {
    final ok = await NotificationService.instance.requestPermission();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اجازه اعلان در تنظیمات سیستم داده نشد'),
        ),
      );
    }
  }
  final next = state.settings.copyWith();
  next.upsertProfitAlert(saved);
  if (!next.notifyTrades) next.notifyTrades = true;
  if (!next.notificationsEnabled) next.notificationsEnabled = true;
  try {
    await state.saveSettings(next);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved.isArmed ? 'آستانه سود ذخیره شد' : 'آستانه سود حذف شد',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ذخیره ناموفق: $e')),
    );
  }
}

class ProfitAlertBell extends StatelessWidget {
  const ProfitAlertBell({
    super.key,
    required this.id,
    this.name = '',
    this.symbol = '',
    this.currentPnl,
    this.currentPnlPct,
    this.iconSize = 20,
    this.color,
  });

  final String id;
  final String name;
  final String symbol;
  final double? currentPnl;
  final double? currentPnlPct;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final armed = context.watch<AppState>().settings.profitAlertFor(id).isArmed;
    return IconButton(
      tooltip: armed ? 'ویرایش آستانه سود' : 'تنظیم آستانه سود',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: () => showProfitAlertEditor(
        context,
        id: id,
        name: name,
        symbol: symbol,
        currentPnl: currentPnl,
        currentPnlPct: currentPnlPct,
      ),
      icon: Icon(
        armed
            ? Icons.notifications_active_rounded
            : Icons.notifications_outlined,
        size: iconSize,
        color: color ?? (armed ? const Color(0xFFFF9500) : AppTheme.muted),
      ),
    );
  }
}

class _ProfitAlertSheet extends StatefulWidget {
  const _ProfitAlertSheet({
    required this.initial,
    this.currentPnl,
    this.currentPnlPct,
  });

  final ProfitAlert initial;
  final double? currentPnl;
  final double? currentPnlPct;

  @override
  State<_ProfitAlertSheet> createState() => _ProfitAlertSheetState();
}

class _ProfitAlertSheetState extends State<_ProfitAlertSheet> {
  late bool _enabled;
  late final TextEditingController _profitToman;
  late final TextEditingController _lossToman;
  late final TextEditingController _profitPct;
  late final TextEditingController _lossPct;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initial.enabled;
    _profitToman = TextEditingController(text: _seedMoney(widget.initial.profitToman));
    _lossToman = TextEditingController(text: _seedMoney(widget.initial.lossToman));
    _profitPct = TextEditingController(text: _seedPct(widget.initial.profitPct));
    _lossPct = TextEditingController(text: _seedPct(widget.initial.lossPct));
  }

  String _seedMoney(double? v) {
    if (v == null || v <= 0) return '';
    return formatNumber(v, decimals: v >= 1000 ? 0 : 0);
  }

  String _seedPct(double? v) {
    if (v == null || v <= 0) return '';
    return formatNumber(v, decimals: v >= 10 ? 0 : 1);
  }

  @override
  void dispose() {
    _profitToman.dispose();
    _lossToman.dispose();
    _profitPct.dispose();
    _lossPct.dispose();
    super.dispose();
  }

  static final _digits = FilteringTextInputFormatter.allow(
    RegExp(r'[0-9۰-۹٠-٩.,٬٫]'),
  );

  void _submit() {
    final profitT = parseFlexibleNumber(_profitToman.text);
    final lossT = parseFlexibleNumber(_lossToman.text);
    final profitP = parseFlexibleNumber(_profitPct.text);
    final lossP = parseFlexibleNumber(_lossPct.text);
    final next = ProfitAlert(
      id: widget.initial.id,
      name: widget.initial.name,
      symbol: widget.initial.symbol,
      enabled: _enabled,
      profitToman: (profitT != null && profitT > 0) ? profitT : null,
      lossToman: (lossT != null && lossT > 0) ? lossT : null,
      profitPct: (profitP != null && profitP > 0) ? profitP : null,
      lossPct: (lossP != null && lossP > 0) ? lossP : null,
    );
    next.enabled = _enabled && next.hasThreshold;
    Navigator.pop(context, next);
  }

  @override
  Widget build(BuildContext context) {
    final pnl = widget.currentPnl;
    final pct = widget.currentPnlPct;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.muted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'آستانه سود ${widget.initial.displayName}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.title,
            ),
          ),
          if (pnl != null) ...[
            const SizedBox(height: 6),
            Text(
              'سود فعلی: ${formatMoney(pnl, showSign: true)}'
              '${pct == null ? '' : ' (${formatPct(pct)})'}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.muted),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('فعال'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          TextField(
            controller: _profitToman,
            enabled: _enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_digits],
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              labelText: 'اگر سود بیشتر از (تومان)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lossToman,
            enabled: _enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_digits],
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              labelText: 'اگر زیان بیشتر از (تومان)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _profitPct,
            enabled: _enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_digits],
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              labelText: 'اگر سود بیشتر از (٪)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lossPct,
            enabled: _enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_digits],
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              labelText: 'اگر زیان بیشتر از (٪)',
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            child: const Text('ذخیره'),
          ),
          TextButton(
            onPressed: () {
              _profitToman.clear();
              _lossToman.clear();
              _profitPct.clear();
              _lossPct.clear();
              _submit();
            },
            child: const Text('حذف آستانه'),
          ),
        ],
      ),
    );
  }
}
