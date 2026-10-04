import 'package:flutter/material.dart';
import 'package:invest/data/notification_inbox_store.dart';
import 'package:invest/domain/models/app_notification.dart';
import 'package:invest/domain/services/notification_service.dart';
import 'package:invest/ui/layout/page_padding.dart';
import 'package:invest/ui/pages/price_alerts_page.dart';
import 'package:invest/ui/theme/app_theme.dart';

/// In-app inbox for local alerts (trades, withdrawals, prices).
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<AppNotification> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload(markRead: true);
  }

  Future<void> _reload({bool markRead = false}) async {
    final items = await NotificationInboxStore.load();
    if (markRead && items.any((e) => !e.read)) {
      await NotificationInboxStore.markAllRead();
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پاک کردن اعلان‌ها'),
        content: const Text('همهٔ اعلان‌های ذخیره‌شده روی این دستگاه حذف شوند؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('پاک کردن'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await NotificationInboxStore.clear();
    if (!mounted) return;
    setState(() => _items = const []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('اعلان‌ها'),
        centerTitle: true,
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'پاک کردن همه',
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _reload(markRead: false),
              child: _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: shellPagePadding(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.16,
                        ),
                        const Icon(
                          Icons.notifications_none_rounded,
                          size: 44,
                          color: AppTheme.muted,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'اعلانی نیست',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.title,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'هشدار قیمت، معاملات و برداشت‌ها اینجا جمع می‌شوند.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.muted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const PriceAlertsPage(),
                                ),
                              );
                            },
                            child: const Text('تنظیم آستانه قیمت'),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: shellPagePadding(),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _NotificationTile(
                        item: _items[i],
                      ),
                    ),
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});
  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    final tone = switch (item.kind) {
      NotificationKind.trades => AppTheme.positive,
      NotificationKind.withdrawals => const Color(0xFFE0C46A),
      NotificationKind.prices => const Color(0xFF6BB8FF),
      NotificationKind.general => AppTheme.muted,
    };
    final icon = switch (item.kind) {
      NotificationKind.trades => Icons.swap_horiz_rounded,
      NotificationKind.withdrawals => Icons.payments_outlined,
      NotificationKind.prices => Icons.show_chart_rounded,
      NotificationKind.general => Icons.notifications_outlined,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.read
              ? AppTheme.border
              : tone.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: AppTheme.title,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.kindLabel,
                      style: TextStyle(
                        color: tone,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (item.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  _formatWhen(item.createdAt),
                  textAlign: TextAlign.right,
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
    );
  }

  static String _formatWhen(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (sameDay) return 'امروز $hh:$mm';
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }
}
