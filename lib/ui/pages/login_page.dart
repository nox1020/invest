import 'package:flutter/material.dart';
import 'package:invest/ui/widgets/app_logo.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;
  bool _offlineBusy = false;
  String? _error;
  String? _debugCode;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    setState(() {
      _busy = true;
      _error = null;
      _debugCode = null;
    });
    final state = context.read<AppState>();
    try {
      final debug = await state.requestOtp(_phoneCtrl.text.trim());
      setState(() {
        _otpSent = true;
        _debugCode = debug;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<AppState>();
    try {
      await state.verifyOtp(_phoneCtrl.text.trim(), _codeCtrl.text.trim());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _enterOffline() async {
    setState(() {
      _offlineBusy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().enterOfflineLocalMode();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _offlineBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _busy || _offlineBusy;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 28),
            const Center(child: AppLogo()),
            const SizedBox(height: 10),
            const Text(
              'با شماره موبایل وینور وارد شوید',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textAlign: TextAlign.right,
              enabled: !_otpSent && !blocked,
              decoration: const InputDecoration(
                labelText: 'شماره موبایل',
                hintText: '09123456789',
              ),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                enabled: !blocked,
                decoration: const InputDecoration(
                  labelText: 'کد تأیید',
                ),
              ),
              if (_debugCode != null) ...[
                const SizedBox(height: 8),
                Text(
                  'کد توسعه: $_debugCode',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.negative.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.negative.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.negative, height: 1.4),
                ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: blocked ? null : (_otpSent ? _verify : _requestOtp),
              child: Text(
                _busy
                    ? 'لطفاً صبر کنید…'
                    : (_otpSent ? 'ورود' : 'دریافت کد'),
              ),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: blocked
                    ? null
                    : () => setState(() {
                          _otpSent = false;
                          _codeCtrl.clear();
                          _debugCode = null;
                        }),
                child: const Text('تغییر شماره'),
              ),
            ],
            const SizedBox(height: 28),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'یا',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'بدون اینترنت',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.title,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        Icons.cloud_off_outlined,
                        color: AppTheme.positive,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'اگر اینترنت ندارید، می‌توانید با فضای کاری محلی وارد شوید. داده‌های قبلی ذخیره‌شده در صورت وجود نمایش داده می‌شود.',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: AppTheme.muted,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: blocked ? null : _enterOffline,
                    icon: _offlineBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.phone_android_rounded, size: 18),
                    label: Text(
                      _offlineBusy ? 'در حال ورود…' : 'ورود آفلاین',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
