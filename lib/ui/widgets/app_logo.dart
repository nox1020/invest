import 'package:flutter/material.dart';
import 'package:invest/config/app_config.dart';
import 'package:invest/ui/theme/app_theme.dart';

/// Small square mark for app bars and lists.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/app_icon.png',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Text(
            'V+',
            style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Branded V+ mark for login, headers, and splash-style layouts.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 88,
    this.showTitle = true,
    this.titleSize = 28,
  });

  final double size;
  final bool showTitle;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppMark(size: size),
        if (showTitle) ...[
          SizedBox(height: size * 0.18),
          Text(
            AppConfig.appName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              color: AppTheme.title,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ],
    );
  }
}
