import 'package:flutter/material.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/domain/utils/dates.dart';
import 'package:shamsi_date/shamsi_date.dart';

/// Picks a calendar day using the app settings calendar, returns ISO `YYYY-MM-DD`.
///
/// Storage stays Gregorian ISO everywhere; only the picker/UI follow [calendar].
Future<String?> pickAppDate(
  BuildContext context, {
  required String calendar,
  String? initialIso,
  DateTime? firstDate,
  DateTime? lastDate,
  String helpText = 'انتخاب تاریخ',
}) async {
  final first = firstDate ?? DateTime(2000);
  final last = lastDate ?? DateTime.now().add(const Duration(days: 1));
  var initial = DateTime.now();
  final normalized = tryNormalizeToIso(initialIso);
  if (normalized != null) {
    initial = parseIsoDate(normalized);
  }
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;

  if (calendar == AppConfig.calendarJalali) {
    return _pickJalaliDate(
      context,
      initial: initial,
      first: first,
      last: last,
      helpText: helpText,
    );
  }

  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
    helpText: helpText,
  );
  if (picked == null) return null;
  return toIsoDate(picked);
}

Future<String?> _pickJalaliDate(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
  required String helpText,
}) async {
  var j = Jalali.fromDateTime(initial);
  final firstJ = Jalali.fromDateTime(first);
  final lastJ = Jalali.fromDateTime(last);

  return showDialog<String>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (ctx, setLocal) {
          final monthLen = j.monthLength;
          if (j.day > monthLen) {
            j = Jalali(j.year, j.month, monthLen);
          }

          final years = [
            for (var y = firstJ.year; y <= lastJ.year; y++) y,
          ];
          final days = [for (var d = 1; d <= monthLen; d++) d];

          bool inRange(Jalali candidate) {
            final g = candidate.toDateTime();
            final dayOnly = DateTime(g.year, g.month, g.day);
            final f = DateTime(first.year, first.month, first.day);
            final l = DateTime(last.year, last.month, last.day);
            return !dayOnly.isBefore(f) && !dayOnly.isAfter(l);
          }

          return AlertDialog(
            title: Text(helpText),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatDisplayDate(toIsoDate(j.toDateTime()), AppConfig.calendarJalali),
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<int>(
                        // ignore: deprecated_member_use
                        value: j.year,
                        decoration: const InputDecoration(
                          labelText: 'سال',
                          isDense: true,
                        ),
                        items: years
                            .map(
                              (y) => DropdownMenuItem(
                                value: y,
                                child: Text('$y'),
                              ),
                            )
                            .toList(),
                        onChanged: (y) {
                          if (y == null) return;
                          setLocal(() {
                            final maxDay = Jalali(y, j.month, 1).monthLength;
                            j = Jalali(y, j.month, j.day.clamp(1, maxDay));
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: DropdownButtonFormField<int>(
                        // ignore: deprecated_member_use
                        value: j.month,
                        decoration: const InputDecoration(
                          labelText: 'ماه',
                          isDense: true,
                        ),
                        items: [
                          for (var m = 1; m <= 12; m++)
                            DropdownMenuItem(
                              value: m,
                              child: Text(jalaliMonthNamesFa[m - 1]),
                            ),
                        ],
                        onChanged: (m) {
                          if (m == null) return;
                          setLocal(() {
                            final maxDay = Jalali(j.year, m, 1).monthLength;
                            j = Jalali(j.year, m, j.day.clamp(1, maxDay));
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<int>(
                        // ignore: deprecated_member_use
                        value: j.day.clamp(1, monthLen),
                        decoration: const InputDecoration(
                          labelText: 'روز',
                          isDense: true,
                        ),
                        items: days
                            .map(
                              (d) => DropdownMenuItem(
                                value: d,
                                child: Text('$d'),
                              ),
                            )
                            .toList(),
                        onChanged: (d) {
                          if (d == null) return;
                          setLocal(() => j = Jalali(j.year, j.month, d));
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف'),
              ),
              ElevatedButton(
                onPressed: inRange(j)
                    ? () => Navigator.pop(ctx, toIsoDate(j.toDateTime()))
                    : null,
                child: const Text('تأیید'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// List tile that shows and picks a date with the active app calendar.
class AppDateTile extends StatelessWidget {
  const AppDateTile({
    super.key,
    required this.label,
    required this.isoDate,
    required this.calendar,
    required this.onChanged,
    this.contentPadding,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final String isoDate;
  final String calendar;
  final ValueChanged<String> onChanged;
  final EdgeInsetsGeometry? contentPadding;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: contentPadding ?? EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(formatFlexibleDisplayDate(isoDate, calendar)),
      trailing: const Icon(Icons.calendar_today_outlined, size: 18),
      onTap: () async {
        final picked = await pickAppDate(
          context,
          calendar: calendar,
          initialIso: isoDate,
          firstDate: firstDate,
          lastDate: lastDate,
          helpText: label,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
