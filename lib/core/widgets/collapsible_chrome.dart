import 'package:flutter/material.dart';

class CollapsibleChrome extends StatelessWidget {
  final bool visible;
  final Alignment alignment;
  final Widget child;

  const CollapsibleChrome({
    super.key,
    required this.visible,
    this.alignment = Alignment.topCenter,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedAlign(
      alignment: alignment,
      heightFactor: visible ? 1 : 0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      child: AnimatedSlide(
        offset: visible
            ? Offset.zero
            : Offset(0, alignment == Alignment.bottomCenter ? 0.12 : -0.12),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        child: child,
      ),
    ),
  );
}
