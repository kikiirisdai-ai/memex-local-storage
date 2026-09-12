import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:memex/data/services/card_retriever.dart';
import 'package:memex/ui/timeline/view_models/card_search_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';

/// Full-screen card search page: keyword search over timeline cards with
/// optional date-range filtering. Mirrors SettingsSearchScreen's structure
/// (StatefulWidget + ListenableBuilder over a plain-notify ViewModel).
///
/// Localization note: user-facing strings here are literal Chinese rather
/// than ARB-sourced. This repo's ARB set spans ~13 locale files; adding and
/// syncing keys across all of them was out of scope for this task. TODO:
/// move these strings into app_en.arb/app_zh.arb (+ other locales) when the
/// feature is localized for non-zh users.
class CardSearchScreen extends StatefulWidget {
  const CardSearchScreen({super.key, required this.viewModel});

  final CardSearchViewModel viewModel;

  @override
  State<CardSearchScreen> createState() => _CardSearchScreenState();
}

class _CardSearchScreenState extends State<CardSearchScreen> {
  final TextEditingController _textController = TextEditingController();
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final vm = widget.viewModel;
    final now = DateTime.now();
    final initialRange = (vm.from != null && vm.to != null)
        ? DateTimeRange(start: vm.from!, end: vm.to!)
        : null;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: initialRange,
    );

    if (picked != null) {
      vm.setDateRange(picked.start, picked.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const ValueKey('card_search_field'),
          controller: _textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索你的记录',
            border: InputBorder.none,
          ),
          onChanged: widget.viewModel.updateQuery,
        ),
        actions: [
          IconButton(
            key: const ValueKey('card_search_date_range_button'),
            icon: const Icon(Icons.date_range),
            tooltip: '按日期筛选',
            onPressed: _pickDateRange,
          ),
          // TODO(card-search): tag filter chips deferred — the ViewModel
          // already supports toggleTag/selectedTags; wire chips once a
          // convenient tag source (e.g. distinct tags across recent cards)
          // is available.
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final vm = widget.viewModel;

    if (vm.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vm.error != null) {
      return Center(child: Text(vm.error!));
    }

    if (vm.query.trim().isEmpty) {
      return const Center(child: Text('输入关键词搜索'));
    }

    if (vm.results.isEmpty) {
      return const Center(child: Text('没有找到相关记录'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: vm.results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildResultTile(context, vm.results[index]),
    );
  }

  Widget _buildResultTile(BuildContext context, CardHit hit) {
    return Material(
      key: ValueKey('card_search_result_${hit.cardId}'),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // factId contains '/' and '#' (e.g. 2025/11/23.md#ts_1), which break
        // GoRouter's '/card/:id' single-segment matching. Open the detail
        // screen directly by object, matching how the timeline and chat do it.
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TimelineCardDetailScreen(cardId: hit.cardId),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hit.title.isEmpty ? '(无标题)' : hit.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hit.snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                _dateFormat.format(hit.date),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
