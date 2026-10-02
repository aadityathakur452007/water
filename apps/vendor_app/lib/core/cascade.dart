// Hand-rolled staggered list entrance for vendor_app.
//
// vendor_app must not add flutter_animate (no new dependencies), so the
// cascade is built by hand: one AnimationController per list, per-item
// Intervals, transform (slide) + opacity only. Zero Timers (widget-test
// safe — controllers run on Tickers, which the test binding owns), and a
// static render when the OS asks for reduced motion.
//
// Usage: wrap the scrollable in [CascadeScope] (itemCount = entering rows;
// headers stay static), then wrap each row in [CascadeItem] with its index.

import 'package:flutter/material.dart';

/// Each item starts 12% of the run after the previous one; every item is a
/// 250ms-equivalent easeOut fade + rise and all finish together.
const double _kStep = 0.12;

/// Provides one entrance controller to descendant [CascadeItem]s.
class CascadeScope extends StatefulWidget {
  const CascadeScope({
    super.key,
    required this.itemCount,
    required this.child,
  });

  /// Number of entering items (headers/static blocks excluded).
  final int itemCount;
  final Widget child;

  @override
  State<CascadeScope> createState() => CascadeScopeState();

  static CascadeScopeState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CascadeInherited>()!.state;
}

class CascadeScopeState extends State<CascadeScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Runs once, on the first build that actually has items. Later count
  /// changes reuse the finished controller (no replay on refresh).
  void _maybeStart() {
    if (_started || widget.itemCount <= 0) return;
    _started = true;
    _controller.forward();
  }

  Animation<double> forIndex(int i) {
    final begin = (i * _kStep).clamp(0.0, 0.8);
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, 1.0, curve: Curves.easeOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    _maybeStart();
    return _CascadeInherited(state: this, child: widget.child);
  }
}

class _CascadeInherited extends InheritedWidget {
  const _CascadeInherited({required this.state, required super.child});

  final CascadeScopeState state;

  @override
  bool updateShouldNotify(_CascadeInherited old) => false;
}

/// One entering row: fade + gentle rise on the scope's controller.
/// Fully visible and static when the OS asks for reduced motion.
class CascadeItem extends StatelessWidget {
  const CascadeItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final anim = CascadeScope.of(context).forIndex(index);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: anim.drive(
          Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ),
        ),
        child: child,
      ),
    );
  }
}
