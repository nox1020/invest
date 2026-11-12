import 'package:flutter/material.dart';
import 'package:invest/domain/models/ai_audit_report.dart';
import 'package:invest/ui/theme/app_theme.dart';

const aiHealthAmber = Color(0xFFFFB340);

Color aiHealthColor(int score) {
  if (score >= aiScoreGood) return AppTheme.positive;
  if (score >= aiScoreWatch) return aiHealthAmber;
  return AppTheme.negative;
}
