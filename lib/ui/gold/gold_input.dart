import 'package:flutter/services.dart';
import 'package:invest/domain/utils/gold_number_input.dart';

/// Digits and decimal marks for weights and percents.
final goldDecimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹٠-٩.,٫]'));

/// Live thousands grouping for Toman fields (`100000000` → `100,000,000`).
/// Persian/Arabic digits become Latin; the caret stays after the same digit.
class GoldTomanFormatter extends TextInputFormatter {
  const GoldTomanFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = groupTomanDigits(newValue.text);
    final caret =
        newValue.selection.isValid ? newValue.selection.end.clamp(0, newValue.text.length) : newValue.text.length;
    // Digits left of the caret in the raw text → same count in the result.
    final before = groupTomanDigits(newValue.text.substring(0, caret)).replaceAll(',', '').length;
    var seen = 0, pos = 0;
    while (pos < text.length && seen < before) {
      if (text[pos] != ',') seen++;
      pos++;
    }
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: pos));
  }
}

/// `100,000,000` for a chip / prefill value.
String goldTomanText(double v) => groupTomanDigits(v.isFinite ? v.round().toString() : '');
