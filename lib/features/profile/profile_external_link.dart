import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Compact action for opening a public profile link outside the app.
class ProfileExternalLink extends StatelessWidget {
  final String label;
  final String url;
  final IconData icon;

  const ProfileExternalLink({
    super.key,
    required this.label,
    required this.url,
    required this.icon,
  });

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This profile link is invalid.')),
      );
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await const MethodChannel('com.kodekoalesce.app/share')
            .invokeMethod<void>('openUrl', {'url': uri.toString()});
        return;
      } on PlatformException {
        // Copy the URL if the platform cannot resolve a browser activity.
      } on MissingPluginException {
        // Fall back to copying on platforms without this channel.
      }
    }

    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$label link copied.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(18);
    return Tooltip(
      message: 'Open $label link',
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
            child: InkWell(
              onTap: () => _open(context),
              borderRadius: radius,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.primary.withValues(alpha: .19),
                      colors.surface.withValues(alpha: .72),
                    ],
                  ),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: .28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: .09),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 6, 10, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 27,
                        height: 27,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.primary.withValues(alpha: .16),
                        ),
                        child: Icon(icon, size: 15, color: colors.primary),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
