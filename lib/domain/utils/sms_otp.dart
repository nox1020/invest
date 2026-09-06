/// Parses OTP codes from Vinor-style SMS Retriever messages, e.g.
/// ```
/// <#> 94300
/// @vinor.ir #94300
/// 4R707/AKLt0
/// ```
class SmsOtp {
  SmsOtp._();

  /// Prefer 5-digit codes (Vinor); also accept common 4–8 digit OTPs.
  /// Ignores trailing 11-char app hashes used by SMS Retriever.
  static final RegExp matcher = RegExp(r'(?<![A-Za-z0-9])(\d{4,8})(?![A-Za-z0-9])');

  static String? extract(String? sms) {
    if (sms == null || sms.trim().isEmpty) return null;

    final text = sms.trim();

    // Explicit Vinor / hash-line forms: "#94300" or first line after "<#>"
    final hashTagged = RegExp(r'#(\d{4,8})\b').firstMatch(text);
    if (hashTagged != null) return hashTagged.group(1);

    final hashPrefix = RegExp(r'<#>\s*(\d{4,8})\b').firstMatch(text);
    if (hashPrefix != null) return hashPrefix.group(1);

    final match = matcher.firstMatch(text);
    return match?.group(1);
  }
}
