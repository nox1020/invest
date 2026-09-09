import 'package:flutter/material.dart';

/// High-level asset categories for create/edit UX and icons.
enum AssetKind {
  crypto,
  gold,
  cash,
  property,
  vehicle,
  other,
}

extension AssetKindX on AssetKind {
  String get id => switch (this) {
        AssetKind.crypto => 'crypto',
        AssetKind.gold => 'gold',
        AssetKind.cash => 'cash',
        AssetKind.property => 'property',
        AssetKind.vehicle => 'vehicle',
        AssetKind.other => 'other',
      };

  String get label => switch (this) {
        AssetKind.crypto => 'ارز دیجیتال',
        AssetKind.gold => 'طلا',
        AssetKind.cash => 'نقد / تتر',
        AssetKind.property => 'ملک',
        AssetKind.vehicle => 'خودرو',
        AssetKind.other => 'سایر',
      };

  String get defaultSymbol => switch (this) {
        AssetKind.crypto => '',
        AssetKind.gold => 'GOLD',
        AssetKind.cash => 'USDT',
        AssetKind.property => 'REAL',
        AssetKind.vehicle => 'CAR',
        AssetKind.other => '',
      };

  String get nameHint => switch (this) {
        AssetKind.crypto => 'مثل Bitcoin',
        AssetKind.gold => 'مثل طلای آب‌شده',
        AssetKind.cash => 'مثل تتر یا دلار',
        AssetKind.property => 'مثل آپارتمان ونک',
        AssetKind.vehicle => 'مثل پژو ۲۰۷',
        AssetKind.other => 'نام دارایی',
      };

  String get symbolHint => switch (this) {
        AssetKind.crypto => 'مثل BTC',
        AssetKind.gold => 'GOLD',
        AssetKind.cash => 'USDT',
        AssetKind.property => 'REAL',
        AssetKind.vehicle => 'CAR',
        AssetKind.other => 'اختیاری',
      };

  String get quantityLabel => switch (this) {
        AssetKind.crypto => 'مقدار',
        AssetKind.gold => 'مقدار (گرم)',
        AssetKind.cash => 'مقدار',
        AssetKind.property => 'تعداد واحد',
        AssetKind.vehicle => 'تعداد',
        AssetKind.other => 'مقدار',
      };

  String get buyPriceLabel => switch (this) {
        AssetKind.property => 'بهای خرید (تومان)',
        AssetKind.vehicle => 'بهای خرید (تومان)',
        AssetKind.gold => 'قیمت خرید هر گرم',
        _ => 'قیمت خرید (تومان)',
      };

  String get currentPriceLabel => switch (this) {
        AssetKind.property => 'ارزش فعلی (تومان)',
        AssetKind.vehicle => 'ارزش فعلی (تومان)',
        AssetKind.gold => 'قیمت فعلی هر گرم',
        _ => 'قیمت فعلی (تومان)',
      };

  String get unitLabel => switch (this) {
        AssetKind.gold => 'گرم',
        AssetKind.property => 'واحد',
        AssetKind.vehicle => 'دستگاه',
        AssetKind.cash => '',
        AssetKind.crypto => '',
        AssetKind.other => '',
      };

  /// Typical starting quantity when creating this kind.
  double get defaultQuantity => switch (this) {
        AssetKind.property => 1,
        AssetKind.vehicle => 1,
        AssetKind.gold => 0,
        AssetKind.cash => 0,
        AssetKind.crypto => 0,
        AssetKind.other => 1,
      };

  bool get isUnitAsset =>
      this == AssetKind.property || this == AssetKind.vehicle;

  IconData get icon => switch (this) {
        AssetKind.crypto => Icons.currency_bitcoin,
        AssetKind.gold => Icons.diamond_outlined,
        AssetKind.cash => Icons.attach_money,
        AssetKind.property => Icons.home_work_outlined,
        AssetKind.vehicle => Icons.directions_car_outlined,
        AssetKind.other => Icons.account_balance_wallet_outlined,
      };

  Color get color => switch (this) {
        AssetKind.crypto => const Color(0xFFF7931A),
        AssetKind.gold => const Color(0xFFE8C547),
        AssetKind.cash => const Color(0xFF3DDB7E),
        AssetKind.property => const Color(0xFF5B8DEF),
        AssetKind.vehicle => const Color(0xFF9B8CFF),
        AssetKind.other => const Color(0xFF4ECDC4),
      };

  String get helpText => switch (this) {
        AssetKind.property =>
          'برای ملک معمولاً تعداد ۱ است؛ بهای خرید و ارزش فعلی را به تومان وارد کنید.',
        AssetKind.vehicle =>
          'برای خودرو معمولاً تعداد ۱ است؛ بهای خرید و ارزش فعلی را به تومان وارد کنید.',
        AssetKind.gold => 'مقدار را به گرم و قیمت هر گرم را وارد کنید.',
        AssetKind.cash => 'موجودی تتر یا نقد را با قیمت هر واحد وارد کنید.',
        AssetKind.crypto =>
          'مقدار و قیمت خرید هر واحد را به تومان و دلار وارد کنید. قیمت فعلی تومانی از بازار زنده می‌آید؛ دلار فعلی معادل تومان ÷ تتر است.',
        AssetKind.other => 'هر دارایی دیگری با مقدار و قیمت تومانی.',
      };
}

/// Detect kind from name/symbol (and optional notes marker).
AssetKind detectAssetKind({
  required String name,
  String symbol = '',
  String notes = '',
}) {
  final marker = RegExp(r'\[kind:([a-z]+)\]', caseSensitive: false)
      .firstMatch(notes);
  if (marker != null) {
    final id = marker.group(1)!.toLowerCase();
    for (final k in AssetKind.values) {
      if (k.id == id) return k;
    }
  }

  final sym = symbol.trim().toUpperCase();
  final nm = name.trim();
  final lower = nm.toLowerCase();

  if (sym == 'GOLD' ||
      sym == 'XAU' ||
      sym == 'GERAM' ||
      sym == 'GRAM' ||
      (nm.contains('طلا') && !nm.contains('سکه') && !nm.contains('عیار'))) {
    return AssetKind.gold;
  }
  if ({'USDT', 'USD', 'DOLLAR', 'USDT.TMN', 'USDTTMN'}.contains(sym) ||
      nm.contains('تتر') ||
      nm.contains('دلار نقد') ||
      (nm.contains('دلار') && !nm.contains('سکه')) ||
      lower == 'usd' ||
      lower == 'usdt') {
    return AssetKind.cash;
  }
  if ({'REAL', 'PROPERTY', 'HOME', 'HOUSE', 'APT', 'LAND'}.contains(sym) ||
      nm.contains('ملک') ||
      nm.contains('آپارتمان') ||
      nm.contains('خانه') ||
      nm.contains('ویلا') ||
      nm.contains('زمین') ||
      nm.contains('مغازه') ||
      nm.contains('مستغلات')) {
    return AssetKind.property;
  }
  if ({'CAR', 'AUTO', 'VEHICLE', 'MOTOR'}.contains(sym) ||
      nm.contains('خودرو') ||
      nm.contains('ماشین') ||
      nm.contains('اتومبیل') ||
      nm.contains('موتورسیکلت') ||
      nm.contains('پژو') ||
      nm.contains('پراید') ||
      nm.contains('تیبا') ||
      nm.contains('سمند') ||
      nm.contains('دنا') ||
      nm.contains('شاهین')) {
    return AssetKind.vehicle;
  }
  if ({'BTC', 'ETH', 'BNB', 'SOL', 'XRP', 'DOGE', 'ADA', 'TRX', 'SHIB'}
          .contains(sym) ||
      nm.contains('بیت') ||
      nm.contains('اتریوم') ||
      lower.contains('bitcoin') ||
      lower.contains('ethereum')) {
    return AssetKind.crypto;
  }
  return AssetKind.other;
}

String notesWithKind(String notes, AssetKind kind) {
  final cleaned = notes
      .replaceAll(RegExp(r'\[kind:[a-z]+\]\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\[meta:\{.*?\}\]\s*', caseSensitive: false, dotAll: true), '')
      .trim();
  final tag = '[kind:${kind.id}]';
  if (cleaned.isEmpty) return tag;
  return '$tag $cleaned';
}

/// Free-text notes with `[kind:…]` / `[meta:…]` markers removed.
String stripKindMarker(String notes) => notes
    .replaceAll(RegExp(r'\[kind:[a-z]+\]\s*', caseSensitive: false), '')
    .replaceAll(RegExp(r'\[meta:\{.*?\}\]\s*', caseSensitive: false, dotAll: true), '')
    .trim();
