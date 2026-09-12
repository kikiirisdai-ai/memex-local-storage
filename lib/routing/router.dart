// Copyright 2024 The Memex team. All rights reserved.
// Compass-aligned: GoRouter for declarative routing.
// ViewModels are created in route builders and passed to screens.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/hybrid_card_retriever.dart';
import 'package:memex/ui/timeline/view_models/card_search_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/card_search_screen.dart';
import 'package:memex/ui/memory/view_models/memory_viewmodel.dart';
import 'package:memex/ui/memory/widgets/memory_screen.dart';
import 'package:memex/ui/character/widgets/character_config_screen.dart';
import 'package:memex/ui/character/widgets/tavern_import_screen.dart';
import 'package:memex/ui/character/view_models/character_viewmodel.dart';
import 'package:memex/ui/chat/view_models/chat_viewmodel.dart';
import 'package:memex/ui/chat/widgets/chat_history_screen.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';
import 'package:memex/ui/settings/widgets/personal_center_screen.dart';
import 'package:memex/ui/user_setup/widgets/user_setup_screen.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/ui/goals/widgets/goals_list_page.dart';
import 'package:memex/routing/routes.dart';

/// Creates the app [GoRouter]. Root content is built by [rootBuilder].
GoRouter createAppRouter(
  GlobalKey<NavigatorState> navigatorKey,
  Widget Function() rootBuilder,
) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => rootBuilder(),
      ),
      GoRoute(
        path: AppRoutes.userSetup,
        builder: (context, state) => UserSetupScreen(
          onUserCreated: () {
            context.go(AppRoutes.home);
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.memory,
        builder: (context, state) {
          final vm = MemoryViewModel(router: context.read<MemexRouter>());
          vm.loadMemory();
          return MemoryScreen(viewModel: vm);
        },
      ),
      GoRoute(
        path: AppRoutes.characterConfig,
        builder: (context, state) {
          final vm = CharacterViewModel(router: context.read<MemexRouter>());
          vm.loadCharacters();
          return CharacterConfigScreen(viewModel: vm);
        },
      ),
      GoRoute(
        path: AppRoutes.chatHistory,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final agentName = extra['agentName'] as String?;
          final title = extra['title'] as String?;
          final vm = ChatViewModel(
            router: context.read<MemexRouter>(),
            agentName: agentName,
          );
          return ChatHistoryScreen(
            viewModel: vm,
            agentName: agentName,
            title: title,
          );
        },
      ),
      GoRoute(
        path: '${AppRoutes.timelineCardDetail}/:id',
        builder: (context, state) {
          final cardId = state.pathParameters['id'] ?? '';
          return TimelineCardDetailScreen(cardId: cardId);
        },
      ),
      GoRoute(
        path: AppRoutes.cardSearch,
        builder: (context, state) => CardSearchScreen(
          viewModel: CardSearchViewModel(
            retriever: HybridCardRetriever.instance,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.personalCenter,
        builder: (_, __) => const PersonalCenterScreen(),
      ),
      GoRoute(
        path: AppRoutes.tavernImport,
        builder: (_, __) => const TavernImportScreen(),
      ),
      GoRoute(
        path: AppRoutes.goals,
        builder: (_, __) => GoalsListPage(goalService: GoalService.instance),
      ),
    ],
  );
}
