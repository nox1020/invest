import 'package:flutter/material.dart';
import 'package:invest/data/write_queue.dart';
import 'package:invest/ui/theme/app_theme.dart';

/// Shows the bound account's unsent writes. Each can be discarded; refused
/// ones show the server's reason. Nothing here sends or deletes server data.
class PendingWritesPanel extends StatelessWidget {
  const PendingWritesPanel({super.key, required this.queue, this.onSendNow});
  final WriteQueue queue;
  final Future<void> Function()? onSendNow;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final items = queue.items;
        if (items.isEmpty) return const SizedBox.shrink();
        const amber = Color(0xFFE0C46A);
        return Container(
          key: const ValueKey('pending-panel'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: amber.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                if (onSendNow != null)
                  TextButton(
                    key: const ValueKey('pending-send'),
                    onPressed: queue.flushing ? null : onSendNow,
                    child: Text(queue.flushing ? 'در حال ارسال…' : 'ارسال الان'),
                  ),
                const Spacer(),
                Flexible(
                  flex: 6,
                  child: Text(
                    '${items.length} تغییر در صف ارسال (هنوز روی سرور نیست)',
                    key: const ValueKey('pending-count'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.cloud_upload_outlined, color: amber, size: 18),
              ]),
              for (final w in items)
                Row(children: [
                  IconButton(
                    key: ValueKey('pending-discard-${w.key}'),
                    tooltip: 'دور انداختن',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => _discard(context, w),
                  ),
                  if (w.error != null)
                    IconButton(
                      key: ValueKey('pending-retry-${w.key}'),
                      tooltip: 'تلاش دوباره',
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      onPressed: () async {
                        await queue.retry(w.key);
                        await onSendNow?.call();
                      },
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(w.label,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12)),
                        if (w.error != null)
                          Text('رد شد: ${w.error}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  color: AppTheme.negative, fontSize: 11)),
                      ],
                    ),
                  ),
                ]),
              const Text(
                'بعد از اتصال به ترتیب و فقط برای همین حساب فرستاده می‌شوند. ارسال دوباره هیچ تغییری را تکراری ثبت نمی‌کند.',
                textAlign: TextAlign.right,
                style: TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _discard(BuildContext context, QueuedWrite w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('دور انداختن این تغییر؟'),
          content: Text('«${w.label}» هرگز به سرور فرستاده نمی‌شود.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
            TextButton(
                key: const ValueKey('pending-discard-ok'),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('دور انداختن')),
          ],
        ),
      ),
    );
    if (ok == true) await queue.discard(w.key);
  }
}
