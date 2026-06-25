import 'package:flutter/material.dart';

/// Shared motion tokens for consistent, fluid interactions across Drop.
abstract final class DropMotion {
  static const fast = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 450);

  static const standard = Curves.easeOutCubic;
  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const spring = Curves.easeOutBack;
}

class DropPageRoute<T> extends PageRouteBuilder<T> {
  DropPageRoute({required Widget page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: DropMotion.medium,
          reverseTransitionDuration: DropMotion.fast,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: DropMotion.enter,
              reverseCurve: DropMotion.exit,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.035),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}

class DropSwitcherTransition extends StatelessWidget {
  const DropSwitcherTransition({
    super.key,
    required this.child,
    required this.animation,
  });

  final Widget child;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: DropMotion.enter,
      reverseCurve: DropMotion.exit,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
