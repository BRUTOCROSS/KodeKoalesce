import 'package:flutter/material.dart';

class AppColors {
  static const ink = Color(0xFF15231D);
  static const green = Color(0xFF2D7557);
  static const canvas = Color(0xFFF7F8F5);
}

Color mutedText(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;
Color softSurface(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerHighest;
Color outlineColor(BuildContext context) =>
    Theme.of(context).colorScheme.outlineVariant;
