import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:invest/ui/theme/app_theme.dart';

/// One shortcut inside [DashSpeedDial].
class SpeedDialAction {
  const SpeedDialAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.id,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Stable key suffix (widget key = ValueKey(id)).
  final String id;
}

/// Telegram-style expanding FAB pinned bottom-left (the trailing edge in RTL).
///
/// Wrap the scrollable [child]; the dial floats above it, dims the page while
/// open, closes on scrim tap / back, and slides away while scrolling down.
class DashSpeedDial extends StatefulWidget {
  const DashSpeedDial({
    super.key,
    required this.child,
    required this.actions,
    this.enabled = true,
  });

  final Widget child;
  final List<SpeedDialAction> actions;
  final bool enabled;

  /// Bottom padding a scrollable under the dial should keep free.
  static const double reserve = 88;

  @override
  State<DashSpeedDial> createState() => DashSpeedDialState();
}

class DashSpeedDialState extends State<DashSpeedDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 220),
  );
  bool _hidden = false;

  bool get isOpen =>
      _c.status == AnimationStatus.forward ||
      _c.status == AnimationStatus.completed;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void toggle() => isOpen ? close() : open();

  void open() {
    setState(() => _hidden = false);
    _c.forward();
  }

  void close() {
    _c.reverse();
    setState(() {});
  }

  void _run(SpeedDialAction a) {
    _c.value = 0;
    setState(() {});
    a.onTap();
  }

  bool _onScroll(UserScrollNotification n) {
    if (isOpen || n.depth != 0) return false;
    final hide = n.direction == ScrollDirection.reverse;
    final show = n.direction == ScrollDirection.forward;
    if (hide && !_hidden) setState(() => _hidden = true);
    if (show && _hidden) setState(() => _hidden = false);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.actions.length;
    return PopScope(
      canPop: !isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isOpen) close();
      },
      child: Stack(
        children: [
          NotificationListener<UserScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
          if (widget.enabled) ...[
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                if (_c.value == 0) return const SizedBox.shrink();
                return Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('fab-scrim'),
                    behavior: HitTestBehavior.opaque,
                    onTap: close,
                    child: Semantics(
                      label: 'بستن میان‌برها',
                      button: true,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.55 * _c.value),
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              left: 16,
              bottom: 16,
              child: Directionality(
                // Pin to the physical left; label sits to the right of the
                // mini button like Telegram's mirrored layout.
                textDirection: TextDirection.ltr,
                child: AnimatedSlide(
                  offset: _hidden ? const Offset(0, 1.6) : Offset.zero,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < n; i++)
                        _item(widget.actions[i], n - 1 - i, n),
                      _main(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _item(SpeedDialAction a, int order, int n) {
    // order 0 = closest to the main button; it appears first.
    final start = (order / n) * 0.45;
    final anim = CurvedAnimation(
      parent: _c,
      curve: Interval(start, (start + 0.55).clamp(0, 1),
          curve: Curves.easeOutBack),
      reverseCurve:
          Interval(0, (0.5 + start).clamp(0, 1), curve: Curves.easeInCubic),
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        if (_c.value == 0) return const SizedBox.shrink();
        final v = anim.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - v)),
            child: Transform.scale(
              scale: 0.6 + 0.4 * v,
              alignment: Alignment.centerLeft,
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 4),
        child: Semantics(
          button: true,
          label: a.label,
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey(a.id),
            onTap: () => _run(a),
            borderRadius: BorderRadius.circular(24),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppTheme.positive.withValues(alpha: 0.35)),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 10,
                        offset: Offset(0, 3)),
                  ],
                ),
                child: Icon(a.icon, color: AppTheme.positive, size: 22),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x55000000),
                        blurRadius: 8,
                        offset: Offset(0, 2)),
                  ],
                ),
                child: Text(
                  a.label,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                      color: AppTheme.title,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _main() {
    return Semantics(
      button: true,
      label: isOpen ? 'بستن میان‌برها' : 'میان‌برها',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: AppTheme.positive.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Material(
          color: AppTheme.positive,
          shape: const CircleBorder(),
          child: InkWell(
            key: const ValueKey('fab-main'),
            customBorder: const CircleBorder(),
            onTap: toggle,
            child: SizedBox(
              width: 58,
              height: 58,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final v = Curves.easeInOut.transform(_c.value);
                  return Transform.rotate(
                    angle: v * 3.14159 / 4 * 3,
                    child: Stack(alignment: Alignment.center, children: [
                      Opacity(
                        opacity: 1 - v,
                        child: const Icon(Icons.edit_rounded,
                            color: AppTheme.bg, size: 24),
                      ),
                      Opacity(
                        opacity: v,
                        child: Transform.rotate(
                          angle: -3.14159 / 4 * 3 + 3.14159 / 4,
                          child: const Icon(Icons.add_rounded,
                              color: AppTheme.bg, size: 28),
                        ),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
