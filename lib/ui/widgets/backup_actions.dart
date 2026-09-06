import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:invest/domain/services/backup_service.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> exportAppBackup(BuildContext context) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    messenger.showSnackBar(
      const SnackBar(content: Text('در حال آماده‌سازی پشتیبان رمزگذاری‌شده…')),
    );
    final bytes = await state.exportEncryptedBackup();
    final stamp = todayIso().replaceAll('-', '');
    final name = 'vplus-backup-$stamp.${BackupService.fileExtension}';
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: BackupService.mimeType,
            name: name,
          ),
        ],
        subject: 'پشتیبان V+',
        text: 'فایل رمزگذاری‌شده پشتیبان V+ — فقط با همین اپلیکیشن باز می‌شود.',
      ),
    );
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'پشتیبان کامل آماده شد '
            '(تنظیمات، ${state.assets.length} دارایی، '
            '${state.openTrades.length + state.closedTrades.length} معامله، '
            '${state.withdrawals.length} برداشت).',
          ),
        ),
      );
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('صدور ناموفق: $e')));
  }
}

Future<void> importAppBackup(BuildContext context) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);

  final picked = await FilePicker.platform.pickFiles(
    type: FileType.any,
    withData: true,
    allowMultiple: false,
  );
  if (picked == null || picked.files.isEmpty) return;
  final file = picked.files.single;
  Uint8List? bytes = file.bytes;
  if ((bytes == null || bytes.isEmpty) && file.path != null) {
    bytes = await XFile(file.path!).readAsBytes();
  }
  if (bytes == null || bytes.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('خواندن فایل ممکن نشد.')),
    );
    return;
  }

  final BackupRestoreReport preview;
  try {
    final payload = state.peekEncryptedBackup(bytes);
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('وارد کردن پشتیبان'),
        content: Text(
          'تمام داده‌های فعلی با این پشتیبان جایگزین می‌شود.\n\n'
          'صاده‌شده: ${formatDisplayDate(payload.exportedAt, state.settings.calendar)}\n'
          'تنظیمات: تقویم، تم، ارز، نرخ‌ها، آدرس APIها\n'
          'دارایی: ${payload.assets.length}\n'
          'معاملات باز: ${payload.openTradeCount}\n'
          'معاملات بسته: ${payload.closedTradeCount}\n'
          'برداشت‌ها: ${payload.withdrawals.length}\n'
          'اسنپ‌شات سرمایه: ${payload.capitalSnapshots.length}\n'
          'قفل برنامه: ${payload.appLockHash != null && payload.appLockHash!.isNotEmpty ? 'دارد' : 'ندارد'}\n\n'
          'این فایل فقط با اپ V+ رمزگشایی می‌شود.',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.negative,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('جایگزینی'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    messenger.showSnackBar(
      const SnackBar(content: Text('در حال وارد کردن پشتیبان…')),
    );
    preview = await state.importEncryptedBackup(bytes);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('وارد کردن ناموفق: $e')));
    return;
  }

  if (!context.mounted) return;
  final msg = StringBuffer('پشتیبان با موفقیت وارد شد.');
  if (preview.remotePushed) {
    msg.write(' داده‌ها با سرور همگام شد.');
  }
  if (preview.remoteWarning != null) {
    msg.write('\n${preview.remoteWarning}');
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(msg.toString()),
      duration: const Duration(seconds: 5),
    ),
  );
}
