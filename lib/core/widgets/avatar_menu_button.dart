import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AvatarMenuButton extends StatelessWidget {
  final VoidCallback onPressed;
  const AvatarMenuButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Open menu',
    onPressed: onPressed,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
    icon: const CircleAvatar(
      radius: 17,
      backgroundColor: Color(0xFFD7E8DC),
      child: Icon(Icons.person_rounded, size: 20, color: AppColors.ink),
    ),
  );
}
