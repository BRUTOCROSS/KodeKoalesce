import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'avatar_menu_button.dart';
import 'collapsible_chrome.dart';

class SectionPage extends StatelessWidget {
  final VoidCallback onOpenDrawer;
  final bool chromeVisible;
  final String eyebrow, title, subtitle, action;
  final IconData icon;
  final Widget child;
  final VoidCallback? onAction;
  final VoidCallback? onSearch;
  final VoidCallback? onSearchClose;
  final ValueChanged<String>? onSearchChanged;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final bool searchExpanded;
  final String searchHint;
  const SectionPage({
    super.key,
    required this.onOpenDrawer,
    required this.chromeVisible,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.icon,
    required this.child,
    this.onAction,
    this.onSearch,
    this.onSearchClose,
    this.onSearchChanged,
    this.searchController,
    this.searchFocusNode,
    this.searchExpanded = false,
    this.searchHint = 'Search',
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      CollapsibleChrome(
        visible: chromeVisible,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 17, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AvatarMenuButton(onPressed: onOpenDrawer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: searchExpanded
                          ? TextField(
                              key: const ValueKey('section-search-field'),
                              controller: searchController,
                              focusNode: searchFocusNode,
                              onChanged: onSearchChanged,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: searchHint,
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: IconButton(
                                  tooltip: 'Close search',
                                  onPressed: onSearchClose,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                                isDense: true,
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            )
                          : Align(
                              key: const ValueKey('section-search-button'),
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                onPressed: onSearch ?? () {},
                                tooltip: 'Search',
                                icon: const Icon(Icons.search_rounded),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              Text(
                eyebrow,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.3,
                  color: AppColors.green,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 27,
                        letterSpacing: -.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: mutedText(context)),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onAction,
                  icon: Icon(icon, size: 18),
                  label: Text(action),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(color: outlineColor(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [child],
        ),
      ),
    ],
  );
}
