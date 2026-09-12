import 'package:flutter/foundation.dart';

import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/utils/result.dart';

/// ViewModel for the Chat history page. Holds session list and delegates to [MemexRouter].
class ChatViewModel extends ChangeNotifier {
  ChatViewModel({
    required MemexRouter router,
    this.agentName,
  }) : _router = router;

  final MemexRouter _router;
  final String? agentName;

  List<Map<String, dynamic>> sessions = [];
  bool isLoading = false;

  Future<void> loadSessions() async {
    isLoading = true;
    notifyListeners();
    final result = await _router.fetchChatSessions(agentName: agentName);
    result.when(
      onOk: (list) => sessions = list,
      onError: (_, __) {},
    );
    isLoading = false;
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId, int index) async {
    await _router.deleteChatSession(sessionId);
    if (index >= 0 && index < sessions.length) {
      sessions.removeAt(index);
      notifyListeners();
    }
  }
}
