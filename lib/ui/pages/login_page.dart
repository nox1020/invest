import 'package:flutter/material.dart';
import 'package:invest/data/invest_api_client.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            const Text(
              'V+ Invest',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.title,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'با شماره موبایل وینور وارد شوید',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textAlign: TextAlign.right,
              enabled: !_otpSent && !_busy,
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
                enabled: !_busy,
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
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.negative),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : (_otpSent ? _verify : _requestOtp),
              child: Text(_busy
                  ? 'لطفاً صبر کنید…'
                  : (_otpSent ? 'ورود' : 'دریافت کد')),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _otpSent = false;
                          _codeCtrl.clear();
                          _debugCode = null;
                        }),
                child: const Text('تغییر شماره'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
