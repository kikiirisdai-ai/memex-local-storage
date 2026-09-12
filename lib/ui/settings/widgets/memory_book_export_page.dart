import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:memex/ui/settings/view_models/memory_book_export_viewmodel.dart';

/// Memory-book export screen: title + date-range + (deferred) tag filters,
/// a generate button, PDF-build progress, and error display. Mirrors
/// CardSearchScreen's structure (StatefulWidget + ListenableBuilder over a
/// plain-notify ViewModel).
///
/// Localization note: user-facing strings here are literal Chinese rather
/// than ARB-sourced, matching CardSearchScreen's precedent. TODO: move these
/// strings into app_en.arb/app_zh.arb (+ other locales) when the feature is
/// localized for non-zh users.
class MemoryBookExportPage extends StatefulWidget {
  const MemoryBookExportPage({super.key, required this.viewModel});

  final MemoryBookExportViewModel viewModel;

  @override
  State<MemoryBookExportPage> createState() => _MemoryBookExportPageState();
}

class _MemoryBookExportPageState extends State<MemoryBookExportPage> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.viewModel.title);
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  @override
  void dispose() {
    _titleController.dispose();
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
      appBar: AppBar(title: const Text('导出记忆册')),
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final vm = widget.viewModel;

    // Keep the title field in sync when setDateRange auto-refreshes it
    // (only while the user hasn't manually diverged the text).
    if (_titleController.text != vm.title) {
      _titleController.value = _titleController.value.copyWith(
        text: vm.title,
        selection: TextSelection.collapsed(offset: vm.title.length),
        composing: TextRange.empty,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const ValueKey('memory_book_title_field'),
          controller: _titleController,
          decoration: const InputDecoration(labelText: '标题'),
          onChanged: vm.setTitle,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const ValueKey('memory_book_date_range_button'),
          onPressed: _pickDateRange,
          icon: const Icon(Icons.date_range),
          label: Text(
            vm.from != null && vm.to != null
                ? '${_dateFormat.format(vm.from!)} – ${_dateFormat.format(vm.to!)}'
                : '选择日期范围',
          ),
        ),
        // TODO(memory-book-export): tag filter chips deferred — the
        // ViewModel already supports selectedTags/toggleTag; wire chips
        // once a convenient tag source (e.g. distinct tags across the
        // selected range) is available.
        const SizedBox(height: 24),
        ElevatedButton(
          key: const ValueKey('memory_book_generate_button'),
          onPressed: vm.generating ? null : () => vm.generate(context),
          child: const Text('生成 PDF'),
        ),
        if (vm.generating) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: vm.progress),
        ],
        if (vm.error != null) ...[
          const SizedBox(height: 16),
          Text(
            vm.error!,
            key: const ValueKey('memory_book_error_text'),
            style: const TextStyle(color: Colors.red),
          ),
        ],
      ],
    );
  }
}
