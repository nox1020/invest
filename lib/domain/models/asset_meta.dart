import 'dart:convert';

import 'package:invest/config/app_config.dart';
import 'package:invest/domain/models/asset_kind.dart';
import 'package:invest/domain/utils/dates.dart';

/// Type-specific asset details persisted as `[meta:{…}]` inside [Asset.notes].
///
/// Core valuation fields (qty / buy / current) stay on the Asset row so Vinor
/// remote create/update keep working; this map only holds extra attributes.
class AssetMeta {
  const AssetMeta({
    this.address,
    this.areaM2,
    this.usage,
    this.deedNotes,
    this.purchaseDate,
    this.brandModel,
    this.year,
    this.plate,
    this.mileageKm,
    this.color,
    this.purity,
    this.buyPriceUsd,
  });

  /// ملک — آدرس
  final String? address;

  /// ملک — متراژ (م²)
  final double? areaM2;

  /// ملک — کاربری: residential | commercial
  final String? usage;

  /// ملک — توضیحات سند / پلاک ثبتی
  final String? deedNotes;

  /// ملک / خودرو — تاریخ خرید (ترجیحاً ISO میلادی؛ نمایش با تقویم تنظیمات)
  final String? purchaseDate;

  /// خودرو — برند / مدل (در صورت تمایز از نام دارایی)
  final String? brandModel;

  /// خودرو — سال ساخت
  final int? year;

  /// خودرو — پلاک
  final String? plate;

  /// خودرو — کارکرد (کیلومتر)
  final double? mileageKm;

  /// خودرو — رنگ
  final String? color;

  /// طلا — عیار / خلوص
  final String? purity;

  /// بهای دلاری خرید واحد (ثبت دستی؛ برای دارایی‌های بدون لات باز)
  final double? buyPriceUsd;

  static const empty = AssetMeta();

  bool get isEmpty =>
      (address == null || address!.trim().isEmpty) &&
      areaM2 == null &&
      (usage == null || usage!.trim().isEmpty) &&
      (deedNotes == null || deedNotes!.trim().isEmpty) &&
      (purchaseDate == null || purchaseDate!.trim().isEmpty) &&
      (brandModel == null || brandModel!.trim().isEmpty) &&
      year == null &&
      (plate == null || plate!.trim().isEmpty) &&
      mileageKm == null &&
      (color == null || color!.trim().isEmpty) &&
      (purity == null || purity!.trim().isEmpty) &&
      (buyPriceUsd == null || buyPriceUsd! <= 0);

  Map<String, Object?> toJson() {
    final m = <String, Object?>{};
    void put(String k, Object? v) {
      if (v == null) return;
      if (v is String && v.trim().isEmpty) return;
      m[k] = v is String ? v.trim() : v;
    }

    put('address', address);
    put('areaM2', areaM2);
    put('usage', usage);
    put('deedNotes', deedNotes);
    put('purchaseDate', purchaseDate);
    put('brandModel', brandModel);
    put('year', year);
    put('plate', plate);
    put('mileageKm', mileageKm);
    put('color', color);
    put('purity', purity);
    if (buyPriceUsd != null && buyPriceUsd! > 0) {
      put('buyPriceUsd', buyPriceUsd);
    }
    return m;
  }

  factory AssetMeta.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return AssetMeta.empty;
    double? asDouble(Object? v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse('$v'.replaceAll(',', ''));
    }

    int? asInt(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.round();
      return int.tryParse('$v'.replaceAll(',', ''));
    }

    String? asStr(Object? v) {
      if (v == null) return null;
      final s = '$v'.trim();
      return s.isEmpty ? null : s;
    }

    final usd = asDouble(json['buyPriceUsd'] ?? json['buy_price_usd']);
    return AssetMeta(
      address: asStr(json['address']),
      areaM2: asDouble(json['areaM2'] ?? json['area']),
      usage: asStr(json['usage']),
      deedNotes: asStr(json['deedNotes'] ?? json['deed']),
      purchaseDate: asStr(json['purchaseDate']),
      brandModel: asStr(json['brandModel'] ?? json['model']),
      year: asInt(json['year']),
      plate: asStr(json['plate']),
      mileageKm: asDouble(json['mileageKm'] ?? json['mileage']),
      color: asStr(json['color']),
      purity: asStr(json['purity'] ?? json['ayar']),
      buyPriceUsd: (usd != null && usd > 0) ? usd : null,
    );
  }

  AssetMeta copyWith({
    String? address,
    double? areaM2,
    String? usage,
    String? deedNotes,
    String? purchaseDate,
    String? brandModel,
    int? year,
    String? plate,
    double? mileageKm,
    String? color,
    String? purity,
    double? buyPriceUsd,
  }) =>
      AssetMeta(
        address: address ?? this.address,
        areaM2: areaM2 ?? this.areaM2,
        usage: usage ?? this.usage,
        deedNotes: deedNotes ?? this.deedNotes,
        purchaseDate: purchaseDate ?? this.purchaseDate,
        brandModel: brandModel ?? this.brandModel,
        year: year ?? this.year,
        plate: plate ?? this.plate,
        mileageKm: mileageKm ?? this.mileageKm,
        color: color ?? this.color,
        purity: purity ?? this.purity,
        buyPriceUsd: buyPriceUsd ?? this.buyPriceUsd,
      );
}

/// Parsed notes: kind marker + optional meta JSON + free-text remainder.
class AssetNotesParts {
  const AssetNotesParts({
    required this.kind,
    required this.meta,
    required this.freeNotes,
  });

  final AssetKind? kind;
  final AssetMeta meta;
  final String freeNotes;
}

final _kindRe = RegExp(r'\[kind:([a-z]+)\]\s*', caseSensitive: false);
final _metaRe = RegExp(r'\[meta:(\{.*?\})\]\s*', caseSensitive: false, dotAll: true);

AssetNotesParts parseAssetNotes(String notes) {
  var rest = notes.trim();
  AssetKind? kind;
  var meta = AssetMeta.empty;

  final kindMatch = _kindRe.firstMatch(rest);
  if (kindMatch != null) {
    final id = kindMatch.group(1)!.toLowerCase();
    for (final k in AssetKind.values) {
      if (k.id == id) {
        kind = k;
        break;
      }
    }
    rest = rest.replaceFirst(_kindRe, '').trim();
  }

  final metaMatch = _metaRe.firstMatch(rest);
  if (metaMatch != null) {
    try {
      final decoded = jsonDecode(metaMatch.group(1)!) as Object?;
      if (decoded is Map) {
        meta = AssetMeta.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Keep free text if meta JSON is corrupt; do not throw.
    }
    rest = rest.replaceFirst(_metaRe, '').trim();
  }

  return AssetNotesParts(kind: kind, meta: meta, freeNotes: rest);
}

/// Encode kind + meta + free notes for round-trip through remote `notes`.
String encodeAssetNotes({
  required AssetKind kind,
  AssetMeta meta = AssetMeta.empty,
  String freeNotes = '',
}) {
  final parts = <String>['[kind:${kind.id}]'];
  if (!meta.isEmpty) {
    parts.add('[meta:${jsonEncode(meta.toJson())}]');
  }
  final free = freeNotes.trim();
  if (free.isNotEmpty) parts.add(free);
  return parts.join(' ');
}

/// Short Persian summary for portfolio cards (empty if nothing useful).
String assetMetaCardSummary(
  AssetKind kind,
  AssetMeta meta, {
  String freeNotes = '',
  String calendar = AppConfig.calendarJalali,
}) {
  final bits = <String>[];
  switch (kind) {
    case AssetKind.property:
      if (meta.areaM2 != null) {
        final a = meta.areaM2!;
        final s = (a - a.roundToDouble()).abs() < 1e-9 ? '${a.round()}' : '$a';
        bits.add('$s م²');
      }
      if (meta.usage == 'commercial') {
        bits.add('تجاری');
      } else if (meta.usage == 'residential') {
        bits.add('مسکونی');
      }
      if (meta.address != null && meta.address!.trim().isNotEmpty) {
        bits.add(meta.address!.trim());
      }
      if (meta.purchaseDate != null && meta.purchaseDate!.trim().isNotEmpty) {
        bits.add(formatFlexibleDisplayDate(meta.purchaseDate, calendar));
      }
    case AssetKind.vehicle:
      if (meta.plate != null && meta.plate!.trim().isNotEmpty) {
        bits.add(meta.plate!.trim());
      }
      if (meta.year != null) bits.add('${meta.year}');
      if (meta.mileageKm != null) {
        final km = meta.mileageKm!;
        final s =
            (km - km.roundToDouble()).abs() < 1e-9 ? '${km.round()}' : '$km';
        bits.add('$s km');
      }
      if (meta.color != null && meta.color!.trim().isNotEmpty) {
        bits.add(meta.color!.trim());
      }
      if (meta.purchaseDate != null && meta.purchaseDate!.trim().isNotEmpty) {
        bits.add(formatFlexibleDisplayDate(meta.purchaseDate, calendar));
      }
    case AssetKind.gold:
      if (meta.purity != null && meta.purity!.trim().isNotEmpty) {
        bits.add('عیار ${meta.purity!.trim()}');
      }
    case AssetKind.cash:
    case AssetKind.crypto:
    case AssetKind.stock:
    case AssetKind.other:
      break;
  }
  if (bits.isEmpty && freeNotes.trim().isNotEmpty) {
    return freeNotes.trim();
  }
  if (bits.isEmpty) return '';
  final line = bits.join(' · ');
  if (freeNotes.trim().isNotEmpty && kind == AssetKind.other) {
    return freeNotes.trim();
  }
  return line;
}

String usageLabelFa(String? usage) => switch (usage) {
      'commercial' => 'تجاری',
      'residential' => 'مسکونی',
      _ => '—',
    };
