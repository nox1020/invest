import 'dart:async';

import 'package:flutter/material.dart';
import 'package:invest/data/invest_api_client.dart';
import 'package:invest/ui/theme/app_theme.dart';

/// Turns engine/API exceptions into a short Persian sentence for the APK.
String formatUserError(Object error) {
  if (error is InvestApiException) {
    return _fromApi(error);
  }
  if (error is ArgumentError) {
    final msg = (error.message ?? '').toString().trim();
    if (msg.isNotEmpty && !_looksTechnical(msg)) return msg;
    return 'مقدار واردشده نامعتبر است.';
  }
  if (error is FormatException) {
    return 'مقدار واردشده نامعتبر است.';
  }
  if (error is TimeoutException) {
    return 'زمان اتصال به سرور تمام شد. دوباره تلاش کنید.';
  }
  if (error is StateError) {
    final msg = error.message.trim();
    if (msg.isNotEmpty && !_looksTechnical(msg)) return msg;
  }

  final raw = error.toString().trim();
  final stripped = raw
      .replaceFirst(
          RegExp(r'^(Exception|Error|StateError|ArgumentError):\s*'), '')
      .trim();
  if (stripped.isEmpty) return 'خطایی رخ داد. لطفاً دوباره تلاش کنید.';
  if (_looksTechnical(stripped) || _looksTechnical(raw)) {
    return _fromTechnical(raw);
  }
  return stripped;
}

String _fromApi(InvestApiException error) {
  final msg = error.message.trim();
  if (msg.isNotEmpty && RegExp(r'[\u0600-\u06FF]').hasMatch(msg)) {
    return msg;
  }
  switch (error.statusCode) {
    case 400:
    case 422:
      return 'اطلاعات واردشده نامعتبر است.';
    case 401:
      return 'نشست شما منقضی شده. دوباره وارد شوید.';
    case 403:
      return 'اجازه این عملیات را ندارید.';
    case 404:
      return 'مورد درخواستی در سرور یافت نشد.';
    case 405:
      return 'این عملیات در نسخه فعلی پشتیبانی نمی‌شود.';
    case 409:
      return 'این مورد از قبل وجود دارد.';
    case 429:
      return 'تعداد درخواست‌ها زیاد است. کمی بعد تلاش کنید.';
    case 500:
    case 502:
    case 503:
      return 'سرور موقتاً در دسترس نیست. کمی بعد تلاش کنید.';
  }
  if (error.errorCode == 'network_error') {
    return 'ارتباط با سرور برقرار نشد (آفلاین).';
  }
  if (error.errorCode == 'auth_required') {
    return 'نشست شما منقضی شده. دوباره وارد شوید.';
  }
  if (msg.isNotEmpty && !_looksTechnical(msg)) return msg;
  return 'خطا در ارتباط با سرور.';
}

String _fromTechnical(String raw) {
  if (raw.contains('NoSuchMethodError')) {
    return 'این عملیات در نسخه فعلی پشتیبانی نمی‌شود. برنامه را به‌روز کنید.';
  }
  if (raw.contains('SocketException') ||
      raw.contains('HandshakeException') ||
      raw.contains('ClientException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('Connection refused') ||
      raw.contains('Network is unreachable')) {
    return 'ارتباط با سرور برقرار نشد (آفلاین).';
  }
  if (raw.contains('TimeoutException') || raw.contains('timed out')) {
    return 'زمان اتصال به سرور تمام شد. دوباره تلاش کنید.';
  }
  if (raw.contains('Null check operator') || raw.contains('NullThrownError')) {
    return 'داده ناقص است. لطفاً دوباره تلاش کنید.';
  }
  return 'خطایی رخ داد. لطفاً دوباره تلاش کنید.';
}

bool _looksTechnical(String text) {
  if (text.contains('NoSuchMethodError') ||
      text.contains('Null check operator') ||
      text.contains('Tried calling:') ||
      text.contains('Receiver:') ||
      text.contains('Instance of ') ||
      text.contains('#0 ') ||
      text.contains('package:')) {
    return true;
  }
  final persian = RegExp(r'[\u0600-\u06FF]');
  if (persian.hasMatch(text)) return false;
  return RegExp(r'[A-Z][a-zA-Z]+Exception|[a-z]+://|_+[a-zA-Z]').hasMatch(text);
}

/// Floating snackbar with a readable Persian error.
void showUserError(BuildContext context, Object error) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          formatUserError(error),
          textAlign: TextAlign.right,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Compact banner for page-level status errors (refresh, index, login).
class UserErrorBanner extends StatelessWidget {
  const UserErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final text = message.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.negative.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: AppTheme.negative,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }
}

/// Release-safe fallback instead of the raw red/yellow error screen.
Widget userErrorPanel(FlutterErrorDetails details) {
  return Material(
    color: AppTheme.bg,
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppTheme.negative, size: 40),
              const SizedBox(height: 16),
              Text(
                formatUserError(details.exception),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'اگر مشکل ادامه داشت، برنامه را ببندید و دوباره باز کنید.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
