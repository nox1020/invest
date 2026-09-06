/// Official Iran CPI / inflation snapshot (SCI monthly preferred).
class IranInflationSnapshot {
  const IranInflationSnapshot({
    required this.period,
    required this.year,
    required this.month,
    required this.cpiIndex,
    required this.pointToPointPct,
    required this.monthlyPct,
    required this.annualPct,
    required this.history,
    required this.sourceLabel,
    required this.fetchedAt,
    this.baseYear = 1400,
  });

  /// Jalali period like `1405-03`.
  final String period;
  final int year;
  final int month;
  final double cpiIndex;

  /// تورم نقطه‌به‌نقطه (YoY).
  final double pointToPointPct;

  /// تورم ماهانه (MoM).
  final double monthlyPct;

  /// تورم سالانه / میانگین ۱۲ماهه.
  final double annualPct;

  /// Recent SCI monthly points (oldest → newest), including [period].
  final List<IranInflationPoint> history;

  final String sourceLabel;
  final DateTime fetchedAt;
  final int baseYear;

  String get periodLabel {
    const months = <String>[
      'فروردین',
      'اردیبهشت',
      'خرداد',
      'تیر',
      'مرداد',
      'شهریور',
      'مهر',
      'آبان',
      'آذر',
      'دی',
      'بهمن',
      'اسفند',
    ];
    final m = (month >= 1 && month <= 12) ? months[month - 1] : '—';
    return '$m $year';
  }

  Map<String, dynamic> toJson() => {
        'period': period,
        'year': year,
        'month': month,
        'cpi_index': cpiIndex,
        'point_to_point_pct': pointToPointPct,
        'monthly_pct': monthlyPct,
        'annual_pct': annualPct,
        'base_year': baseYear,
        'source_label': sourceLabel,
        'fetched_at': fetchedAt.toIso8601String(),
        'history': history.map((e) => e.toJson()).toList(),
      };

  factory IranInflationSnapshot.fromJson(Map<String, dynamic> json) {
    final hist = ((json['history'] as List?) ?? const [])
        .map((e) => IranInflationPoint.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return IranInflationSnapshot(
      period: (json['period'] as String?) ?? '',
      year: (json['year'] as num?)?.toInt() ?? 0,
      month: (json['month'] as num?)?.toInt() ?? 0,
      cpiIndex: (json['cpi_index'] as num?)?.toDouble() ?? 0,
      pointToPointPct: (json['point_to_point_pct'] as num?)?.toDouble() ?? 0,
      monthlyPct: (json['monthly_pct'] as num?)?.toDouble() ?? 0,
      annualPct: (json['annual_pct'] as num?)?.toDouble() ?? 0,
      baseYear: (json['base_year'] as num?)?.toInt() ?? 1400,
      sourceLabel: (json['source_label'] as String?) ?? 'مرکز آمار ایران',
      fetchedAt: DateTime.tryParse((json['fetched_at'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      history: hist,
    );
  }
}

class IranInflationPoint {
  const IranInflationPoint({
    required this.period,
    required this.year,
    required this.month,
    required this.cpiIndex,
    required this.pointToPointPct,
    required this.monthlyPct,
    required this.annualPct,
  });

  final String period;
  final int year;
  final int month;
  final double cpiIndex;
  final double pointToPointPct;
  final double monthlyPct;
  final double annualPct;

  String get shortLabel {
    const months = <String>[
      'فرو',
      'ارد',
      'خرد',
      'تیر',
      'مرد',
      'شهر',
      'مهر',
      'آبا',
      'آذر',
      'دی',
      'بهم',
      'اسف',
    ];
    final m = (month >= 1 && month <= 12) ? months[month - 1] : period;
    return '$m ${year % 100}';
  }

  Map<String, dynamic> toJson() => {
        'period': period,
        'year': year,
        'month': month,
        'cpi_index': cpiIndex,
        'point_to_point_pct': pointToPointPct,
        'monthly_pct': monthlyPct,
        'annual_pct': annualPct,
      };

  factory IranInflationPoint.fromJson(Map<String, dynamic> json) =>
      IranInflationPoint(
        period: (json['period'] as String?) ?? '',
        year: (json['year'] as num?)?.toInt() ?? 0,
        month: (json['month'] as num?)?.toInt() ?? 0,
        cpiIndex: (json['cpi_index'] as num?)?.toDouble() ?? 0,
        pointToPointPct: (json['point_to_point_pct'] as num?)?.toDouble() ?? 0,
        monthlyPct: (json['monthly_pct'] as num?)?.toDouble() ?? 0,
        annualPct: (json['annual_pct'] as num?)?.toDouble() ?? 0,
      );
}

/// One of the standard inflation type cards shown in the UI.
class IranInflationTypeInfo {
  const IranInflationTypeInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.valuePct,
    required this.unitHint,
  });

  final String id;
  final String title;
  final String subtitle;
  final double valuePct;
  final String unitHint;
}
