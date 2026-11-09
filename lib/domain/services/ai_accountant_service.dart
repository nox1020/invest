import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:invest/data/bank_sms_store.dart';
import 'package:invest/domain/models/ai_audit_report.dart';
import 'package:invest/domain/models/bank_check.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:invest/domain/utils/money.dart';
import 'package:invest/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// سرویس هوشمند حسابدار و حسابرس مبتنی بر گوگل جمنای
class AiAccountantService {
  AiAccountantService._();
  static final AiAccountantService instance = AiAccountantService._();

  static const String _kReportCacheKey = 'ai_accountant_daily_report_v1';
  static const String _kApiKeyPref = 'gemini_api_key';

  /// بازبینی تمام حساب‌ها و تولید گزارش حسابرسی روزانه
  Future<AiAuditReport> auditAccounts({
    required AppState state,
    String? apiKey,
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // ۱. بررسی کش روزانه در صورتی که کاربر رفرش اجباری نزده باشد
    if (!force) {
      final cachedJson = prefs.getString(_kReportCacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final data = jsonDecode(cachedJson) as Map<String, dynamic>;
          final cachedReport = AiAuditReport.fromJson(data);
          // اگر گزارش مربوط به امروز است، همان را بازگردان
          final auditDate = cachedReport.auditedAtIso.split('T').first;
          final today = DateTime.now().toIso8601String().split('T').first;
          if (auditDate == today) {
            return cachedReport;
          }
        } catch (_) {}
      }
    }

    // ۲. استخراج و تجمیع داده‌های مالی پورتفولیو
    final summaryData = _aggregateFinancialData(state);

    // ۳. تلاش برای فراخوانی API جمنای
    final effectiveKey = apiKey?.trim().isNotEmpty == true
        ? apiKey!.trim()
        : prefs.getString(_kApiKeyPref)?.trim() ?? '';

    AiAuditReport? report;
    if (effectiveKey.isNotEmpty) {
      try {
        report = await _callGeminiApi(summaryData, effectiveKey);
      } catch (e) {
        debugPrint('Gemini API audit error: $e');
      }
    }

    // ۴. در صورت عدم دسترسی به اینترنت یا نبود کلید، استفاده از موتور محاسباتی محلی
    report ??= _generateLocalExpertAudit(summaryData);

    // ۵. ذخیره در کش
    try {
      await prefs.setString(_kReportCacheKey, jsonEncode(report.toJson()));
    } catch (_) {}

    return report;
  }

  /// دریافت آخرین گزارش ذخیره‌شده بدون فراخوانی مجدد
  Future<AiAuditReport?> getLastCachedReport() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_kReportCacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final data = jsonDecode(cachedJson) as Map<String, dynamic>;
        return AiAuditReport.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  /// ذخیره کلید جمنای در تنظیمات برنامه
  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKeyPref, key.trim());
  }

  /// خواندن کلید جمنای از تنظیمات
  Future<String> getSavedApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kApiKeyPref) ?? '';
  }

  /// تجمیع داده‌های مالی برای ارسال به حسابدار
  Map<String, dynamic> _aggregateFinancialData(AppState state) {
    final now = DateTime.now();
    final today = todayIso();

    // محاسبه دارایی‌ها
    double totalCapitalTmn = state.metrics?.totalCapital ?? 0;
    final assetBreakdown = <String, double>{};
    for (final a in state.assets) {
      final val = a.currentValue ?? 0;
      if (val > 0) {
        assetBreakdown[a.name] = val;
      }
    }

    // تفکیک چک‌ها
    int overdueCount = 0;
    int nearDueCount = 0; // کمتر از ۷ روز
    int bouncedCount = 0;
    double pendingPayableTmn = 0;
    double pendingReceivableTmn = 0;

    for (final c in state.checks) {
      if (c.isArchived) continue;

      if (c.status == checkStatusBounced) {
        bouncedCount++;
      } else if (c.status == checkStatusPending) {
        final amount = c.amount ?? 0;
        if (c.direction == checkDirectionPayable) {
          pendingPayableTmn += amount;
        } else if (c.direction == checkDirectionReceivable) {
          pendingReceivableTmn += amount;
        }

        if (c.dueDate.isNotEmpty) {
          final due = DateTime.tryParse(c.dueDate);
          if (due != null) {
            final diff = due.difference(now).inDays;
            if (diff < 0) {
              overdueCount++;
            } else if (diff <= 7) {
              nearDueCount++;
            }
          }
        }
      }
    }

    // معاملات
    final openTradesCount = state.openTrades.length;
    final closedTradesCount = state.closedTrades.length;

    // پیامک‌های بانکی بلاتکلیف
    int unhandledSmsCount = 0;
    try {
      unhandledSmsCount = BankSmsStore.instance.pending.length;
    } catch (_) {}

    return {
      'date': today,
      'total_capital_toman': totalCapitalTmn,
      'asset_count': state.assets.length,
      'top_assets': assetBreakdown,
      'checks': {
        'pending_payable_toman': pendingPayableTmn,
        'pending_receivable_toman': pendingReceivableTmn,
        'overdue_count': overdueCount,
        'near_due_7_days_count': nearDueCount,
        'bounced_count': bouncedCount,
      },
      'trades': {
        'open_count': openTradesCount,
        'closed_count': closedTradesCount,
      },
      'unhandled_bank_sms': unhandledSmsCount,
    };
  }

  /// فراخوانی مستقیم Google Gemini REST API
  Future<AiAuditReport> _callGeminiApi(
    Map<String, dynamic> data,
    String apiKey,
  ) async {
    const model = 'gemini-2.5-flash';
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );

    final prompt = '''
شما سرپرست ارشد حسابداری و حسابرس قسم‌خورده مالی برای نرم‌افزار مدیریت دارایی V+ هستید.
وظیفه شما بررسی تمام ارقام زیر و ارائه گزارش بازبینی روزانه با لحن کاملاً حرفه‌ای، رسمی، فارسی و دقیق حسابداری است:

خلاصه داده‌های مالی پورتفولیو:
${jsonEncode(data)}

دستورالعمل‌های حسابرسی:
۱. وضعیت تطابق چک‌های پرداختی با دارایی نقد و سررسیدهای نزدیک را ارزیابی کنید.
۲. اگر چک معوقه (overdue) یا برگشتی (bounced) وجود دارد، هشدار جدی با سطح "high" صادر کنید.
۳. وضعیت تمرکز دارایی‌ها و ریسک سبد را بررسی کنید.
۴. پیامک‌های بانکی ثبت‌نشده را یادآوری کنید.
۵. خروجی را دقیقاً و فقط به صورت یک شیء JSON با ساختار زیر بازگردانید (بدون متن اضافی خارج از JSON):
{
  "health_score": <عدد صحیح بین ۰ تا ۱۰۰ بر اساس سلامت حساب‌ها>,
  "health_title": "<عنوان کوتاه وضعیت سلامت حساب‌ها>",
  "summary": "<متن ۲ تا ۳ پاراگرافی گزارش تحلیلی روزانه حسابدار به زبان فارسی روان>",
  "alerts": [
    {
      "severity": "high" | "medium" | "low",
      "title": "<عنوان هشدار>",
      "detail": "<شرح مختصر و اقدام لازم>",
      "category": "چک" | "تراکنش" | "نقدینگی" | "ریسک"
    }
  ],
  "recommendations": [
    "<توصیه مالی و حسابداری اول>",
    "<توصیه مالی و حسابداری دوم>",
    "<توصیه مالی و حسابداری سوم>"
  ]
}
''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
      }
    });

    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw Exception('خطای سرور جمنای (${res.statusCode}): ${res.body}');
    }

    final resData = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = resData['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('هیچ پاسخی از جمنای دریافت نشد.');
    }

    final text = candidates[0]['content']?['parts']?[0]?['text']?.toString() ?? '';
    final parsedJson = jsonDecode(text) as Map<String, dynamic>;

    return AiAuditReport.fromJson({
      ...parsedJson,
      'audited_at': DateTime.now().toIso8601String(),
      'total_capital': data['total_capital_toman'],
      'pending_payable': (data['checks'] as Map)['pending_payable_toman'],
      'pending_receivable': (data['checks'] as Map)['pending_receivable_toman'],
      'overdue_checks': (data['checks'] as Map)['overdue_count'],
      'open_trades': (data['trades'] as Map)['open_count'],
      'is_ai': true,
    });
  }

  /// موتور تحلیل قواعد خبره حسابداری در صورت عدم دسترسی به API آنلاین
  AiAuditReport _generateLocalExpertAudit(Map<String, dynamic> data) {
    final checks = data['checks'] as Map<String, dynamic>;
    final overdueCount = checks['overdue_count'] as int? ?? 0;
    final nearDueCount = checks['near_due_7_days_count'] as int? ?? 0;
    final bouncedCount = checks['bounced_count'] as int? ?? 0;
    final pendingPayable = (checks['pending_payable_toman'] as num?)?.toDouble() ?? 0;
    final pendingReceivable = (checks['pending_receivable_toman'] as num?)?.toDouble() ?? 0;
    final totalCapital = (data['total_capital_toman'] as num?)?.toDouble() ?? 0;
    final unhandledSms = data['unhandled_bank_sms'] as int? ?? 0;

    int score = 95;
    final alerts = <AiAuditAlert>[];
    final recs = <String>[];

    // ۱. بررسی چک‌های معوقه و برگشتی
    if (bouncedCount > 0) {
      score -= 30;
      alerts.add(AiAuditAlert(
        severity: 'high',
        title: '$bouncedCount فقره چک برگشتی ثبت شده است',
        detail: 'رسیدگی حقوقی و مذاکره با صادرکننده در اولویت نخست جریان مالی قرار دارد.',
        category: 'چک',
      ));
    }

    if (overdueCount > 0) {
      score -= 20;
      alerts.add(AiAuditAlert(
        severity: 'high',
        title: '$overdueCount فقره چک سررسید گذشته (معوق)',
        detail: 'وضعیت تسویه و دریافت یا پاس شدن این اسناد تجاری باید فوراً در سامانه به‌روزرسانی شود.',
        category: 'چک',
      ));
    }

    if (nearDueCount > 0) {
      score -= 10;
      alerts.add(AiAuditAlert(
        severity: 'medium',
        title: '$nearDueCount چک نزدیک به موعد سررسید (طی ۷ روز آینده)',
        detail: 'موجودی حساب‌های متصل به دسته چک را جهت جلوگیری از برگشت وجه بررسی و شارژ فرمایید.',
        category: 'نقدینگی',
      ));
    }

    // ۲. بررسی جریان نقدینگی در تعهدات
    if (pendingPayable > pendingReceivable && pendingPayable > 0) {
      final diff = pendingPayable - pendingReceivable;
      alerts.add(AiAuditAlert(
        severity: 'medium',
        title: 'تراز منفی تعهدات چک به میزان ${formatMoney(diff)} تومان',
        detail: 'میزان چک‌های پرداختی متعهدشده از دریافتی‌ها بیشتر است؛ پیش‌بینی ورودی نقدی ضروری است.',
        category: 'نقدینگی',
      ));
    }

    // ۳. پیامک‌های بدون ثبت
    if (unhandledSms > 0) {
      alerts.add(AiAuditAlert(
        severity: 'low',
        title: '$unhandledSms تراکنش پیامک بانکی بدون معامله متناظر',
        detail: 'جهت حفظ تراز دفاتر مالی، پیامک‌های بانکی تعیین‌تکلیف نشده را به معاملات پیوند دهید.',
        category: 'تراکنش',
      ));
    }

    // توصیه‌ها
    if (score >= 85) {
      recs.add('انضباط مالی و ثبت اسناد در سطح بسیار مطلوب قرار دارد.');
      recs.add('پیشنهاد می‌شود مازاد نقدینگی ماهانه را به دارایی‌های ضد تورمی (طلا یا تتر) تخصیص دهید.');
    } else {
      recs.add('اولویت فوری بر تعیین تکلیف چک‌های سررسیدشده و تأمین وجه تعهدات هفته جاری است.');
      recs.add('توصیه می‌شود قبل از ورود به معاملات جدید، مانده خالص نقدینگی را مثبت تثبیت کنید.');
    }
    recs.add('گزارش‌گیری روزانه حسابدار را برای ثبت به‌موقع تراکنش‌ها تکرار نمایید.');

    score = score.clamp(20, 100);

    String title;
    if (score >= 85) {
      title = 'وضعیت حساب‌ها: مطلوب و پایدار';
    } else if (score >= 60) {
      title = 'وضعیت حساب‌ها: نیازمند توجه و پایش تعهدات';
    } else {
      title = 'وضعیت حساب‌ها: هشدار ریسک و کسری نقدینگی';
    }

    final summary = '''
بررسی دفاتر مالی و سبد دارایی‌ها در تاریخ ${todayIso()} نشان می‌دهد که ارزش کل پورتفولیو معادل ${formatMoney(totalCapital)} تومان است. در بخش اسناد تجاری، مجموعاً مبلغ ${formatMoney(pendingPayable)} تومان چک پرداختی در دست تسویه و مبلغ ${formatMoney(pendingReceivable)} تومان اسناد دریافتی وجود دارد.
${overdueCount > 0 || bouncedCount > 0 ? 'توجه: وجود اسناد سررسید گذشته نیازمند اقدام فوری جهت جلوگیری از اختلال در اعتبار بانکی و رتبه اعتباری است.' : 'جریان وصول و تسویه اسناد جاری بر اساس جدول زمانی در جریان است.'}
توصیه حسابرس: تعهدات سررسید نزدیک را با مانده نقدینگی تطبیق داده و تراکنش‌های باز را به‌صورت مستمر مستندسازی نمایید.
''';

    return AiAuditReport(
      healthScore: score,
      healthTitle: title,
      summary: summary.trim(),
      alerts: alerts,
      recommendations: recs,
      auditedAtIso: DateTime.now().toIso8601String(),
      totalCapitalToman: totalCapital,
      pendingChecksPayableToman: pendingPayable,
      pendingChecksReceivableToman: pendingReceivable,
      overdueChecksCount: overdueCount,
      openTradesCount: data['trades']['open_count'] as int? ?? 0,
      isAiGenerated: false,
    );
  }
}
