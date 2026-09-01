import 'package:flutter/material.dart';
import 'package:invest/security/app_lock.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:invest/ui/widgets/app_logo.dart';
import 'package:provider/provider.dart';

/// Local password gate — unrelated to Vinor OTP.
class AppLockPage extends StatefulWidget {
  const AppLockPage({super.key});

  @override
  State<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends State<AppLockPage> {
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final state = context.read<AppState>();
    if (!state.biometricUnlockEnabled || !state.biometricAvailable) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await state.unlockWithBiometric();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await context.read<AppState>().unlockApp(_passwordCtrl.text);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'رمز ورود نادرست است.';
        _passwordCtrl.clear();
      });
      return;
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final showBiometric =
        state.biometricUnlockEnabled && state.biometricAvailable;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            const Center(child: AppLogo(showTitle: true, titleSize: 26)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 40,
                    color: AppTheme.positive.withValues(alpha: 0.9),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'برنامه قفل است',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.title,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    showBiometric
                        ? 'رمز ورود یا ${state.biometricLabel} را وارد کنید'
                        : 'برای دسترسی به V+ رمز ورود را وارد کنید',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.muted, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (showBiometric) ...[
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _tryBiometric,
                  icon: const Icon(Icons.fingerprint_rounded, size: 26),
                  label: Text('ورود با ${state.biometricLabel}'),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('یا', style: TextStyle(color: AppTheme.muted)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              enabled: !_busy,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'رمز ورود',
                errorText: _error,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _busy ? null : _unlock(),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _busy ? null : _unlock,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(_busy ? 'لطفاً صبر کنید…' : 'ورود با رمز'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showAppLockSetDialog(
  BuildContext context, {
  required bool hasLock,
}) async {
  final currentCtrl = TextEditingController();
  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  var obscure = true;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(hasLock ? 'تغییر رمز ورود' : 'تنظیم رمز ورود'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'رمز محلی برای باز کردن برنامه — ربطی به OTP وینور ندارد.',
                textAlign: TextAlign.right,
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (hasLock)
                TextField(
                  controller: currentCtrl,
                  obscureText: obscure,
                  decoration: const InputDecoration(labelText: 'رمز فعلی'),
                  textAlign: TextAlign.right,
                ),
              TextField(
                controller: newCtrl,
                obscureText: obscure,
                decoration: const InputDecoration(labelText: 'رمز جدید'),
                textAlign: TextAlign.right,
              ),
              TextField(
                controller: confirmCtrl,
                obscureText: obscure,
                decoration: const InputDecoration(labelText: 'تکرار رمز'),
                textAlign: TextAlign.right,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setLocal(() => obscure = !obscure),
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  label: Text(obscure ? 'نمایش رمز' : 'مخفی کردن'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    ),
  );

  if (ok != true || !context.mounted) {
    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
    return false;
  }

  final state = context.read<AppState>();
  if (hasLock &&
      !verifyAppLockPassword(
        currentCtrl.text,
        state.appLockHash ?? '',
      )) {
    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رمز فعلی نادرست است.')),
      );
    }
    return false;
  }

  final newPass = newCtrl.text;
  final confirm = confirmCtrl.text;
  currentCtrl.dispose();
  newCtrl.dispose();
  confirmCtrl.dispose();

  if (newPass.length < appLockMinPasswordLen) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رمز باید حداقل ۴ کاراکتر باشد.')),
      );
    }
    return false;
  }
  if (newPass != confirm) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تکرار رمز با رمز جدید یکسان نیست.')),
      );
    }
    return false;
  }

  await state.setAppLockPassword(newPass);
  return true;
}
