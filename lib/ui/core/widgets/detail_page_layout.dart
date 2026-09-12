import 'package:flutter/material.dart';
import 'package:memex/ui/core/widgets/back_button.dart';
import 'package:memex/utils/user_storage.dart';

class DetailPageLayout extends StatelessWidget {
  final String title;
  final String icon;
  final String? type;
  final Widget child;
  final String subTitle;
  final List<Widget>? actions;

  const DetailPageLayout({
    super.key,
    required this.title,
    required this.icon,
    this.type,
    required this.child,
    this.subTitle = '',
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Top spacing
              SliverToBoxAdapter(
                child: SizedBox(height: topPadding + 56),
              ),

              // Content
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                  child: child,
                ),
              ),
            ],
          ),

          // Top bar: back + title + actions
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xFFF7F8FA),
              padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 12),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      UserStorage.l10n.aiInsightDetail,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0A0A0A),
                      ),
                    ),
                  ),
                  if (actions != null) ...actions!,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
