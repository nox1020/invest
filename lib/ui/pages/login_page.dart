import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:invest/domain/utils/sms_otp.dart';
import 'package:invest/ui/widgets/app_logo.dart';
import 'package:invest/state/app_state.dart';
import 'package:invest/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:smart_auth/smart_auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _smartAuth = SmartAuth.instance;
  bool _otpSent = false;
  bool _busy = false;
  bool _smsListenActive = false;
  String? _error;
  String? _debugCode;

  bool get _androidSmsAutofill => !kIsWeb && Platform.isAndroid;

  @override
  void dispose() {
    unawaited(_stopSmsListen());
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _stopSmsListen() async {
    if (!_smsListenActive) return;
    _smsListenActive = false;
    try {
      await _smartAuth.removeSmsRetrieverApiListener();
    } catch (_) {}
    try {
      await _smartAuth.removeUserConsentApiListener();
    } catch (_) {}
  }

  /// Prefer SMS Retriever (`<#>…hash`); fall back to User Consent dialog.
  Future<void> _listenForSmsOtp() async {
    if (!_androidSmsAutofill) return;
    await _stopSmsListen();
    _smsListenActive = true;

    try {
      final retriever = await _smartAuth.getSmsWithRetrieverApi(
        matcher: r'\d{4,8}',
      );
      if (!mounted || !_smsListenActive) return;
      if (retriever.hasData) {
        final filled = _applySmsCode(retriever.requireData);
        if (filled) {
          _smsListenActive = false;
          return;
        }
      }
    } catch (_) {
      // Retriever unavailable — try User Consent below.
    }

    if (!mounted || !_smsListenActive) return;

    try {
      final consent = await _smartAuth.getSmsWithUserConsentApi(
        matcher: r'\d{4,8}',
      );
      if (!mounted || !_smsListenActive) return;
      if (consent.hasData && _applySmsCode(consent.requireData)) {
        _smsListenActive = false;
      }
    } catch (_) {
      // Manual entry still works.
    }
  }

  bool _applySmsCode(SmartAuthSms sms) {
    final code = SmsOtp.extract(sms.sms) ?? sms.code;
    if (code == null || code.isEmpty) return false;
    _codeCtrl.text = code;
    _codeCtrl.selection = TextSelection.collapsed(offset: code.length);
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _requestOtp() async {
    setState(() {
      _busy = true;
      _error = null;
      _debugCode = null;
    });
    final state = context.read<AppState>();
    try {
      // Register Retriever before the SMS can arrive.
      if (_androidSmsAutofill) {
        unawaited(_listenForSmsOtp());
      }
      final debug = await state.requestOtp(_phoneCtrl.text.trim());
      setState(() {
        _otpSent = true;
        _debugCode = debug;
      });
    } catch (e) {
      await _stopSmsListen();
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
      await _stopSmsListen();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _changePhone() async {
    await _stopSmsListen();
    setState(() {
      _otpSent = false;
      _codeCtrl.clear();
      _debugCode = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _busy;

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
                autofillHints: const [AutofillHints.oneTimeCode],
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
                onPressed: blocked ? null : _changePhone,
                child: const Text('تغییر شماره'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
