import 'package:flutter/material.dart';

/// A clear, theme-colored name treatment for builder identity headers.
class BuilderNameHeading extends StatelessWidget {
  final String name;
  final double fontSize;
  final bool showAccent;

  const BuilderNameHeading({
    super.key,
    required this.name,
    this.fontSize = 25,
    this.showAccent = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: fontSize,
            height: 1.08,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.55,
          ),
        ),
        if (showAccent) ...[
          const SizedBox(height: 6),
          Container(
            width: 30,
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(
                colors: [colors.primary, colors.tertiary],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
