import 'package:flutter/material.dart';
import 'package:invest/ui/theme/app_theme.dart';

Color tgSettingsPageBg(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? AppTheme.bg : const Color(0xFFEFF0F3);
}

Color tgSettingsGroupBg(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? AppTheme.card : Colors.white;
}

Color tgSettingsDivider(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? const Color(0xFF2A3A32) : const Color(0xFFE5E5EA);
}

/// Telegram-style section: muted caption + rounded grouped rows.
class TgSettingsSection extends StatelessWidget {
  const TgSettingsSection({
    super.key,
    this.title,
    required this.children,
  });

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
              child: Text(
                title!,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.muted,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
          Container(
            decoration: BoxDecoration(
              color: tgSettingsGroupBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class TgSettingsIcon extends StatelessWidget {
  const TgSettingsIcon({
    super.key,
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 29,
      height: 29,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}

/// One Telegram settings row (icon · title · value/switch/chevron).
class TgSettingsTile extends StatelessWidget {
  const TgSettingsTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.destructive = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final titleColor = destructive ? AppTheme.negative : AppTheme.text;

    Widget? end;
    if (trailing != null) {
      end = trailing;
    } else if (onTap != null) {
      end = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null && value!.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, color: AppTheme.muted),
              ),
            ),
          const Icon(
            Icons.chevron_left_rounded,
            color: AppTheme.muted,
            size: 22,
          ),
        ],
      );
    } else if (value != null) {
      end = Text(
        value!,
        style: const TextStyle(fontSize: 15, color: AppTheme.muted),
      );
    }

    final row = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              TgSettingsIcon(icon: icon, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: titleColor,
                        height: 1.25,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (end != null) end,
            ],
          ),
        ),
      ),
    );

    if (!showDivider) return row;

    return Column(
      children: [
        row,
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 53),
          child: Divider(
            height: 1,
            thickness: 0.6,
            color: tgSettingsDivider(context),
          ),
        ),
      ],
    );
  }
}

class TgSettingsSwitchTile extends StatelessWidget {
  const TgSettingsSwitchTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return TgSettingsTile(
      icon: icon,
      iconColor: iconColor,
      title: title,
      subtitle: subtitle,
      showDivider: showDivider,
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

Future<T?> showTgChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required List<({T value, String label})> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: tgSettingsGroupBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.muted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.title,
                ),
              ),
            ),
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0)
                Divider(height: 1, color: tgSettingsDivider(ctx)),
              ListTile(
                onTap: () => Navigator.pop(ctx, options[i].value),
                title: Text(
                  options[i].label,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 16, color: AppTheme.text),
                ),
                trailing: options[i].value == selected
                    ? const Icon(Icons.check_rounded, color: AppTheme.positive)
                    : null,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
